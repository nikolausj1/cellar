//
//  FridgeCabinetView.swift
//  Cellar — Views/Map
//
//  The cabinet itself: near-black glass, a brushed stainless frame, shelves top
//  to bottom, deep shadow pooling between them. PRD §7: "a photoreal replica of
//  his actual fridge, not a diagram of it." Placeholder-first — every surface
//  here is a gradient and a shadow, no image assets.
//

import SwiftUI

struct FridgeCabinetView: View {
    let shelves: [ShelfLayout]
    let bottleForSlot: (SlotAddress) -> Bottle?
    let currentYear: Int
    let onSelectBottle: (Bottle) -> Void
    let onSelectEmptySlot: (SlotAddress) -> Void

    /// Unlit mode dims the glow and interior to near-nothing — used only by the
    /// empty state (PRD §6.1: "the fridge rendered empty and unlit").
    var isLit: Bool = true

    /// Forces the interior (and its background) to at least this tall even with
    /// zero shelves — used only so the true "no shelves configured yet" state
    /// still reads as an empty cabinet rather than a sliver. Never affects
    /// layout math (SlotAddress, occupancy) — purely cosmetic.
    var minHeight: CGFloat? = nil

    /// When true, the cabinet stretches to fill whatever vertical space its
    /// parent gives it instead of hugging its shelves' natural height — used
    /// only by the empty state so "the fridge rendered empty and unlit" reads
    /// as a full door, not a small floating card. Purely cosmetic.
    var expandsToFill: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            ForEach(shelves, id: \.index) { shelf in
                ShelfRowView(
                    shelf: shelf,
                    bottleForSlot: { slot in bottleForSlot(SlotAddress(shelfIndex: shelf.index, slot: slot)) },
                    currentYear: currentYear,
                    onSelectBottle: onSelectBottle,
                    onSelectEmptySlot: onSelectEmptySlot
                )
            }
            if expandsToFill { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: expandsToFill ? .infinity : nil)
        .padding(.vertical, 16)
        .background(interior)
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
        .opacity(isLit ? 1 : 0.55)
        .saturation(isLit ? 1 : 0.35)
        .animation(.easeInOut(duration: 0.4), value: isLit)
    }

    private var interior: some View {
        ZStack {
            LinearGradient(
                colors: [CellarPalette.glassBlack, CellarPalette.glassBlackDeep],
                startPoint: .top,
                endPoint: .bottom
            )

            // A faint overall warm wash, independent of the per-shelf glow, so the
            // whole cabinet reads as lit from within rather than lit per-shelf.
            if isLit {
                RadialGradient(
                    colors: [CellarPalette.ledGlow.opacity(0.05), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 420
                )
            }
        }
    }
}
