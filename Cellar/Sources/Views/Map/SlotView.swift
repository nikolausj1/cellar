//
//  SlotView.swift
//  Cellar — Views/Map
//
//  One (shelf, slot) address: an occupied capsule or an empty cutout. PRD §6.1:
//  tap occupied → bottle detail; tap empty → callback out, pre-targeted to that
//  slot. This file never navigates itself — it only calls the closures it's
//  given, because the add flow and bottle detail screens are owned elsewhere.
//

import SwiftUI

struct SlotView: View {
    let address: SlotAddress
    let bottle: Bottle?
    let currentYear: Int
    var diameter: CGFloat = 34

    let onSelectBottle: (Bottle) -> Void
    let onSelectEmptySlot: (SlotAddress) -> Void

    var body: some View {
        Group {
            if let bottle {
                Button {
                    onSelectBottle(bottle)
                } label: {
                    FoilCapsule(content: capsuleContent(for: bottle), diameter: diameter)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: bottle))
            } else {
                Button {
                    onSelectEmptySlot(address)
                } label: {
                    emptyCutout
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Empty slot, shelf \(address.shelfIndex + 1), position \(address.slot + 1)")
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func capsuleContent(for bottle: Bottle) -> FoilCapsule.Content {
        guard let wine = bottle.wine else { return .unresolved }
        let readiness = ReadinessCalculator.readiness(for: wine.drinkWindow, currentYear: currentYear)
        return .resolved(foil: FoilVariant.forID(bottle.id), readiness: readiness)
    }

    private func accessibilityLabel(for bottle: Bottle) -> String {
        guard let wine = bottle.wine else { return "Unidentified bottle, still recognizing" }
        return "\(wine.producer) \(wine.name)"
    }

    private var emptyCutout: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [CellarPalette.glassBlackDeep, CellarPalette.glassBlack.opacity(0.4)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .overlay(
                Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 1.5, x: 0, y: 1)
    }
}
