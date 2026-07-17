//
//  SmokeTest.swift
//  Cellar — Engine smoke test
//
//  Engine-only. Per the Build Guide's engine-test recipe, this file is copied to
//  /tmp/main.swift and compiled directly against Sources/Engine/*.swift with
//  `swiftc` — no Xcode, no XCTest, no SwiftData. Top-level code here runs as the
//  program's entry point.
//
//    xattr -cr Sources && cp Tests/SmokeTest.swift /tmp/main.swift && \
//      swiftc -O Sources/Engine/*.swift /tmp/main.swift -o /tmp/t && /tmp/t
//

import Foundation

// MARK: - Tiny assertion harness

var passCount = 0
var failCount = 0
var failures: [String] = []

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if condition() {
        passCount += 1
    } else {
        failCount += 1
        let text = "FAIL: \(message) (\(file):\(line))"
        failures.append(text)
        print(text)
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String, file: StaticString = #file, line: UInt = #line) {
    check(actual == expected, "\(label) — expected \(expected), got \(actual)", file: file, line: line)
}

// =====================================================================
// MARK: - Readiness
// =====================================================================

// nil window -> unknown
checkEqual(ReadinessCalculator.readiness(for: nil, currentYear: 2026), .unknown, "nil window is unknown")

// window with both bounds nil -> unknown
checkEqual(
    ReadinessCalculator.readiness(for: DrinkWindow(startYear: nil, endYear: nil), currentYear: 2026),
    .unknown,
    "empty window is unknown"
)

// open-ended start (drink any time up to end)
checkEqual(
    ReadinessCalculator.readiness(for: DrinkWindow(startYear: nil, endYear: 2030), currentYear: 2020),
    .ready,
    "open-ended start, well before end, is ready"
)
checkEqual(
    ReadinessCalculator.readiness(for: DrinkWindow(startYear: nil, endYear: 2030), currentYear: 2030),
    .drinkSoon,
    "open-ended start, at end year, is drinkSoon"
)
checkEqual(
    ReadinessCalculator.readiness(for: DrinkWindow(startYear: nil, endYear: 2030), currentYear: 2035),
    .drinkSoon,
    "open-ended start, past end year, is drinkSoon"
)

// open-ended end (no upper bound, ready forever once start hits)
checkEqual(
    ReadinessCalculator.readiness(for: DrinkWindow(startYear: 2025, endYear: nil), currentYear: 2020),
    .hold,
    "open-ended end, before start, is hold"
)
checkEqual(
    ReadinessCalculator.readiness(for: DrinkWindow(startYear: 2025, endYear: nil), currentYear: 2025),
    .ready,
    "open-ended end, at start, is ready"
)
checkEqual(
    ReadinessCalculator.readiness(for: DrinkWindow(startYear: 2025, endYear: nil), currentYear: 2099),
    .ready,
    "open-ended end, far past start, is still ready (no upper bound)"
)

// single-year window (start == end)
checkEqual(
    ReadinessCalculator.readiness(for: DrinkWindow(startYear: 2026, endYear: 2026), currentYear: 2025),
    .hold,
    "single-year window, before it, is hold"
)
checkEqual(
    ReadinessCalculator.readiness(for: DrinkWindow(startYear: 2026, endYear: 2026), currentYear: 2026),
    .drinkSoon,
    "single-year window, at it, is drinkSoon"
)
checkEqual(
    ReadinessCalculator.readiness(for: DrinkWindow(startYear: 2026, endYear: 2026), currentYear: 2027),
    .drinkSoon,
    "single-year window, past it, is drinkSoon"
)

// boundary years on a normal window
let normalWindow = DrinkWindow(startYear: 2024, endYear: 2028)
checkEqual(ReadinessCalculator.readiness(for: normalWindow, currentYear: 2023), .hold, "year before start is hold")
checkEqual(ReadinessCalculator.readiness(for: normalWindow, currentYear: 2024), .ready, "exact start year is ready")
checkEqual(ReadinessCalculator.readiness(for: normalWindow, currentYear: 2026), .ready, "middle of window is ready")
checkEqual(ReadinessCalculator.readiness(for: normalWindow, currentYear: 2027), .ready, "year before end is ready")
checkEqual(ReadinessCalculator.readiness(for: normalWindow, currentYear: 2028), .drinkSoon, "exact end year is drinkSoon")
checkEqual(ReadinessCalculator.readiness(for: normalWindow, currentYear: 2029), .drinkSoon, "year after end is drinkSoon")

// past-end far in the future stays drinkSoon (never reverts to hold/ready/unknown)
checkEqual(ReadinessCalculator.readiness(for: normalWindow, currentYear: 2099), .drinkSoon, "far past end is still drinkSoon")

// =====================================================================
// MARK: - FridgeLayout
// =====================================================================

let displayShelf = ShelfLayout(index: 0, slotCount: 4, style: .display)
let storageShelfA = ShelfLayout(index: 1, slotCount: 6, style: .storage)
let storageShelfB = ShelfLayout(index: 2, slotCount: 0, style: .storage) // zero-slot shelf is legal
let layout = FridgeLayout(shelves: [storageShelfA, displayShelf, storageShelfB]) // deliberately out of order

// construction sorts shelves by index
checkEqual(layout.shelves.map(\.index), [0, 1, 2], "FridgeLayout sorts shelves by index")

// capacity
checkEqual(layout.capacity, 10, "capacity sums slotCount across shelves (4 + 6 + 0)")

// configuration validity
check(layout.isConfigurationValid, "layout with unique indices and non-negative slot counts is valid")
let duplicateLayout = FridgeLayout(shelves: [ShelfLayout(index: 0, slotCount: 2, style: .display), ShelfLayout(index: 0, slotCount: 3, style: .storage)])
check(!duplicateLayout.isConfigurationValid, "layout with duplicate shelf indices is invalid")

// shelf(at:)
checkEqual(layout.shelf(at: 1)?.slotCount, 6, "shelf(at:) finds the right shelf")
check(layout.shelf(at: 99) == nil, "shelf(at:) returns nil for a nonexistent shelf")

// address validation — valid cases
check(layout.isValid(SlotAddress(shelfIndex: 0, slot: 0)), "first slot of shelf 0 is valid")
check(layout.isValid(SlotAddress(shelfIndex: 0, slot: 3)), "last slot of shelf 0 is valid")
check(layout.isValid(SlotAddress(shelfIndex: 1, slot: 5)), "last slot of shelf 1 is valid")

// address validation — invalid cases (out of range, shelf not found, empty shelf)
check(!layout.isValid(SlotAddress(shelfIndex: 0, slot: 4)), "one past the last slot is invalid")
check(!layout.isValid(SlotAddress(shelfIndex: 0, slot: -1)), "negative slot is invalid")
check(!layout.isValid(SlotAddress(shelfIndex: 5, slot: 0)), "nonexistent shelf is invalid")
check(!layout.isValid(SlotAddress(shelfIndex: 2, slot: 0)), "slot 0 on a zero-capacity shelf is invalid")

// validate(_:) throws the right error
do {
    try layout.validate(SlotAddress(shelfIndex: 9, slot: 0))
    check(false, "validate should have thrown for a missing shelf")
} catch FridgeLayoutError.shelfNotFound(let shelf) {
    checkEqual(shelf, 9, "shelfNotFound carries the right shelf index")
} catch {
    check(false, "validate threw the wrong error type for a missing shelf")
}

do {
    try layout.validate(SlotAddress(shelfIndex: 0, slot: 10))
    check(false, "validate should have thrown for an out-of-range slot")
} catch FridgeLayoutError.slotOutOfRange(let shelf, let slot, let slotCount) {
    checkEqual(shelf, 0, "slotOutOfRange carries the right shelf")
    checkEqual(slot, 10, "slotOutOfRange carries the right slot")
    checkEqual(slotCount, 4, "slotOutOfRange carries the right slotCount")
} catch {
    check(false, "validate threw the wrong error type for an out-of-range slot")
}

// occupancy math — empty fridge
checkEqual(layout.occupiedCount(occupied: []), 0, "empty occupancy has zero occupied")
checkEqual(layout.freeCount(occupied: []), 10, "empty occupancy has full free count")
check(!layout.isFull(occupied: []), "empty fridge is not full")
checkEqual(layout.nextFreeAddress(occupied: []), SlotAddress(shelfIndex: 0, slot: 0), "next free on empty fridge is the very first slot")

// occupancy math — partially filled
let partiallyOccupied: Set<SlotAddress> = [
    SlotAddress(shelfIndex: 0, slot: 0),
    SlotAddress(shelfIndex: 0, slot: 1),
    SlotAddress(shelfIndex: 1, slot: 0),
]
checkEqual(layout.occupiedCount(occupied: partiallyOccupied), 3, "occupiedCount counts valid occupied addresses")
checkEqual(layout.freeCount(occupied: partiallyOccupied), 7, "freeCount is capacity minus occupied")
checkEqual(layout.nextFreeAddress(occupied: partiallyOccupied), SlotAddress(shelfIndex: 0, slot: 2), "next free skips occupied slots in shelf/slot order")
checkEqual(layout.freeAddresses(occupied: partiallyOccupied).count, 7, "freeAddresses count matches freeCount")

// occupancy math — addresses outside the current layout don't count as occupied
let occupiedWithStaleAddress: Set<SlotAddress> = [SlotAddress(shelfIndex: 99, slot: 0)]
checkEqual(layout.occupiedCount(occupied: occupiedWithStaleAddress), 0, "stale/out-of-layout addresses are not counted as occupied")

// occupancy math — completely full fridge
let fullLayout = FridgeLayout(shelves: [ShelfLayout(index: 0, slotCount: 2, style: .display)])
let fullOccupancy: Set<SlotAddress> = [SlotAddress(shelfIndex: 0, slot: 0), SlotAddress(shelfIndex: 0, slot: 1)]
check(fullLayout.isFull(occupied: fullOccupancy), "fridge with every slot occupied reports full")
check(fullLayout.nextFreeAddress(occupied: fullOccupancy) == nil, "nextFreeAddress is nil when full")
checkEqual(fullLayout.freeAddresses(occupied: fullOccupancy).count, 0, "freeAddresses is empty when full")

// shelf occupancy breakdown
let breakdown = layout.shelfOccupancy(occupied: partiallyOccupied)
checkEqual(breakdown[0]?.occupied, 2, "shelf 0 occupancy breakdown is correct")
checkEqual(breakdown[0]?.capacity, 4, "shelf 0 capacity breakdown is correct")
checkEqual(breakdown[1]?.occupied, 1, "shelf 1 occupancy breakdown is correct")
checkEqual(breakdown[2]?.occupied, 0, "shelf 2 (empty shelf) occupancy breakdown is correct")

// allAddresses count matches capacity
checkEqual(layout.allAddresses().count, layout.capacity, "allAddresses count matches capacity")

// empty layout (no shelves at all — the true empty-fridge / first-run state)
let emptyLayout = FridgeLayout(shelves: [])
checkEqual(emptyLayout.capacity, 0, "layout with no shelves has zero capacity")
check(emptyLayout.nextFreeAddress(occupied: []) == nil, "layout with no shelves has no next free address")
check(emptyLayout.isFull(occupied: []), "layout with no shelves is trivially full (0 free of 0)")

// =====================================================================
// MARK: - Placement decision (the pure half of CellarStore.place)
//
// SCOPE NOTE: these assertions cover FridgeLayout.placementDecision, which is the
// branching logic CellarStore.place delegates to. They do NOT cover CellarStore
// itself — it touches ModelContext and is unreachable from the swiftc recipe. See
// the report for exactly what that leaves untested.
// =====================================================================

// layout: shelf 0 has 4 slots, shelf 1 has 6, shelf 2 has 0
let occupiedSlots: Set<SlotAddress> = [
    SlotAddress(shelfIndex: 0, slot: 0),
    SlotAddress(shelfIndex: 0, slot: 1),
    SlotAddress(shelfIndex: 1, slot: 3),
]

// free slot, bottle coming from boxes (no current address) -> allowed
checkEqual(
    layout.placementDecision(for: SlotAddress(shelfIndex: 0, slot: 2), occupied: occupiedSlots, currentAddress: nil),
    .allowed,
    "placing into a free slot from boxes is allowed"
)

// free slot, bottle moving from another slot -> allowed
checkEqual(
    layout.placementDecision(for: SlotAddress(shelfIndex: 1, slot: 0), occupied: occupiedSlots, currentAddress: SlotAddress(shelfIndex: 0, slot: 0)),
    .allowed,
    "moving a bottle from one slot to a different free slot is allowed"
)

// slot held by ANOTHER bottle -> occupied (the bug this closes)
checkEqual(
    layout.placementDecision(for: SlotAddress(shelfIndex: 0, slot: 0), occupied: occupiedSlots, currentAddress: nil),
    .occupied,
    "placing into a slot another bottle holds is refused"
)
checkEqual(
    layout.placementDecision(for: SlotAddress(shelfIndex: 1, slot: 3), occupied: occupiedSlots, currentAddress: SlotAddress(shelfIndex: 0, slot: 1)),
    .occupied,
    "moving a bottle onto an occupied slot is refused"
)

// re-tapping the slot the bottle already holds -> noOp, NOT occupied
checkEqual(
    layout.placementDecision(for: SlotAddress(shelfIndex: 0, slot: 0), occupied: occupiedSlots, currentAddress: SlotAddress(shelfIndex: 0, slot: 0)),
    .noOp,
    "re-placing a bottle at its own address is a no-op, not a collision with itself"
)

// out-of-range / nonexistent shelf / zero-capacity shelf -> invalid
checkEqual(
    layout.placementDecision(for: SlotAddress(shelfIndex: 0, slot: 4), occupied: occupiedSlots, currentAddress: nil),
    .invalid,
    "placing past the last slot of a shelf is invalid"
)
checkEqual(
    layout.placementDecision(for: SlotAddress(shelfIndex: 99, slot: 0), occupied: occupiedSlots, currentAddress: nil),
    .invalid,
    "placing on a nonexistent shelf is invalid"
)
checkEqual(
    layout.placementDecision(for: SlotAddress(shelfIndex: 2, slot: 0), occupied: occupiedSlots, currentAddress: nil),
    .invalid,
    "placing on a zero-capacity shelf is invalid"
)
checkEqual(
    layout.placementDecision(for: SlotAddress(shelfIndex: 0, slot: -1), occupied: occupiedSlots, currentAddress: nil),
    .invalid,
    "placing at a negative slot is invalid"
)

// invalid beats noOp: if the layout shrank under a bottle, re-placing it at its
// own now-nonexistent address is still invalid, not a free pass
checkEqual(
    layout.placementDecision(for: SlotAddress(shelfIndex: 99, slot: 0), occupied: occupiedSlots, currentAddress: SlotAddress(shelfIndex: 99, slot: 0)),
    .invalid,
    "invalid beats no-op when the layout no longer contains the bottle's own address"
)

// invalid beats occupied
checkEqual(
    layout.placementDecision(for: SlotAddress(shelfIndex: 2, slot: 0), occupied: [SlotAddress(shelfIndex: 2, slot: 0)], currentAddress: nil),
    .invalid,
    "invalid beats occupied for an address outside the layout"
)

// placement into an entirely empty fridge
checkEqual(
    layout.placementDecision(for: SlotAddress(shelfIndex: 0, slot: 0), occupied: [], currentAddress: nil),
    .allowed,
    "any valid slot in an empty fridge is allowed"
)

// free-slot ordering — what the slot picker renders. Must be shelf order, then
// slot order, and must exclude occupied slots.
let freeInOrder = layout.freeAddresses(occupied: occupiedSlots)
checkEqual(freeInOrder.count, 7, "freeAddresses excludes every occupied slot")
checkEqual(freeInOrder.first, SlotAddress(shelfIndex: 0, slot: 2), "freeAddresses starts at the first free slot in layout order")
check(!freeInOrder.contains(SlotAddress(shelfIndex: 0, slot: 0)), "freeAddresses omits an occupied slot")
check(!freeInOrder.contains(SlotAddress(shelfIndex: 1, slot: 3)), "freeAddresses omits an occupied slot on a later shelf")
check(
    freeInOrder == freeInOrder.sorted(by: { ($0.shelfIndex, $0.slot) < ($1.shelfIndex, $1.slot) }),
    "freeAddresses is ordered by shelf then slot"
)
check(
    freeInOrder.allSatisfy { layout.isValid($0) },
    "every address freeAddresses returns is a valid address"
)

// freeAddresses agrees with nextFreeAddress — the picker and the bulk-add batch
// screen must never disagree about what "next" is
checkEqual(
    layout.nextFreeAddress(occupied: occupiedSlots),
    freeInOrder.first,
    "nextFreeAddress matches the head of freeAddresses"
)

// =====================================================================
// MARK: - AuditDiff
// =====================================================================

let expectedShelf: Set<String> = ["Ornellaia 2015", "Duckhorn 2018", "Caymus 2019"]

// present / missing / unexpected, fully identified
let identifiedResult = AuditEngine.diff(
    expected: expectedShelf,
    observedCount: 3,
    identifiedCandidates: ["Ornellaia 2015", "Caymus 2019", "Silver Oak 2017"]
)
checkEqual(identifiedResult.present, ["Ornellaia 2015", "Caymus 2019"], "audit present set is the intersection")
checkEqual(identifiedResult.missing, ["Duckhorn 2018"], "audit missing set is expected minus observed")
checkEqual(identifiedResult.unexpected, ["Silver Oak 2017"], "audit unexpected set is observed minus expected")
check(!identifiedResult.isAmbiguous, "fully identified audit is not ambiguous")
checkEqual(identifiedResult.countDiscrepancy, 0, "count discrepancy is zero when counts agree")
check(identifiedResult.countMatches, "countMatches is true when counts agree")

// everything present, nothing missing or unexpected
let perfectResult = AuditEngine.diff(expected: expectedShelf, observedCount: 3, identifiedCandidates: expectedShelf)
checkEqual(perfectResult.present, expectedShelf, "perfect audit — everything present")
check(perfectResult.missing.isEmpty, "perfect audit — nothing missing")
check(perfectResult.unexpected.isEmpty, "perfect audit — nothing unexpected")

// ambiguous photo: count-only path, no identity guessing
let ambiguousResult = AuditEngine.diff(expected: expectedShelf, observedCount: 2, identifiedCandidates: nil)
check(ambiguousResult.isAmbiguous, "audit with nil candidates is ambiguous")
check(ambiguousResult.present.isEmpty, "ambiguous audit never guesses present")
check(ambiguousResult.missing.isEmpty, "ambiguous audit never guesses missing")
check(ambiguousResult.unexpected.isEmpty, "ambiguous audit never guesses unexpected")
checkEqual(ambiguousResult.expectedCount, 3, "ambiguous audit still reports expected count")
checkEqual(ambiguousResult.observedCount, 2, "ambiguous audit still reports observed count")
checkEqual(ambiguousResult.countDiscrepancy, -1, "ambiguous audit reports the count discrepancy (missing one)")
check(!ambiguousResult.countMatches, "ambiguous audit with a mismatch reports countMatches false")

// ambiguous photo where the count happens to match — still ambiguous, still no identities
let ambiguousMatchingCount = AuditEngine.diff(expected: expectedShelf, observedCount: 3, identifiedCandidates: nil)
check(ambiguousMatchingCount.isAmbiguous, "ambiguous audit stays ambiguous even when the count matches")
check(ambiguousMatchingCount.countMatches, "ambiguous audit with matching count reports countMatches true")
check(ambiguousMatchingCount.present.isEmpty, "ambiguous audit never guesses present, even on a matching count")

// empty shelf, nothing expected, nothing observed
let emptyShelfResult = AuditEngine.diff(expected: [], observedCount: 0, identifiedCandidates: Set<String>())
check(emptyShelfResult.present.isEmpty, "empty shelf audit has no present")
check(emptyShelfResult.missing.isEmpty, "empty shelf audit has no missing")
check(emptyShelfResult.unexpected.isEmpty, "empty shelf audit has no unexpected")

// =====================================================================
// MARK: - CellarValue
// =====================================================================

// empty cellar
let emptySummary = CellarValueCalculator.aggregate([])
checkEqual(emptySummary.total, 0, "empty cellar totals to zero")
check(!emptySummary.isEstimate, "empty cellar is not flagged as an estimate (nothing to estimate)")
checkEqual(emptySummary.valuedBottleCount, 0, "empty cellar has zero valued bottles")
checkEqual(emptySummary.unvaluedBottleCount, 0, "empty cellar has zero unvalued bottles")

// mix of valued (estimate) and unvalued bottles
let mixedBottles = [
    ValuedBottle(value: 120.0),
    ValuedBottle(value: 45.5),
    ValuedBottle(value: nil), // not yet enriched
]
let mixedSummary = CellarValueCalculator.aggregate(mixedBottles)
checkEqual(mixedSummary.total, 165.5, "mixed cellar totals only the valued bottles")
check(mixedSummary.isEstimate, "cellar with any estimate-valued bottle is flagged as an estimate")
checkEqual(mixedSummary.valuedBottleCount, 2, "mixed cellar counts valued bottles correctly")
checkEqual(mixedSummary.unvaluedBottleCount, 1, "mixed cellar counts unvalued bottles correctly")

// all unvalued — total is zero but distinguishable from a truly empty cellar
let allUnvalued = CellarValueCalculator.aggregate([ValuedBottle(value: nil), ValuedBottle(value: nil)])
checkEqual(allUnvalued.total, 0, "all-unvalued cellar totals to zero")
check(!allUnvalued.isEstimate, "all-unvalued cellar is not flagged as an estimate (no value exists to be one)")
checkEqual(allUnvalued.unvaluedBottleCount, 2, "all-unvalued cellar counts both unvalued bottles")

// a non-estimate value (hypothetical future ground-truth source) does not by
// itself flag the aggregate, but mixing it with a real estimate does
let nonEstimateOnly = CellarValueCalculator.aggregate([ValuedBottle(value: 50, isEstimate: false)])
check(!nonEstimateOnly.isEstimate, "an aggregate made only of non-estimate values is not flagged as an estimate")

let estimateAndGroundTruth = CellarValueCalculator.aggregate([
    ValuedBottle(value: 50, isEstimate: false),
    ValuedBottle(value: 9200, isEstimate: true),
])
check(estimateAndGroundTruth.isEstimate, "mixing in even one estimate flags the whole aggregate as an estimate")
checkEqual(estimateAndGroundTruth.total, 9250, "mixed ground-truth + estimate totals correctly")

// single bottle, single value
let singleBottleSummary = CellarValueCalculator.aggregate([ValuedBottle(value: 9200)])
checkEqual(singleBottleSummary.total, 9200, "single bottle total matches its value")
check(singleBottleSummary.isEstimate, "single estimated bottle flags the aggregate")

// =====================================================================
// MARK: - Summary
// =====================================================================

print("")
print("Cellar Engine Smoke Test")
print(String(repeating: "-", count: 40))
print("Passed: \(passCount)")
print("Failed: \(failCount)")

if failCount > 0 {
    print("")
    print("Failures:")
    for failure in failures {
        print("  \(failure)")
    }
    exit(1)
} else {
    print("All checks passed.")
    exit(0)
}
