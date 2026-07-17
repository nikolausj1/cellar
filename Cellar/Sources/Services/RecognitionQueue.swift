//
//  RecognitionQueue.swift
//  Cellar — Services
//
//  The heart of the whole architecture (PRD §5 principle 2, §6.2). A bottle is
//  created and slotted the instant the user taps a slot; recognition happens
//  somewhere behind that, on its own schedule, and NEVER holds up the caller.
//
//  THE ENFORCEMENT: `submit(...)` below is NOT `async` and returns `Void`. There is
//  nothing to await. A caller cannot accidentally block the add flow on this call
//  even by mistake — the compiler won't let them `await` something that isn't
//  async, and there's no result to wait for anyway. That is deliberate: the
//  invariant is enforced by the type signature, not by a comment telling callers
//  not to await it.
//
//  Persists pending recognitions to a local JSON file (survives app restart and
//  Pi/network outages independent of the SwiftData store), retries with capped
//  exponential backoff, and is idempotent against being resumed twice (e.g. app
//  relaunch while entries were still in flight).
//

import Foundation
import SwiftData

/// A recognition request waiting on the Pi. Not a SwiftData model — this is
/// Services-local, disk-backed state, independent of the PRD §8 schema. Visible
/// (not `private`) so `PendingEntryStore`, a sibling type in this file, can share it.
struct PendingRecognitionEntry: Codable, Sendable {
    let id: UUID
    let bottleID: UUID
    let photo: Data
    let hint: String?
    var attempts: Int
    let createdAt: Date
}

/// Minimal file-backed persistence for the pending queue. An actor so concurrent
/// reads/writes from multiple in-flight retries never race each other.
actor PendingEntryStore {
    private let url: URL
    private var cache: [PendingRecognitionEntry]?

    init(url: URL) {
        self.url = url
    }

    private func load() -> [PendingRecognitionEntry] {
        if let cache { return cache }
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([PendingRecognitionEntry].self, from: data)
        else {
            cache = []
            return []
        }
        cache = decoded
        return decoded
    }

    private func persist(_ entries: [PendingRecognitionEntry]) {
        cache = entries
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func all() -> [PendingRecognitionEntry] { load() }

    func append(_ entry: PendingRecognitionEntry) { persist(load() + [entry]) }

    func update(_ entry: PendingRecognitionEntry) {
        var entries = load()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        }
        persist(entries)
    }

    func remove(_ id: UUID) { persist(load().filter { $0.id != id }) }
}

public actor RecognitionQueue {
    public struct Configuration: Sendable {
        public var confidenceThreshold: Double
        public var baseBackoff: TimeInterval
        public var maxBackoff: TimeInterval

        public init(confidenceThreshold: Double = 0.85, baseBackoff: TimeInterval = 5, maxBackoff: TimeInterval = 300) {
            self.confidenceThreshold = confidenceThreshold
            self.baseBackoff = baseBackoff
            self.maxBackoff = maxBackoff
        }
    }

    private let container: ModelContainer
    private let client: PiClientProtocol
    private let store: PendingEntryStore
    private var configuration: Configuration
    private var inFlight: Set<UUID> = []

    public init(
        container: ModelContainer,
        client: PiClientProtocol,
        configuration: Configuration = .init(),
        storeURL: URL? = nil
    ) {
        self.container = container
        self.client = client
        self.configuration = configuration
        self.store = PendingEntryStore(url: storeURL ?? Self.defaultStoreURL())
    }

    private static func defaultStoreURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("Cellar", isDirectory: true).appendingPathComponent("RecognitionQueue.json")
    }

    public func updateConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
    }

    /// Fire-and-forget, by construction: not `async`, returns nothing. Called the
    /// instant a bottle is created (PRD §6.2 step 3 must never wait on step 2). All
    /// this does synchronously is hand a struct to a background Task; the actual
    /// disk write and network call both happen off this call's stack.
    nonisolated public func submit(bottleID: UUID, photo: Data, hint: String? = nil) {
        let entry = PendingRecognitionEntry(id: UUID(), bottleID: bottleID, photo: photo, hint: hint, attempts: 0, createdAt: .now)
        Task { await self.enqueueAndDrain(entry) }
    }

    /// Call once at app launch to resume anything left over from a previous run —
    /// killed app, killed Pi, no network at the time. Safe to call more than once;
    /// `process(_:)` is idempotent (skips a bottle that already has a `wine` set).
    public func resumePending() async {
        await drain()
    }

    private func enqueueAndDrain(_ entry: PendingRecognitionEntry) async {
        await store.append(entry)
        await drain()
    }

    private func drain() async {
        for entry in await store.all() where !inFlight.contains(entry.id) {
            inFlight.insert(entry.id)
            Task { await self.process(entry) }
        }
    }

    private func process(_ entry: PendingRecognitionEntry) async {
        defer { inFlight.remove(entry.id) }
        do {
            let result = try await client.recognize(image: entry.photo, hint: entry.hint)
            try await apply(result, toBottleID: entry.bottleID, photo: entry.photo, confidenceThreshold: configuration.confidenceThreshold)
            await store.remove(entry.id)
        } catch {
            await retryLater(entry)
        }
    }

    private func retryLater(_ entry: PendingRecognitionEntry) async {
        var updated = entry
        updated.attempts += 1
        await store.update(updated)

        let delay = backoffDelay(forAttempt: updated.attempts)
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            // Re-drain rather than re-processing this one entry directly: another
            // resumePending() or submit() may have already retried it, and drain()
            // is naturally idempotent via `inFlight`.
            await self.drain()
        }
    }

    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let exponential = configuration.baseBackoff * pow(2.0, Double(max(0, attempt - 1)))
        return min(exponential, configuration.maxBackoff)
    }

    /// Attaches a resolved wine to its bottle, or files a ReviewItem if confidence
    /// is below threshold. Runs on the main actor because SwiftData ModelContext
    /// is safest driven from one consistent context/thread.
    @MainActor
    private func apply(_ result: RecognizeResult, toBottleID bottleID: UUID, photo: Data, confidenceThreshold: Double) async throws {
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<Bottle>(predicate: #Predicate { $0.id == bottleID })
        guard let bottle = try context.fetch(descriptor).first else {
            // Bottle was deleted before recognition came back. Nothing to attach to.
            return
        }
        guard bottle.wine == nil else {
            // Already resolved (e.g. a resumed duplicate drain). Idempotent no-op.
            return
        }

        if result.confidence >= confidenceThreshold, let best = result.candidates.first {
            let wine = try Self.findOrCreateWine(matching: best, in: context)
            bottle.wine = wine
        } else {
            let review = ReviewItem(
                photo: photo,
                candidates: result.candidates,
                confidence: result.confidence,
                source: .phone,
                bottle: bottle
            )
            context.insert(review)
        }

        try context.save()
    }

    /// Dedupes by (producer, name, vintage) so two bottles of the same wine added
    /// back to back end up pointing at ONE Wine record, not two.
    @MainActor
    private static func findOrCreateWine(matching candidate: WineCandidate, in context: ModelContext) throws -> Wine {
        let producer = candidate.producer
        let name = candidate.name
        let vintage = candidate.vintage

        var descriptor = FetchDescriptor<Wine>(
            predicate: #Predicate { $0.producer == producer && $0.name == name && $0.vintage == vintage }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let wine = Wine(
            producer: candidate.producer,
            name: candidate.name,
            vintage: candidate.vintage,
            region: candidate.region,
            varietal: candidate.varietal,
            bottleSize: candidate.bottleSize
        )
        context.insert(wine)
        return wine
    }
}
