//
//  CellarValue.swift
//  Cellar — Engine
//
//  Pure Foundation. Aggregates estimated cellar value (PRD §6.9). The `isEstimate`
//  flag is carried all the way through the aggregate so the UI has no way to render
//  a bare, authoritative-looking number — every value in this system originates
//  from a single cached LLM guess per wine, never a receipt, never verified.
//

import Foundation

/// One bottle's contribution to the aggregate. `isEstimate` defaults to true because,
/// per the architecture (PRD §6.9), every value that exists at all came from one
/// cached `/enrich` call — there is no other source of bottle value in this app.
/// The parameter still exists (rather than hardcoding true) so this stays honest if
/// a future source of ground truth is ever added.
public struct ValuedBottle: Sendable {
    public let value: Double?
    public let isEstimate: Bool

    public init(value: Double?, isEstimate: Bool = true) {
        self.value = value
        self.isEstimate = isEstimate
    }
}

public struct CellarValueSummary: Equatable, Sendable {
    public let total: Double
    /// True iff at least one bottle contributing to `total` is an estimate. Any
    /// screen displaying `total` MUST also display this flag (e.g. an "estimated"
    /// tag) — PRD §6.9: never let this render as authoritative.
    public let isEstimate: Bool
    public let valuedBottleCount: Int
    public let unvaluedBottleCount: Int
}

public enum CellarValueCalculator {
    public static func aggregate(_ bottles: [ValuedBottle]) -> CellarValueSummary {
        var total = 0.0
        var anyEstimate = false
        var valuedCount = 0
        var unvaluedCount = 0

        for bottle in bottles {
            if let value = bottle.value {
                total += value
                valuedCount += 1
                if bottle.isEstimate { anyEstimate = true }
            } else {
                unvaluedCount += 1
            }
        }

        return CellarValueSummary(
            total: total,
            isEstimate: valuedCount > 0 && anyEstimate,
            valuedBottleCount: valuedCount,
            unvaluedBottleCount: unvaluedCount
        )
    }
}
