//
//  Bottle.swift
//  Cellar — Models
//
//  SwiftData. PRD §8: an instance. THE invariant this whole architecture rests on:
//  `wine` is optional, and a Bottle is created and slotted with `wine == nil` —
//  recognition resolves it later, asynchronously, never gating creation.
//

import Foundation
import SwiftData

public enum BottleStatus: String, Codable, Sendable {
    case present
    case gone
}

@Model
public final class Bottle {
    @Attribute(.unique) public var id: UUID

    /// NIL until recognition resolves. This is the key invariant (PRD §8): a Bottle
    /// may exist with no Wine attached. Nothing in this file — or anywhere else —
    /// requires this to be set at creation time. See RecognitionQueue for the only
    /// code path that ever sets it after the fact.
    public var wine: Wine?

    // MARK: Location — illegal-state-unrepresentable, the SwiftData-compromise way
    //
    // PRD §8: a fridge Bottle has exactly one (shelf, slot); a `.boxes` Bottle has
    // both nil. The natural Swift representation is an enum with an associated
    // value (`.fridge(shelf:slot:)` / `.boxes`), but SwiftData's `@Model` macro
    // wants plain stored properties it can map to predicates and a schema, and an
    // associated-value enum doesn't participate cleanly in `#Predicate` (needed for
    // occupancy queries like "what's on shelf 2") or schema migration. So the raw
    // storage is three private(set) fields, and `location` is a computed, public
    // enum view over them — giving the same "illegal state unrepresentable" result
    // from the call site, while keeping shelfIndex/slotIndex directly queryable.
    // `private(set)` means no file outside this one can write these three fields
    // directly; `_unsafeRelocate(to:)` below is the only thing that changes them,
    // and it always sets or clears the pair together.
    //
    // That guarantees the (shelf, slot) PAIR is always coherent, but it says
    // nothing about whether two DIFFERENT bottles hold the same address — a Bottle
    // can't see its neighbours. Slot uniqueness is enforced one layer up, in
    // `CellarStore.place(_:at:layout:)`, which is the only supported way to set a
    // slot.
    public private(set) var locationKind: String
    public private(set) var shelfIndex: Int?
    public private(set) var slotIndex: Int?

    public var labelPhoto: Data?
    public var addedAt: Date
    public var status: BottleStatus

    @Relationship(deleteRule: .nullify, inverse: \DrinkEvent.bottle)
    public var drinkEvents: [DrinkEvent]? = []

    @Relationship(deleteRule: .nullify, inverse: \ReviewItem.bottle)
    public var reviewItems: [ReviewItem]? = []

    public enum Location: Equatable, Sendable {
        case fridge(shelf: Int, slot: Int)
        case boxes

        /// Bridges to the Engine's pure-Foundation `SlotAddress`, or nil for `.boxes`.
        public var address: SlotAddress? {
            if case let .fridge(shelf, slot) = self {
                return SlotAddress(shelfIndex: shelf, slot: slot)
            }
            return nil
        }
    }

    private static let fridgeKind = "fridge"
    private static let boxesKind = "boxes"

    public var location: Location {
        if locationKind == Self.fridgeKind, let shelf = shelfIndex, let slot = slotIndex {
            return .fridge(shelf: shelf, slot: slot)
        }
        return .boxes
    }

    public init(
        id: UUID = UUID(),
        wine: Wine? = nil,
        location: Location = .boxes,
        labelPhoto: Data? = nil,
        addedAt: Date = .now,
        status: BottleStatus = .present
    ) {
        self.id = id
        self.wine = wine
        self.labelPhoto = labelPhoto
        self.addedAt = addedAt
        self.status = status
        self.locationKind = Self.boxesKind
        self.shelfIndex = nil
        self.slotIndex = nil
        // Safe here despite the name: a brand-new bottle isn't in the store yet, so
        // there is no uniqueness question to answer. Callers creating a bottle AT a
        // slot must still go through CellarStore.place afterward to validate it —
        // which is why the add flow creates bottles in .boxes (the default) and
        // places them as a second step.
        self._unsafeRelocate(to: location)
    }

    /// DO NOT CALL THIS. Use `CellarStore.place(_:at:layout:)` or
    /// `CellarStore.moveToBoxes(_:)` instead.
    ///
    /// This writes the location fields with NO uniqueness check — calling it
    /// directly is how two bottles end up in slot C4. It cannot enforce that
    /// itself: uniqueness is a fact about every OTHER bottle in the store, and a
    /// `Bottle` has no way to see them. `CellarStore` owns the ModelContext, so it
    /// is the only thing that can query live occupancy and decide.
    ///
    /// It stays `public` only because `CellarStore` lives in a different directory
    /// of the same single-module app, where `internal` buys nothing. The `_unsafe`
    /// prefix is the honest enforcement available here: a bypass is visible in
    /// review rather than hidden behind an innocent-looking name.
    ///
    /// Slot positions change ONLY through the add flow, the drink log, or the audit
    /// (PRD §8) — and all three go through `CellarStore`.
    public func _unsafeRelocate(to newLocation: Location) {
        switch newLocation {
        case let .fridge(shelf, slot):
            locationKind = Self.fridgeKind
            shelfIndex = shelf
            slotIndex = slot
        case .boxes:
            locationKind = Self.boxesKind
            shelfIndex = nil
            slotIndex = nil
        }
    }
}
