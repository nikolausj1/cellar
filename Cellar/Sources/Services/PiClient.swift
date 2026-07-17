//
//  PiClient.swift
//  Cellar — Services
//
//  Talks to the Pi scan station (PRD §9). The base URL is configurable at RUNTIME
//  (persisted via UserDefaults, never compiled in) — the Pi doesn't exist yet, and
//  Tailscale addresses / hostnames can change. This file matches the server
//  contract another worker is implementing in parallel, endpoint for endpoint.
//
//  IMPORTANT: nothing in this file is fire-and-forget. Every method here is a
//  normal `async throws` network call — the whole point of RecognitionQueue and
//  EnrichmentService existing as separate types is to be the layer that NEVER lets
//  the add flow await one of these calls directly.
//

import Foundation

// MARK: - Wire types

public struct PiHealth: Codable, Sendable, Equatable {
    public let ok: Bool
    public let hardware: String
    public let recognizer: String
    public let queued: Int
}

public struct RecognizeResult: Codable, Sendable, Equatable {
    public let candidates: [WineCandidate]
    public let confidence: Double
}

public struct EnrichRequest: Codable, Sendable, Equatable {
    public let producer: String
    public let name: String
    public let vintage: Int?
    public let region: String?
    public let varietal: String?

    public init(producer: String, name: String, vintage: Int?, region: String?, varietal: String?) {
        self.producer = producer
        self.name = name
        self.vintage = vintage
        self.region = region
        self.varietal = varietal
    }
}

public struct EnrichResult: Codable, Sendable, Equatable {
    public let drinkWindowStart: Int?
    public let drinkWindowEnd: Int?
    public let tastingNotes: String?
    public let pairings: String?
    public let estimatedValue: Double?
}

public struct PiQueueEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let photoBase64: String
    public let candidates: [WineCandidate]
    public let confidence: Double
    public let capturedAt: Date
    public let voiceNote: String?
}

public struct PiQueueResponse: Codable, Sendable {
    public let entries: [PiQueueEntry]
}

// MARK: - Errors

public enum PiClientError: Error, Sendable, Equatable {
    /// No base URL has been configured yet in settings.
    case notConfigured
    case invalidResponse
    case http(status: Int)
    case encoding
    case decoding
}

// MARK: - Runtime-configurable settings

/// Base URL for the Pi, stored in app settings (UserDefaults), NOT compiled in.
/// The Pi doesn't exist yet as this is written, and it will move (new hardware,
/// new Tailscale hostname). Nothing in this app should ever hardcode a URL to it.
public final class PiClientSettings: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let baseURLKey = "PiClient.baseURL"
    private static let confidenceThresholdKey = "PiClient.confidenceThreshold"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var baseURL: URL? {
        get { defaults.string(forKey: Self.baseURLKey).flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: Self.baseURLKey) }
    }

    /// Recognition confidence threshold for auto-accepting a candidate vs. routing
    /// to the review queue. PRD §12 open question 5: "start at 85%, tune against
    /// the first 100 real bottles" — so this is a setting, not a constant.
    public var confidenceThreshold: Double {
        get {
            let stored = defaults.double(forKey: Self.confidenceThresholdKey)
            return stored == 0 ? 0.85 : stored
        }
        set { defaults.set(newValue, forKey: Self.confidenceThresholdKey) }
    }
}

// MARK: - Protocol (for a mock proxy per PRD §10 Phase 1a, and for testing)

public protocol PiClientProtocol: Sendable {
    func health() async throws -> PiHealth
    func recognize(image: Data, hint: String?) async throws -> RecognizeResult
    func enrich(_ request: EnrichRequest) async throws -> EnrichResult
    func fetchQueue() async throws -> [PiQueueEntry]
    func deleteQueueEntry(id: String) async throws
    func pushCandidates(_ wines: [String]) async throws
}

// MARK: - Live implementation

public final class PiClient: PiClientProtocol, @unchecked Sendable {
    private let settings: PiClientSettings
    private let session: URLSession

    public init(settings: PiClientSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    private func makeURL(_ path: String) throws -> URL {
        guard let base = settings.baseURL else { throw PiClientError.notConfigured }
        return base.appendingPathComponent(path)
    }

    private static func checkOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw PiClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw PiClientError.http(status: http.statusCode) }
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // GET /health -> {ok, hardware, recognizer, queued}
    public func health() async throws -> PiHealth {
        var request = URLRequest(url: try makeURL("health"))
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try Self.checkOK(response)
        guard let decoded = try? Self.decoder().decode(PiHealth.self, from: data) else {
            throw PiClientError.decoding
        }
        return decoded
    }

    // POST /recognize multipart field "image", optional form field "hint"
    // -> {candidates: [...], confidence}
    public func recognize(image: Data, hint: String?) async throws -> RecognizeResult {
        var request = URLRequest(url: try makeURL("recognize"))
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(boundary: boundary, imageData: image, hint: hint)

        let (data, response) = try await session.data(for: request)
        try Self.checkOK(response)
        guard let decoded = try? Self.decoder().decode(RecognizeResult.self, from: data) else {
            throw PiClientError.decoding
        }
        return decoded
    }

    // POST /enrich JSON {producer, name, vintage, region, varietal}
    // -> {drinkWindowStart, drinkWindowEnd, tastingNotes, pairings, estimatedValue}
    public func enrich(_ enrichRequest: EnrichRequest) async throws -> EnrichResult {
        var request = URLRequest(url: try makeURL("enrich"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? Self.encoder().encode(enrichRequest) else { throw PiClientError.encoding }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try Self.checkOK(response)
        guard let decoded = try? Self.decoder().decode(EnrichResult.self, from: data) else {
            throw PiClientError.decoding
        }
        return decoded
    }

    // GET /queue -> {entries: [...]}
    public func fetchQueue() async throws -> [PiQueueEntry] {
        var request = URLRequest(url: try makeURL("queue"))
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try Self.checkOK(response)
        guard let decoded = try? Self.decoder().decode(PiQueueResponse.self, from: data) else {
            throw PiClientError.decoding
        }
        return decoded.entries
    }

    // DELETE /queue/{id}
    public func deleteQueueEntry(id: String) async throws {
        var request = URLRequest(url: try makeURL("queue/\(id)"))
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        try Self.checkOK(response)
    }

    // PUT /candidates JSON {wines: [String]}
    public func pushCandidates(_ wines: [String]) async throws {
        var request = URLRequest(url: try makeURL("candidates"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? Self.encoder().encode(["wines": wines]) else { throw PiClientError.encoding }
        request.httpBody = body

        let (_, response) = try await session.data(for: request)
        try Self.checkOK(response)
    }

    // MARK: Multipart body builder

    private static func multipartBody(boundary: String, imageData: Data, hint: String?) -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        func append(_ string: String) {
            if let data = string.data(using: .utf8) { body.append(data) }
        }

        append("--\(boundary)\(lineBreak)")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"bottle.jpg\"\(lineBreak)")
        append("Content-Type: image/jpeg\(lineBreak)\(lineBreak)")
        body.append(imageData)
        append(lineBreak)

        if let hint, !hint.isEmpty {
            append("--\(boundary)\(lineBreak)")
            append("Content-Disposition: form-data; name=\"hint\"\(lineBreak)\(lineBreak)")
            append("\(hint)\(lineBreak)")
        }

        append("--\(boundary)--\(lineBreak)")
        return body
    }
}
