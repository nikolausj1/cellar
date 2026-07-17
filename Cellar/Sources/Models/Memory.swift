//
//  Memory.swift
//  Cellar — Models
//
//  SwiftData. PRD §6.6 / §8: one memory slot per drink event, filled by any one of
//  photo / sentence / rating, with a three-rung capture cascade (voice note at the
//  Pi → app-open prompt → notification backstop). The cascade escalates across up
//  to three separate call sites (Pi voice-note handler, an app-open view, a local
//  notification handler) that this model layer has no control over — so the ONE
//  thing it can and must guarantee itself is that `promptedAt` can only ever be
//  written once, no matter which of those three call sites gets there first.
//

import Foundation
import SwiftData

@Model
public final class Memory {
    @Attribute(.unique) public var id: UUID

    public var text: String?
    public var photo: Data?
    public var rating: Int?

    /// Written EXACTLY ONCE (PRD §8 / §6.6: "one notification per drink event,
    /// forever"). `private(set)` — no file outside this one can assign it directly;
    /// `markPrompted()` below is the only way to set it, and it self-guards against
    /// a second write. Whichever rung of the cascade (app-open card or push
    /// notification) fires first calls `markPrompted()`; every later rung must
    /// check `promptedAt == nil` before firing at all, but even if that check is
    /// skipped somewhere, this method makes a double-write structurally impossible.
    public private(set) var promptedAt: Date?

    public init(id: UUID = UUID(), text: String? = nil, photo: Data? = nil, rating: Int? = nil) {
        self.id = id
        self.text = text
        self.photo = photo
        self.rating = rating
        self.promptedAt = nil
    }

    /// True once any of the three optional fields is filled — "any one fills the
    /// slot" (PRD §6.6).
    public var isFilled: Bool { text != nil || photo != nil || rating != nil }

    /// Records that the notification cascade fired. Returns `false` (a no-op) if it
    /// had already fired — the caller can use that to decide not to actually show a
    /// notification/card, closing the loop between "can't write twice" and "won't
    /// even try to prompt twice."
    @discardableResult
    public func markPrompted(at date: Date = .now) -> Bool {
        guard promptedAt == nil else { return false }
        promptedAt = date
        return true
    }
}
