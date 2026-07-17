//
//  EnrichmentService.swift
//  Cellar — Services
//
//  PRD §6.9: ONE `/enrich` call per unique Wine, EVER, cached forever on the wine
//  record, never called again. Two bottles of the same wine added back to back
//  must not fire two calls — this file is the race guard.
//

import Foundation
import SwiftData

public actor EnrichmentService {
    private let container: ModelContainer
    private let client: PiClientProtocol

    /// In-memory guard against a race within a single app run: two calls to
    /// `requestEnrichment` for the same wine before the first one returns. Actor
    /// isolation makes the check-then-insert on this set atomic — there is no
    /// `await` between checking membership and inserting, so two concurrent calls
    /// can never both pass the guard.
    private var inFlight: Set<PersistentIdentifier> = []

    public init(container: ModelContainer, client: PiClientProtocol) {
        self.container = container
        self.client = client
    }

    /// Fire-and-forget, same contract as RecognitionQueue.submit: not `async`, so a
    /// caller adding a bottle can never block on this. Internally spawns a Task
    /// that does the real (network-bound) work.
    nonisolated public func requestEnrichment(for wineID: PersistentIdentifier) {
        Task { await self.run(wineID) }
    }

    private func run(_ wineID: PersistentIdentifier) async {
        guard !inFlight.contains(wineID) else { return }
        inFlight.insert(wineID)
        defer { inFlight.remove(wineID) }

        // Second guard, durable across app relaunches (the in-flight set above only
        // protects a single process's lifetime): re-check the persisted
        // `valueEstimatedAt` right before calling out. If some earlier run already
        // completed and saved, this is a no-op.
        guard let request = await buildRequestIfUnenriched(wineID) else { return }

        do {
            let result = try await client.enrich(request)
            await apply(result, to: wineID)
        } catch {
            // Drop silently. Nothing was marked enriched, so no state was lost —
            // the next bottle of this wine (or a manual retry) will ask again.
        }
    }

    @MainActor
    private func buildRequestIfUnenriched(_ wineID: PersistentIdentifier) -> EnrichRequest? {
        let context = ModelContext(container)
        guard let wine = context.model(for: wineID) as? Wine, wine.valueEstimatedAt == nil else {
            return nil
        }
        return EnrichRequest(
            producer: wine.producer,
            name: wine.name,
            vintage: wine.vintage,
            region: wine.region,
            varietal: wine.varietal
        )
    }

    /// Applies the result through `Wine.applyEnrichment(...)`, the model-layer
    /// choke point that itself re-checks `valueEstimatedAt == nil` and no-ops if
    /// it's already set. Belt and suspenders: even if two EnrichmentService
    /// instances somehow existed (they shouldn't — inject one per app), the model
    /// method is the final backstop against overwriting cached figures.
    @MainActor
    private func apply(_ result: EnrichResult, to wineID: PersistentIdentifier) {
        let context = ModelContext(container)
        guard let wine = context.model(for: wineID) as? Wine else { return }
        wine.applyEnrichment(
            drinkWindowStart: result.drinkWindowStart,
            drinkWindowEnd: result.drinkWindowEnd,
            tastingNotes: result.tastingNotes,
            pairings: result.pairings,
            estimatedValue: result.estimatedValue
        )
        try? context.save()
    }
}
