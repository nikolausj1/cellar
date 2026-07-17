//
//  EmptyFridgeView.swift
//  Cellar — Views/Map
//
//  PRD §6.1: "Empty state: the fridge rendered empty and unlit, one line —
//  'Nothing in here yet' — and a single Add button. This is the load-day
//  starting screen and it should feel like an invitation, not an error." This
//  is also the very first thing Justin ever sees when he opens the app for the
//  first time, before Setup has even been run — it has to hold up with zero
//  shelves configured, not just zero bottles in a configured fridge.
//

import Foundation
import SwiftUI

struct EmptyFridgeView: View {
    /// Whatever shelves exist right now — possibly none at all, pre-Setup.
    /// Rendered dim and unlit either way; there's nothing to show, so nothing
    /// pretends otherwise.
    let shelves: [ShelfLayout]
    let onAdd: () -> Void

    var body: some View {
        ZStack {
            // Real geometry only — if Setup hasn't run yet there are zero
            // shelves, and this renders the bare unlit glass box rather than
            // inventing shelf counts. The real fridge geometry is an open
            // question (PRD §12 Q1); nothing here guesses at it.
            FridgeCabinetView(
                shelves: shelves,
                bottleForSlot: { _ in nil },
                currentYear: Calendar.current.component(.year, from: .now),
                onSelectBottle: { _ in },
                onSelectEmptySlot: { _ in },
                isLit: false,
                minHeight: 420,
                expandsToFill: true
            )

            VStack(spacing: 18) {
                Spacer()
                VStack(spacing: 6) {
                    Text("Nothing in here yet")
                        .wineListType(size: 17, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Button(action: onAdd) {
                    Label("Add", systemImage: "camera.fill")
                        .wineListType(size: 15, weight: .semibold)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(CellarPalette.ledGlow.opacity(0.9))
                        )
                        .foregroundStyle(CellarPalette.glassBlackDeep)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.vertical, 40)
        }
    }
}
