//
//  DemoSeed.swift
//  Cellar — Views/Map
//
//  Launch-arg-gated demo data so the POPULATED map can be screenshotted with
//  `simctl`, which cannot tap through the real add flow (Build Guide: "give
//  each screen a launch-arg autostart hook"). Launch with `-demoLayout`.
//
//  This seeds an entirely separate, in-memory-only ModelContainer — it is
//  structurally impossible for this to touch Justin's real on-disk cellar.
//  CellarApp only ever reaches for this when the launch arg is present.
//

import Foundation
import SwiftData

enum DemoSeed {
    static let launchArgument = "-demoLayout"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// A fresh, in-memory-only container, pre-populated with a representative
    /// fridge: several shelves, mixed shelf styles, occupied and open slots,
    /// every readiness state, a couple of unresolved (wine == nil) bottles —
    /// the normal, calm, load-day-in-progress look — plus a few bottles in
    /// Boxes, a couple of review items, and one drink event still missing its
    /// memory, so the map's cards have something to show.
    @MainActor
    static func makeContainer() -> ModelContainer {
        let schema = Schema([Wine.self, Bottle.self, Shelf.self, DrinkEvent.self, Memory.self, ReviewItem.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seed(into: container.mainContext)
        return container
    }

    @MainActor
    private static func seed(into context: ModelContext) {
        // MARK: Shelves — top to bottom, mixed styles, matching the _inbox photos:
        // a couple of storage shelves up top, a pair of display shelves in the
        // middle, storage shelves filling out the bottom (where the bulk lives).
        let shelves = [
            Shelf(index: 0, slotCount: 5, style: .storage),
            Shelf(index: 1, slotCount: 3, style: .display),
            Shelf(index: 2, slotCount: 3, style: .display),
            Shelf(index: 3, slotCount: 6, style: .storage),
            Shelf(index: 4, slotCount: 6, style: .storage),
            Shelf(index: 5, slotCount: 6, style: .storage),
        ]
        shelves.forEach { context.insert($0) }

        let currentYear = Calendar.current.component(.year, from: .now)

        func wine(_ producer: String, _ name: String, _ vintage: Int, start: Int?, end: Int?, region: String? = nil) -> Wine {
            let wine = Wine(producer: producer, name: name, vintage: vintage, region: region, varietal: nil, bottleSize: "750ml")
            if start != nil || end != nil {
                wine.applyEnrichment(
                    drinkWindowStart: start,
                    drinkWindowEnd: end,
                    tastingNotes: "Dark fruit, cedar, a long finish.",
                    pairings: "Braised short rib, aged cheddar.",
                    estimatedValue: Double.random(in: 45...420)
                )
            }
            return wine
        }

        // One of each readiness state, plus a couple left unenriched (unknown).
        let wines: [Wine] = [
            wine("Ornellaia", "Bolgheri Superiore", 2015, start: currentYear - 4, end: currentYear + 6, region: "Tuscany"),
            wine("Duckhorn", "Napa Valley Cabernet", 2018, start: currentYear - 2, end: currentYear + 3, region: "Napa Valley"),
            wine("Caymus", "Special Selection", 2019, start: currentYear - 3, end: currentYear + 4, region: "Napa Valley"),
            wine("Georges de Latour", "BV Private Reserve", 2016, start: currentYear + 2, end: currentYear + 9, region: "Napa Valley"),
            wine("Ringer", "Vate Reserve Cabernet Sauvignon", 2015, start: currentYear + 1, end: currentYear + 6, region: "Napa Valley"),
            wine("CastelGiocondo", "Brunello di Montalcino", 2017, start: currentYear - 6, end: currentYear - 1, region: "Montalcino"),
            wine("Frescobaldi", "Nipozzano Riserva", 2014, start: currentYear - 8, end: currentYear, region: "Chianti Rùfina"),
            wine("Marcassin", "Vin de Lanville Réserve", 2010, start: nil, end: nil),
            wine("Michel & Nickel", "Cabernet Sauvignon", 2016, start: nil, end: nil),
        ]
        wines.forEach { context.insert($0) }

        // MARK: Bottles — a representative slice of a 120-bottle collection.
        var bottles: [Bottle] = []

        func place(_ wine: Wine?, shelf: Int, slot: Int) -> Bottle {
            let bottle = Bottle(wine: wine, location: .fridge(shelf: shelf, slot: slot), addedAt: .now, status: .present)
            context.insert(bottle)
            bottles.append(bottle)
            return bottle
        }

        // Shelf 0 (storage, 5 slots) — 4 occupied, 1 open.
        _ = place(wines[0], shelf: 0, slot: 0)
        _ = place(wines[1], shelf: 0, slot: 1)
        _ = place(wines[2], shelf: 0, slot: 2)
        _ = place(nil, shelf: 0, slot: 3) // unresolved — recognition still pending, the normal load-day look
        // slot 4 left open

        // Shelf 1 (display, 3 slots) — full.
        _ = place(wines[3], shelf: 1, slot: 0)
        _ = place(wines[4], shelf: 1, slot: 1)
        _ = place(wines[5], shelf: 1, slot: 2)

        // Shelf 2 (display, 3 slots) — 2 occupied, 1 open.
        _ = place(wines[6], shelf: 2, slot: 0)
        _ = place(nil, shelf: 2, slot: 1) // unresolved
        // slot 2 left open

        // Shelf 3 (storage, 6 slots) — 4 occupied.
        _ = place(wines[7], shelf: 3, slot: 0)
        _ = place(wines[8], shelf: 3, slot: 1)
        _ = place(wines[0], shelf: 3, slot: 2)
        _ = place(wines[1], shelf: 3, slot: 3)
        // slots 4-5 left open

        // Shelf 4 (storage, 6 slots) — full, mostly unresolved (fresh load-day batch).
        for slot in 0..<6 {
            _ = place(slot % 2 == 0 ? nil : wines[slot % wines.count], shelf: 4, slot: slot)
        }

        // Shelf 5 (storage, 6 slots) — 3 occupied.
        _ = place(wines[2], shelf: 5, slot: 0)
        _ = place(wines[4], shelf: 5, slot: 1)
        _ = place(wines[6], shelf: 5, slot: 2)

        // A few in Boxes — no slots, just a pile.
        _ = Bottle(wine: wines[5], location: .boxes, status: .present).also { context.insert($0); bottles.append($0) }
        _ = Bottle(wine: nil, location: .boxes, status: .present).also { context.insert($0); bottles.append($0) }
        _ = Bottle(wine: wines[7], location: .boxes, status: .present).also { context.insert($0); bottles.append($0) }

        // MARK: Review items — a couple pending, driving the "N bottles need review" card.
        let reviewBottle = bottles.first { $0.wine == nil }
        let review1 = ReviewItem(
            photo: Data(),
            candidates: [
                WineCandidate(producer: "Silver Oak", name: "Alexander Valley Cabernet", vintage: 2018),
                WineCandidate(producer: "Silver Oak", name: "Napa Valley Cabernet", vintage: 2018),
            ],
            confidence: 0.62,
            source: .phone,
            bottle: reviewBottle
        )
        context.insert(review1)

        let review2 = ReviewItem(
            photo: Data(),
            candidates: [WineCandidate(producer: "Unknown", name: "Handwritten label")],
            confidence: 0.31,
            source: .pi,
            bottle: nil
        )
        context.insert(review2)

        // MARK: A drink event still missing its memory — drives the app-open card
        // (PRD §6.6 rung 2).
        let lastNight = Calendar.current.date(byAdding: .hour, value: -14, to: .now) ?? .now
        let drinkEvent = DrinkEvent(wine: wines[0], bottle: nil, drankAt: lastNight, outcome: .drank)
        context.insert(drinkEvent)

        try? context.save()
    }
}

private extension Bottle {
    /// Small local convenience so the seeding block above reads top-to-bottom
    /// without an intermediate `let` for every Boxes bottle.
    func also(_ body: (Bottle) -> Void) -> Bottle {
        body(self)
        return self
    }
}
