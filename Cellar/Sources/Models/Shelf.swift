//
//  Shelf.swift
//  Cellar — Models
//
//  SwiftData. PRD §8 / §6.12: configurable fridge geometry, editable in a setup
//  screen, seeded with nothing until the real fridge geometry is known (§12 open
//  question 1).
//
//  NOTE: the pure layout math (validation, occupancy, next-free-slot, capacity)
//  lives in Sources/Engine/FridgeLayout.swift as `ShelfLayout` / `FridgeLayout`,
//  which cannot depend on SwiftData. This `Shelf` is the persisted counterpart;
//  `layout` bridges one to the other.
//

import Foundation
import SwiftData

@Model
public final class Shelf {
    @Attribute(.unique) public var index: Int
    public var slotCount: Int
    public var style: ShelfStyle

    public init(index: Int, slotCount: Int, style: ShelfStyle) {
        self.index = index
        self.slotCount = slotCount
        self.style = style
    }

    /// The pure-Foundation Engine value for this shelf, for feeding FridgeLayout
    /// math (validation, occupancy, next-free-slot).
    public var layout: ShelfLayout {
        ShelfLayout(index: index, slotCount: slotCount, style: style)
    }
}
