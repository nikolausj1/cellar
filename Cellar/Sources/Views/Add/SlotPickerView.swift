//
//  SlotPickerView.swift
//  Cellar — Views/Add
//
//  PRD §6.2 step 3: "Slot picker appears immediately: fridge map with open
//  slots highlighted. Tap one. Or tap 'Boxes' to place it with no slot."
//  The bottle passed in here already exists (created the instant the shutter
//  fired, wine == nil) — this screen's only job is to give it a location.
//
//  Placement goes through `CellarStore.place`, the only supported path
//  (PRD/brief). "Boxes" needs no store call to happen structurally — a fresh
//  bottle is already in `.boxes` by construction — but calling
//  `moveToBoxes` explicitly keeps this correct even when re-picking a
//  bottle that had already been placed somewhere else (bulk re-assignment).
//

import SwiftUI
import SwiftData

struct SlotPickerView: View {
    let bottle: Bottle
    /// Called once the bottle has a resolved location (a slot, or an
    /// explicit "Boxes"). The caller decides what happens next — for the
    /// single add flow, that's looping back to the camera (PRD §6.2 step 4).
    var onPlaced: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Shelf.index) private var shelves: [Shelf]
    @Query private var allBottles: [Bottle]

    private var layout: FridgeLayout { FridgeLayout(shelves: shelves.map(\.layout)) }
    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    private var occupiedByAddress: [SlotAddress: Bottle] {
        var dict: [SlotAddress: Bottle] = [:]
        for other in allBottles where other.status == .present && other.id != bottle.id {
            if case let .fridge(shelfIndex, slot) = other.location {
                dict[SlotAddress(shelfIndex: shelfIndex, slot: slot)] = other
            }
        }
        return dict
    }

    var body: some View {
        ZStack {
            CellarPalette.glassBlackDeep.ignoresSafeArea()
            VStack(spacing: 16) {
                header
                ScrollView {
                    SlotPickerCabinetView(
                        shelves: layout.shelves,
                        bottleForSlot: { occupiedByAddress[$0] },
                        currentYear: currentYear,
                        onPick: pick
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)

                boxesButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Place it")
                .wineListType(size: 18, weight: .semibold)
                .foregroundStyle(.white.opacity(0.95))
            Text("Tap a free slot, or send it to Boxes.")
                .cellarLabelType(size: 11)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.top, 20)
    }

    private var boxesButton: some View {
        Button(action: chooseBoxes) {
            Label("Boxes", systemImage: "shippingbox")
                .wineListType(size: 15, weight: .semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .foregroundStyle(.white.opacity(0.85))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func pick(_ address: SlotAddress) {
        let store = CellarStore(context: context)
        // `.slotOccupied` / `.invalidSlot` are backstops (the picker already
        // excludes occupied cells from tap targets) — swallow them the same
        // way the map does: nothing to show, the bottle simply stays where
        // it was, and the user can tap another free slot.
        try? store.place(bottle, at: address, layout: layout)
        onPlaced()
    }

    private func chooseBoxes() {
        let store = CellarStore(context: context)
        store.moveToBoxes(bottle)
        onPlaced()
    }
}
