//
//  Readiness.swift
//  Cellar — Engine
//
//  Pure Foundation. Drives the fridge map's capsule ring color (PRD §6.1, §7).
//  Given a drink window (either bound may be nil) and "now" (as a year, so the
//  caller controls the clock — no `Date()` calls buried in here), decide whether
//  the wine is being held, ready, at/past the end of its window, or unknown.
//

import Foundation

public enum Readiness: String, Equatable, Sendable {
    /// Too young — before the window's start year.
    case hold
    /// Inside the window.
    case ready
    /// At or past the window's end year — PRD: "amber hold, red drink soon" maps
    /// this case to the red ring.
    case drinkSoon
    /// No drink window data at all (never enriched, or enrichment returned nothing).
    case unknown
}

public struct DrinkWindow: Codable, Equatable, Sendable {
    public let startYear: Int?
    public let endYear: Int?

    public init(startYear: Int?, endYear: Int?) {
        self.startYear = startYear
        self.endYear = endYear
    }

    var isEmpty: Bool { startYear == nil && endYear == nil }
}

public enum ReadinessCalculator {
    /// - Parameters:
    ///   - window: nil, or a window with both bounds nil, both mean "no data yet".
    ///   - currentYear: the caller's "now", as a year — keeps this function pure
    ///     and trivially testable across boundary years.
    public static func readiness(for window: DrinkWindow?, currentYear: Int) -> Readiness {
        guard let window, !window.isEmpty else {
            return .unknown
        }

        // "At or past the end" wins even if the same year is also >= start
        // (a single-year window, start == end, reads as drinkSoon, not ready).
        if let end = window.endYear, currentYear >= end {
            return .drinkSoon
        }

        if let start = window.startYear, currentYear < start {
            return .hold
        }

        // Either inside [start, end), or open-ended on one side with the other
        // bound satisfied.
        return .ready
    }
}
