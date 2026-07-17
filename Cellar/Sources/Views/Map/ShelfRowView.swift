//
//  ShelfRowView.swift
//  Cellar — Views/Map
//
//  One shelf: a brushed-stainless rail, warm LED glow pooling from its edge
//  (_inbox photo 2), and its slots left to right. Storage shelves get the wood
//  slot dividers visible in _inbox photo 3; display shelves are a plainer rail.
//  Every occupied slot renders identically as a foil capsule regardless of
//  shelf style — see FoilCapsule.swift for why that's non-negotiable here.
//

import SwiftUI

struct ShelfRowView: View {
    let shelf: ShelfLayout
    let bottleForSlot: (Int) -> Bottle?
    let currentYear: Int
    let onSelectBottle: (Bottle) -> Void
    let onSelectEmptySlot: (SlotAddress) -> Void

    private let capsuleDiameter: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            // Warm interior LED glow, pooling from the shelf edge upward onto the
            // capsules (PRD §7: FFE9C4 at low opacity, pooling from the shelf edges).
            ZStack {
                LinearGradient(
                    colors: [CellarPalette.ledGlow.opacity(0.16), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: 46)

                slotsRow
                    .padding(.bottom, 6)
            }

            rail
        }
    }

    private var slotsRow: some View {
        HStack(spacing: 0) {
            ForEach(0..<max(shelf.slotCount, 0), id: \.self) { slot in
                let address = SlotAddress(shelfIndex: shelf.index, slot: slot)
                Group {
                    if shelf.style == .storage, slot > 0 {
                        woodDivider
                    }
                    SlotView(
                        address: address,
                        bottle: bottleForSlot(slot),
                        currentYear: currentYear,
                        diameter: capsuleDiameter,
                        onSelectBottle: onSelectBottle,
                        onSelectEmptySlot: onSelectEmptySlot
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
    }

    private var woodDivider: some View {
        LinearGradient(colors: [CellarPalette.woodLight, CellarPalette.woodDark], startPoint: .top, endPoint: .bottom)
            .frame(width: 3, height: capsuleDiameter + 10)
            .clipShape(RoundedRectangle(cornerRadius: 1))
            .shadow(color: .black.opacity(0.4), radius: 1, x: 0.5, y: 0)
    }

    /// The brushed stainless rail the bottles rest against — PRD §7: gradient
    /// #C8CCD0 → #8E9499. Display shelves get a slightly thinner, plainer rail;
    /// storage shelves (where he actually keeps the bulk of the collection) get
    /// the fuller rail with an end-cap highlight, matching the photos.
    private var rail: some View {
        LinearGradient(colors: [CellarPalette.railTop, CellarPalette.railBottom], startPoint: .top, endPoint: .bottom)
            .frame(height: shelf.style == .storage ? 7 : 4)
            .overlay(
                LinearGradient(colors: [Color.white.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 1.5),
                alignment: .top
            )
            .shadow(color: .black.opacity(0.7), radius: 3, x: 0, y: 3)
            .padding(.horizontal, 6)
    }
}
