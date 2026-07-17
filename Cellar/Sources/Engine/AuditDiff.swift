//
//  AuditDiff.swift
//  Cellar — Engine
//
//  Pure Foundation. The heal mechanism for the fridge map (PRD §6.8). A shelf audit
//  is verification, not identification: the app already knows what should be on the
//  shelf, so it just checks. PRD is explicit: "Ambiguous photo: report only the
//  count discrepancy and skip identification. A count is always trustworthy; a
//  guess isn't." This file makes that the only way to call the diff — when the
//  caller has no identified candidates, there is no code path that produces a
//  present/missing/unexpected guess.
//

import Foundation

public struct AuditDiff<ID: Hashable>: Equatable where ID: Equatable {
    /// Expected AND observed — the shelf checks out for this identity.
    public let present: Set<ID>
    /// Expected but NOT observed — investigate (drank / gifted / moved / broken?).
    public let missing: Set<ID>
    /// Observed but NOT expected — a bottle that shouldn't be here.
    public let unexpected: Set<ID>

    public let expectedCount: Int
    public let observedCount: Int

    /// True when the photo was too ambiguous to identify individual bottles.
    /// When true, `present`/`missing`/`unexpected` are always empty — count is
    /// the only trustworthy signal, so that's the only thing reported.
    public let isAmbiguous: Bool

    public var countDiscrepancy: Int { observedCount - expectedCount }
    public var countMatches: Bool { countDiscrepancy == 0 }
}

public enum AuditEngine {
    /// - Parameters:
    ///   - expected: identities the app believes should be on this shelf right now.
    ///   - observedCount: capsules counted in the photo. Always trustworthy (PRD §6.8),
    ///     always used, whether or not identification succeeded.
    ///   - identifiedCandidates: identities the recognizer is confident enough to name,
    ///     or `nil` when the photo is ambiguous. Passing `nil` is the ONLY way to reach
    ///     the ambiguous branch — there is no separate "confidence" knob to get wrong;
    ///     the caller either has candidates or it doesn't.
    public static func diff<ID: Hashable>(
        expected: Set<ID>,
        observedCount: Int,
        identifiedCandidates: Set<ID>?
    ) -> AuditDiff<ID> {
        guard let observed = identifiedCandidates else {
            return AuditDiff(
                present: [],
                missing: [],
                unexpected: [],
                expectedCount: expected.count,
                observedCount: observedCount,
                isAmbiguous: true
            )
        }

        return AuditDiff(
            present: expected.intersection(observed),
            missing: expected.subtracting(observed),
            unexpected: observed.subtracting(expected),
            expectedCount: expected.count,
            observedCount: observedCount,
            isAmbiguous: false
        )
    }
}
