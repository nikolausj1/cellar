//
//  WineResolution.swift
//  Cellar — Views/Review
//
//  Turns an accepted `WineCandidate` into a real `Wine` record — the same
//  producer/name/vintage dedupe RecognitionQueue uses internally (so two
//  bottles of the same wine, one auto-accepted and one accepted here by
//  hand, still converge on ONE Wine row), reimplemented here because that
//  logic is private to RecognitionQueue (Services, off-limits to edit) and
//  this package needs the identical behavior for tiers 2 and 3 of the
//  review queue (PRD §6.4), which resolve a bottle's wine directly rather
//  than through the queue's own auto-accept path.
//

import Foundation
import SwiftData

enum WineResolution {
    @MainActor
    static func resolve(_ candidate: WineCandidate, in context: ModelContext) throws -> Wine {
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

/// Resolves a whole ReviewItem to a chosen candidate: attaches (or creates)
/// the Wine, then removes the item from the queue. Shared by tier 1
/// (Accept) and tier 2 (pick an alternate) — both end at the same place,
/// just with a different candidate.
enum ReviewResolution {
    /// For a Pi-sourced item with no cellar bottle behind it (PRD §6.5: an
    /// unknown bottle logged as a drink), there is nothing here to attach
    /// the wine to — wiring a resolved wine back to that drink event
    /// belongs to the Pi scan station / drink log feature, not this
    /// package. The item is simply cleared from the queue in that case.
    @MainActor
    static func accept(candidate: WineCandidate, for item: ReviewItem, in context: ModelContext) {
        if let bottle = item.bottle, bottle.wine == nil {
            bottle.wine = try? WineResolution.resolve(candidate, in: context)
        }
        context.delete(item)
        try? context.save()
    }
}
