//
//  FridgeLayout.swift
//  Cellar — Engine
//
//  Pure Foundation. NO SwiftData, NO SwiftUI, NO UIKit. Must compile standalone
//  with `swiftc` (see Project Build Guide "engine-test recipe").
//
//  Fridge geometry is a runtime configuration, not a hardcoded constant — the real
//  fridge model is still unknown (PRD §12 open question 1) and a second fridge is a
//  planned v2 scenario (PRD §4 deferred). Nothing in this file assumes a slot count,
//  a shelf count, or a specific shelf style.
//
//  NOTE ON NAMING: PRD §8 names the persisted shelf model "Shelf". This file's shelf
//  value type is deliberately named `ShelfLayout` instead, because the SwiftData
//  `Shelf` model (Sources/Models/Shelf.swift) lives in the same compiled Xcode module
//  as this file, and two public top-level types both named `Shelf` would collide.
//  `ShelfLayout` is the pure-Foundation twin that `Shelf` bridges to via a computed
//  `layout` property, keeping SwiftData entirely out of Sources/Engine.
//

import Foundation

// MARK: - Shelf style

public enum ShelfStyle: String, Codable, CaseIterable, Sendable {
    /// Bottles stood upright, label visible — a showcase shelf.
    case display
    /// Bottles stored neck-out — the label is never visible without pulling the bottle.
    case storage
}

// MARK: - Shelf layout (one shelf's geometry)

public struct ShelfLayout: Codable, Hashable, Sendable {
    public let index: Int
    public let slotCount: Int
    public let style: ShelfStyle

    public init(index: Int, slotCount: Int, style: ShelfStyle) {
        self.index = index
        self.slotCount = max(0, slotCount)
        self.style = style
    }
}

// MARK: - A single (shelf, slot) address

public struct SlotAddress: Hashable, Codable, Sendable {
    public let shelfIndex: Int
    public let slot: Int

    public init(shelfIndex: Int, slot: Int) {
        self.shelfIndex = shelfIndex
        self.slot = slot
    }
}

// MARK: - Validation errors

public enum FridgeLayoutError: Error, Equatable, Sendable {
    case shelfNotFound(Int)
    case slotOutOfRange(shelf: Int, slot: Int, slotCount: Int)
}

// MARK: - Placement decision

/// The outcome of asking "may this bottle go in this slot?" — see
/// `FridgeLayout.placementDecision(for:occupied:currentAddress:)`.
/// `CellarStore.place` maps these onto its `PlacementError` / success contract.
public enum SlotPlacement: Equatable, Sendable {
    /// Free, valid, and not the bottle's current address — place it.
    case allowed
    /// The bottle already holds this exact address. Success, but nothing to write.
    case noOp
    /// A different present bottle holds this address.
    case occupied
    /// Not a real address in the configured layout.
    case invalid
}

// MARK: - FridgeLayout

/// A complete, runtime-configurable fridge geometry: an ordered list of shelves.
/// Owns address validation, occupancy math, next-free-slot lookup, and capacity —
/// nothing else. Whether a slot is actually occupied is a fact that lives in
/// SwiftData (Bottle.location); this type only does the arithmetic.
public struct FridgeLayout: Codable, Sendable {
    public let shelves: [ShelfLayout]

    public init(shelves: [ShelfLayout]) {
        self.shelves = shelves.sorted { $0.index < $1.index }
    }

    /// Total slots across every shelf.
    public var capacity: Int {
        shelves.reduce(0) { $0 + $1.slotCount }
    }

    /// True iff every shelf index is unique and no shelf has a negative slot count.
    /// A setup screen (owned elsewhere) should check this before saving a layout.
    public var isConfigurationValid: Bool {
        let indices = shelves.map(\.index)
        return Set(indices).count == indices.count && shelves.allSatisfy { $0.slotCount >= 0 }
    }

    public func shelf(at index: Int) -> ShelfLayout? {
        shelves.first { $0.index == index }
    }

    /// Throws a specific `FridgeLayoutError` describing why the address is invalid,
    /// or returns normally if it is valid.
    public func validate(_ address: SlotAddress) throws {
        guard let shelf = shelf(at: address.shelfIndex) else {
            throw FridgeLayoutError.shelfNotFound(address.shelfIndex)
        }
        guard address.slot >= 0 && address.slot < shelf.slotCount else {
            throw FridgeLayoutError.slotOutOfRange(shelf: address.shelfIndex, slot: address.slot, slotCount: shelf.slotCount)
        }
    }

    public func isValid(_ address: SlotAddress) -> Bool {
        (try? validate(address)) != nil
    }

    /// Every valid address in the fridge, shelf order then slot order.
    public func allAddresses() -> [SlotAddress] {
        shelves.flatMap { shelf in
            (0..<shelf.slotCount).map { SlotAddress(shelfIndex: shelf.index, slot: $0) }
        }
    }

    /// Count of `occupied` addresses that are actually valid positions in this layout.
    /// (Addresses referring to a shelf that no longer exists, e.g. after a layout edit,
    /// are not counted — they don't occupy anything in the current geometry.)
    public func occupiedCount(occupied: Set<SlotAddress>) -> Int {
        occupied.filter(isValid).count
    }

    public func freeCount(occupied: Set<SlotAddress>) -> Int {
        capacity - occupiedCount(occupied: occupied)
    }

    public func isFull(occupied: Set<SlotAddress>) -> Bool {
        freeCount(occupied: occupied) <= 0
    }

    public func freeAddresses(occupied: Set<SlotAddress>) -> [SlotAddress] {
        allAddresses().filter { !occupied.contains($0) }
    }

    /// The first free slot in shelf order, then slot order — deterministic so the
    /// slot picker and bulk-add batch screen always agree on "next" without a race.
    public func nextFreeAddress(occupied: Set<SlotAddress>) -> SlotAddress? {
        for shelf in shelves {
            for slot in 0..<shelf.slotCount {
                let address = SlotAddress(shelfIndex: shelf.index, slot: slot)
                if !occupied.contains(address) {
                    return address
                }
            }
        }
        return nil
    }

    // MARK: - Placement decision

    /// The pure decision behind `CellarStore.place(_:at:layout:)`. Extracted here,
    /// with no SwiftData in sight, so the branching (invalid vs. no-op vs. occupied
    /// vs. allowed) is covered by the swiftc smoke test rather than being locked
    /// behind a ModelContext that the Build Guide's engine-test recipe can't reach.
    ///
    /// This takes `occupied` as a parameter, which looks like the delegation problem
    /// CellarStore exists to eliminate — it isn't. `CellarStore.place` is the only
    /// caller, and it builds that set itself from live `Bottle` data. Views must go
    /// through `CellarStore.place`, never here.
    ///
    /// - Parameters:
    ///   - occupied: every address held by a present bottle, INCLUDING the bottle
    ///     being placed (if it currently holds one). `currentAddress` disambiguates.
    ///   - currentAddress: the address the bottle being placed holds right now, or
    ///     nil if it's in boxes / brand new.
    public func placementDecision(
        for address: SlotAddress,
        occupied: Set<SlotAddress>,
        currentAddress: SlotAddress?
    ) -> SlotPlacement {
        // Invalid wins over everything: if the layout shrank out from under a
        // bottle, re-placing it at its own now-nonexistent address is still invalid.
        guard isValid(address) else { return .invalid }

        // Re-tapping the slot a bottle already holds is a no-op success, not a
        // collision with itself.
        if let currentAddress, currentAddress == address { return .noOp }

        if occupied.contains(address) { return .occupied }

        return .allowed
    }

    /// Per-shelf (occupied, capacity) pairs, keyed by shelf index.
    public func shelfOccupancy(occupied: Set<SlotAddress>) -> [Int: (occupied: Int, capacity: Int)] {
        var result: [Int: (occupied: Int, capacity: Int)] = [:]
        for shelf in shelves {
            let occupiedOnShelf = occupied.filter {
                $0.shelfIndex == shelf.index && $0.slot >= 0 && $0.slot < shelf.slotCount
            }.count
            result[shelf.index] = (occupiedOnShelf, shelf.slotCount)
        }
        return result
    }
}
