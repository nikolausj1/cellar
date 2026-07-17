//
//  ReviewItem.swift
//  Cellar — Models
//
//  SwiftData. PRD §6.4 / §8: the single place naming decisions happen, for both
//  low-confidence phone recognitions and Pi button-scans.
//

import Foundation
import SwiftData

/// One recognition guess, from either `/recognize`'s `candidates` array or a Pi
/// `/queue` entry. Shared by Models and Services (Services depends on Models, not
/// the reverse) so PiClient and ReviewItem speak the exact same shape.
///
/// DEVIATION FROM THE PRD TEXT: PRD §8 writes `candidates: [Wine]`. This is
/// deliberately a plain Codable struct instead, not a relationship to `Wine`.
/// Reasoning: a candidate is an unconfirmed guess — most candidates in a review
/// item are rejected. Modeling them as real `Wine` records would either (a)
/// persist a `Wine` for every rejected guess, polluting the cellar with phantom
/// wines nobody owns, contradicting "one Wine per unique wine actually owned", or
/// (b) require inserting-then-deleting throwaway Wine rows on every review
/// decision. A `Wine` is only ever created once a candidate is accepted (§6.4,
/// mirrored in RecognitionQueue.findOrCreateWine). Storing `[WineCandidate]` as a
/// plain attribute also avoids relationship/delete-rule complexity for data that
/// isn't really an entity yet.
public struct WineCandidate: Codable, Hashable, Sendable {
    public var producer: String
    public var name: String
    public var vintage: Int?
    public var region: String?
    public var varietal: String?
    public var bottleSize: String?

    public init(
        producer: String,
        name: String,
        vintage: Int? = nil,
        region: String? = nil,
        varietal: String? = nil,
        bottleSize: String? = nil
    ) {
        self.producer = producer
        self.name = name
        self.vintage = vintage
        self.region = region
        self.varietal = varietal
        self.bottleSize = bottleSize
    }
}

public enum ReviewSource: String, Codable, Sendable {
    case phone
    case pi
}

@Model
public final class ReviewItem {
    @Attribute(.unique) public var id: UUID

    public var photo: Data
    public var candidates: [WineCandidate]
    public var confidence: Double
    public var source: ReviewSource

    /// The unnamed bottle awaiting a name. Optional because a Pi button-scan can
    /// create a review item with no cellar bottle behind it at all (an unknown
    /// bottle logged as a drink — PRD §6.5).
    public var bottle: Bottle?

    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        photo: Data,
        candidates: [WineCandidate],
        confidence: Double,
        source: ReviewSource,
        bottle: Bottle? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.photo = photo
        self.candidates = candidates
        self.confidence = confidence
        self.source = source
        self.bottle = bottle
        self.createdAt = createdAt
    }
}
