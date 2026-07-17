//
//  CellarStore.swift
//  Cellar — Services
//
//  The choke point for slot occupancy. PRD §8: "a slot holds at most one Bottle."
//
//  That invariant cannot live on `Bottle`, because it is a fact about every OTHER
//  bottle in the store — a single `Bottle` has no way to see its neighbours. So it
//  lives here, in the one type that owns a ModelContext and can therefore ask.
//  `Bottle._unsafeRelocate(to:)` is named to make bypassing this visible in review.
//
//  Every slot write in the app — add flow, drink log, audit (PRD §8: "nothing else
//  writes them") — goes through `place` or `moveToBoxes`.
//
//  @MainActor because ModelContext is not Sendable and the callers are views.
//

import Foundation
import SwiftData

@MainActor
public final class CellarStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public enum PlacementError: Error, Equatable {
        /// Another PRESENT bottle already holds this address.
        case slotOccupied(SlotAddress)
        /// Not a real address in the configured layout.
        case invalidSlot(SlotAddress)
    }

    /// The ONLY supported way a bottle acquires or changes a fridge slot.
    ///
    /// Validates against LIVE data — it queries present bottles itself rather than
    /// trusting a caller-supplied occupancy set, because a caller-supplied set is
    /// the same delegation problem one layer up: the slot picker would be the thing
    /// deciding what's occupied, which is exactly the bug this method exists to
    /// prevent.
    ///
    /// Placing a bottle at the address it already holds is a no-op success —
    /// re-tapping the same slot must not error.
    ///
    /// - Throws: `.slotOccupied` if another present bottle holds that address,
    ///           `.invalidSlot` if the address isn't in the configured layout.
    public func place(_ bottle: Bottle, at address: SlotAddress, layout: FridgeLayout) throws {
        let decision = layout.placementDecision(
            for: address,
            occupied: occupiedSlots(),
            currentAddress: bottle.location.address
        )

        switch decision {
        case .invalid:
            throw PlacementError.invalidSlot(address)
        case .occupied:
            throw PlacementError.slotOccupied(address)
        case .noOp:
            return
        case .allowed:
            bottle._unsafeRelocate(to: .fridge(shelf: address.shelfIndex, slot: address.slot))
            try? context.save()
        }
    }

    /// Moves a bottle out of the fridge and into boxes, freeing its slot. Always
    /// legal — boxes is a pile with no slots (PRD §4), so there is nothing to
    /// collide with and nothing to validate.
    public func moveToBoxes(_ bottle: Bottle) {
        bottle._unsafeRelocate(to: .boxes)
        try? context.save()
    }

    /// Live occupancy from present bottles. Excludes `.gone` bottles — a bottle
    /// that's been drunk doesn't hold its old slot hostage.
    ///
    /// Fetches all bottles and filters in memory rather than using a `#Predicate`
    /// on `status` / `locationKind`. Deliberate: this is a ~120-bottle personal app
    /// (PRD §2), the cost is nil, and it keeps occupancy reading off SwiftData
    /// predicate support for a custom enum and the private-set location fields.
    public func occupiedSlots() -> Set<SlotAddress> {
        let bottles = (try? context.fetch(FetchDescriptor<Bottle>())) ?? []
        return Set(
            bottles
                .filter { $0.status == .present }
                .compactMap { $0.location.address }
        )
    }

    /// Free, valid addresses in layout order — what the slot picker renders.
    /// Ordering is shelf index, then slot index, matching `FridgeLayout` so the
    /// picker and `nextFreeAddress` never disagree.
    public func freeSlots(in layout: FridgeLayout) -> [SlotAddress] {
        layout.freeAddresses(occupied: occupiedSlots())
    }
}
