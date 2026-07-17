//
//  SlotPickerCabinetView.swift
//  Cellar — Views/Add
//
//  The fridge map redrawn for the SLOT PICKER, not the home map — reused by
//  both the single add flow (SlotPickerView) and the bulk batch screen
//  (BulkSlottingView). Deliberately a separate file from Views/Map (which is
//  off-limits to edit): the tap semantics are inverted from the map's
//  SlotView — there, tapping an occupied slot opens Bottle Detail; here, an
//  occupied slot must be "visibly non-tappable" (PRD brief) because there is
//  nothing to do with it in a placement picker. Only empty slots are live.
//
//  Visual language matches CellarTheme throughout (same palette, same
//  FoilCapsule) so this never reads as a second app bolted onto the map.
//

import SwiftUI

struct SlotPickerCabinetView: View {
    let shelves: [ShelfLayout]
    let bottleForSlot: (SlotAddress) -> Bottle?
    let currentYear: Int
    /// Whether an empty slot may currently be tapped. False in bulk mode
    /// when no bottle is selected — free slots still render highlighted
    /// (they ARE free), just inert, so the grid doesn't lie about geometry.
    var isPickingActive: Bool = true
    var onPick: (SlotAddress) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(shelves, id: \.index) { shelf in
                PickerShelfRow(
                    shelf: shelf,
                    bottleForSlot: { slot in bottleForSlot(SlotAddress(shelfIndex: shelf.index, slot: slot)) },
                    currentYear: currentYear,
                    isPickingActive: isPickingActive,
                    onPick: onPick
                )
            }
        }
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [CellarPalette.glassBlack, CellarPalette.glassBlackDeep],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [CellarPalette.railTop.opacity(0.9), CellarPalette.railBottom.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        )
        .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 14)
    }
}

private struct PickerShelfRow: View {
    let shelf: ShelfLayout
    let bottleForSlot: (Int) -> Bottle?
    let currentYear: Int
    let isPickingActive: Bool
    let onPick: (SlotAddress) -> Void

    private let capsuleDiameter: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [CellarPalette.ledGlow.opacity(0.16), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: 46)

                HStack(spacing: 0) {
                    ForEach(0..<max(shelf.slotCount, 0), id: \.self) { slot in
                        let address = SlotAddress(shelfIndex: shelf.index, slot: slot)
                        PickerSlotCell(
                            address: address,
                            bottle: bottleForSlot(slot),
                            currentYear: currentYear,
                            diameter: capsuleDiameter,
                            isPickingActive: isPickingActive,
                            onPick: onPick
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }

            LinearGradient(colors: [CellarPalette.railTop, CellarPalette.railBottom], startPoint: .top, endPoint: .bottom)
                .frame(height: shelf.style == .storage ? 7 : 4)
                .shadow(color: .black.opacity(0.7), radius: 3, x: 0, y: 3)
                .padding(.horizontal, 6)
        }
    }
}

private struct PickerSlotCell: View {
    let address: SlotAddress
    let bottle: Bottle?
    let currentYear: Int
    let diameter: CGFloat
    let isPickingActive: Bool
    let onPick: (SlotAddress) -> Void

    @State private var glowPhase: CGFloat = 0

    var body: some View {
        Group {
            if let bottle {
                // Occupied — visibly non-tappable: dimmed, desaturated, no
                // Button wrapper at all (there is genuinely nothing to do
                // with it here).
                FoilCapsule(content: capsuleContent(for: bottle), diameter: diameter)
                    .opacity(0.4)
                    .saturation(0.5)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Occupied")
            } else if isPickingActive {
                Button {
                    onPick(address)
                } label: {
                    freeCutout
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Place here, shelf \(address.shelfIndex + 1), position \(address.slot + 1)")
            } else {
                freeCutout
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var freeCutout: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [CellarPalette.ledGlow.opacity(0.22 + 0.1 * glowPhase), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .overlay(
                Circle().strokeBorder(CellarPalette.ledGlow.opacity(0.55 + 0.25 * glowPhase), lineWidth: 1.5)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    glowPhase = 1
                }
            }
    }

    private func capsuleContent(for bottle: Bottle) -> FoilCapsule.Content {
        guard let wine = bottle.wine else { return .unresolved }
        let readiness = ReadinessCalculator.readiness(for: wine.drinkWindow, currentYear: currentYear)
        return .resolved(foil: FoilVariant.forID(bottle.id), readiness: readiness)
    }
}
