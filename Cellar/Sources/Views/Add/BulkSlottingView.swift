//
//  BulkSlottingView.swift
//  Cellar — Views/Add
//
//  PRD §6.3: "Slot assignment happens AFTER, in one batch screen: a grid of
//  captured photos, drag or tap each into a slot." Tap-to-select then
//  tap-a-slot-to-place (the "tap" half of "drag or tap") — select a
//  thumbnail, the cabinet below lights up, tap a free slot.
//
//  Every bottle here already exists and already lives somewhere valid
//  (`.boxes` by default, or a slot from a previous pass through this
//  screen) — this view only ever calls `CellarStore.place` /
//  `CellarStore.moveToBoxes`, the same two supported paths everything else
//  in the app uses. "Finish" has nothing to reconcile: whatever isn't
//  slotted is already correctly sitting in Boxes.
//

import SwiftUI
import SwiftData
import UIKit

struct BulkSlottingView: View {
    let bottles: [Bottle]
    var onFinished: () -> Void
    /// Screenshot-only convenience (see CellarApp's `-showBulkSlotting`
    /// hook): pre-selects a bottle so `simctl`, which cannot tap a
    /// thumbnail, can still capture the picker section in its expanded
    /// state. Always nil on the real bulk-add path.
    var initialSelectedBottleID: UUID? = nil

    @Environment(\.modelContext) private var context
    @Query(sort: \Shelf.index) private var shelves: [Shelf]
    @Query private var allBottles: [Bottle]

    @State private var selectedBottleID: UUID?

    init(bottles: [Bottle], onFinished: @escaping () -> Void, initialSelectedBottleID: UUID? = nil) {
        self.bottles = bottles
        self.onFinished = onFinished
        self.initialSelectedBottleID = initialSelectedBottleID
        _selectedBottleID = State(initialValue: initialSelectedBottleID)
    }

    private var layout: FridgeLayout { FridgeLayout(shelves: shelves.map(\.layout)) }
    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    private var selectedBottle: Bottle? {
        guard let selectedBottleID else { return nil }
        return bottles.first { $0.id == selectedBottleID }
    }

    /// Occupancy for rendering the picker, excluding whichever bottle is
    /// currently selected — re-placing it (or leaving it where it is) must
    /// never show as a collision with itself. `CellarStore.place` re-checks
    /// live occupancy anyway; this only affects what's drawn.
    private var occupiedByAddress: [SlotAddress: Bottle] {
        var dict: [SlotAddress: Bottle] = [:]
        for other in allBottles where other.status == .present && other.id != selectedBottleID {
            if case let .fridge(shelfIndex, slot) = other.location {
                dict[SlotAddress(shelfIndex: shelfIndex, slot: slot)] = other
            }
        }
        return dict
    }

    private var unplacedCount: Int {
        bottles.filter { if case .boxes = $0.location { true } else { false } }.count
    }

    private let columns = [GridItem(.adaptive(minimum: 76, maximum: 92), spacing: 12)]

    var body: some View {
        ZStack {
            CellarPalette.glassBlackDeep.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 20) {
                        grid
                        if selectedBottle != nil {
                            pickerSection
                        } else {
                            Text("Tap a bottle, then tap a slot.")
                                .cellarLabelType(size: 11)
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.top, 16)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Place the load")
                    .wineListType(size: 18, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.95))
                Text("\(unplacedCount) of \(bottles.count) still in Boxes")
                    .cellarLabelType(size: 10)
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Button(action: onFinished) {
                Text("Finish")
                    .wineListType(size: 14, weight: .semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(CellarPalette.ledGlow.opacity(0.9)))
                    .foregroundStyle(CellarPalette.glassBlackDeep)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(bottles, id: \.id) { bottle in
                BulkThumbnailCard(
                    bottle: bottle,
                    isSelected: selectedBottleID == bottle.id,
                    onTap: { toggleSelection(bottle) }
                )
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Picker

    private var pickerSection: some View {
        VStack(spacing: 12) {
            SlotPickerCabinetView(
                shelves: layout.shelves,
                bottleForSlot: { occupiedByAddress[$0] },
                currentYear: currentYear,
                isPickingActive: true,
                onPick: place
            )
            Button(action: sendSelectedToBoxes) {
                Label("Send to Boxes", systemImage: "shippingbox")
                    .wineListType(size: 14, weight: .semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .foregroundStyle(.white.opacity(0.85))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ bottle: Bottle) {
        selectedBottleID = (selectedBottleID == bottle.id) ? nil : bottle.id
    }

    private func place(_ address: SlotAddress) {
        guard let bottle = selectedBottle else { return }
        let store = CellarStore(context: context)
        try? store.place(bottle, at: address, layout: layout)
        selectedBottleID = nil
    }

    private func sendSelectedToBoxes() {
        guard let bottle = selectedBottle else { return }
        let store = CellarStore(context: context)
        store.moveToBoxes(bottle)
        selectedBottleID = nil
    }
}

// MARK: - Thumbnail card

private struct BulkThumbnailCard: View {
    let bottle: Bottle
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                thumbnail
                Text(locationText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var thumbnail: some View {
        Group {
            if let data = bottle.labelPhoto, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                FoilCapsule(content: .unresolved, diameter: 40)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? CellarPalette.ledGlow : Color.white.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
        )
    }

    private var locationText: String {
        switch bottle.location {
        case .boxes: "Boxes"
        case let .fridge(shelf, slot): "S\(shelf + 1)·\(slot + 1)"
        }
    }
}
