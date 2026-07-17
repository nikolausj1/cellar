//
//  Wine.swift
//  Cellar — Models
//
//  SwiftData. PRD §8: the reference — one per unique wine. Populated by exactly ONE
//  cached `/enrich` call, ever (§6.9); see `applyEnrichment(...)` below for the
//  choke point that enforces that.
//

import Foundation
import SwiftData

@Model
public final class Wine {
    @Attribute(.unique) public var id: UUID

    public var producer: String
    public var name: String
    public var vintage: Int?
    public var region: String?
    public var varietal: String?
    public var bottleSize: String?

    public var drinkWindowStart: Int?
    public var drinkWindowEnd: Int?

    public var tastingNotes: String?
    public var pairings: String?
    public var estimatedValue: Double?
    /// Non-nil iff `/enrich` has ever returned for this wine. This is the durable
    /// (survives relaunch) half of the "one call ever" guarantee — see
    /// EnrichmentService, which also guards the in-flight race in memory.
    public var valueEstimatedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \Bottle.wine)
    public var bottles: [Bottle]? = []

    @Relationship(deleteRule: .nullify, inverse: \DrinkEvent.wine)
    public var drinkEvents: [DrinkEvent]? = []

    public init(
        id: UUID = UUID(),
        producer: String,
        name: String,
        vintage: Int? = nil,
        region: String? = nil,
        varietal: String? = nil,
        bottleSize: String? = nil
    ) {
        self.id = id
        self.producer = producer
        self.name = name
        self.vintage = vintage
        self.region = region
        self.varietal = varietal
        self.bottleSize = bottleSize
    }

    /// The drink window as a plain Engine value, ready for `ReadinessCalculator`.
    /// (`DrinkWindow` is defined in Sources/Engine/Readiness.swift; both files live
    /// in the same compiled module, so no import is needed — this is the one place
    /// SwiftData data crosses into Engine math, and it crosses as a plain struct,
    /// never a SwiftData type.)
    public var drinkWindow: DrinkWindow {
        DrinkWindow(startYear: drinkWindowStart, endYear: drinkWindowEnd)
    }

    public var isEnriched: Bool { valueEstimatedAt != nil }

    /// The single choke point for applying a `/enrich` result. PRD §6.9: one Gemini
    /// call per unique wine, EVER, cached forever on the wine record, never called
    /// again. This method silently no-ops (returns false) if `valueEstimatedAt` is
    /// already set, so a stray duplicate call — e.g. two bottles of the same wine
    /// added back to back losing a race in EnrichmentService — can never overwrite
    /// the cached figures.
    @discardableResult
    public func applyEnrichment(
        drinkWindowStart: Int?,
        drinkWindowEnd: Int?,
        tastingNotes: String?,
        pairings: String?,
        estimatedValue: Double?,
        at date: Date = .now
    ) -> Bool {
        guard valueEstimatedAt == nil else { return false }
        self.drinkWindowStart = drinkWindowStart
        self.drinkWindowEnd = drinkWindowEnd
        self.tastingNotes = tastingNotes
        self.pairings = pairings
        self.estimatedValue = estimatedValue
        self.valueEstimatedAt = date
        return true
    }
}
