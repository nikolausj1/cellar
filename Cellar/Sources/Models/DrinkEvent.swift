//
//  DrinkEvent.swift
//  Cellar — Models
//
//  SwiftData. PRD §8 / §6.5: a DrinkEvent may reference a Wine with NO Bottle — he
//  drank a bottle he never catalogued (bought Tuesday, drunk Tuesday at the Pi).
//  That is a supported flow, not an error, so `bottle` is optional with no
//  compensating requirement elsewhere.
//

import Foundation
import SwiftData

public enum DrinkOutcome: String, Codable, CaseIterable, Sendable {
    case drank
    case gifted
    case broken
    case moved
}

@Model
public final class DrinkEvent {
    @Attribute(.unique) public var id: UUID

    /// Nil only until recognition resolves (mirrors Bottle.wine) — every drink
    /// event should eventually have a wine, but nothing here blocks on that.
    public var wine: Wine?

    /// Nil for a never-owned bottle (PRD §6.5) — the Pi is a drink logger for all
    /// wine, not just fridge wine. This is a normal, supported state, not a
    /// placeholder for data that's "supposed" to arrive later.
    public var bottle: Bottle?

    public var drankAt: Date

    /// Defaults to `.drank` (PRD §8 / §6.5: "Outcome is always drank" at the Pi;
    /// corrected later in the drink log if it was a gift or breakage).
    public var outcome: DrinkOutcome

    @Relationship(deleteRule: .cascade)
    public var memory: Memory?

    public init(
        id: UUID = UUID(),
        wine: Wine?,
        bottle: Bottle? = nil,
        drankAt: Date = .now,
        outcome: DrinkOutcome = .drank,
        memory: Memory? = nil
    ) {
        self.id = id
        self.wine = wine
        self.bottle = bottle
        self.drankAt = drankAt
        self.outcome = outcome
        self.memory = memory
    }
}
