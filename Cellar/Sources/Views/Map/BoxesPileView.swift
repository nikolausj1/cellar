//
//  BoxesPileView.swift
//  Cellar — Views/Map
//
//  PRD §6.1 / §8: "Boxes" is the second location — a pile, no slots. Same
//  capsule rendering as the fridge (still neck-out foil, still a readiness
//  ring), just laid out as a loose grid instead of shelves, because there is no
//  shelf geometry to respect here.
//

import SwiftUI

struct BoxesPileView: View {
    let bottles: [Bottle]
    let currentYear: Int
    let onSelectBottle: (Bottle) -> Void

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 14)]

    var body: some View {
        Group {
            if bottles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("Boxes are empty")
                        .cellarLabelType()
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(bottles, id: \.id) { bottle in
                        Button {
                            onSelectBottle(bottle)
                        } label: {
                            FoilCapsule(content: capsuleContent(for: bottle), diameter: 40)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [CellarPalette.glassBlack, CellarPalette.glassBlackDeep],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func capsuleContent(for bottle: Bottle) -> FoilCapsule.Content {
        guard let wine = bottle.wine else { return .unresolved }
        let readiness = ReadinessCalculator.readiness(for: wine.drinkWindow, currentYear: currentYear)
        return .resolved(foil: FoilVariant.forID(bottle.id), readiness: readiness)
    }
}
