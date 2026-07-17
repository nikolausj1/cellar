//
//  FoilCapsule.swift
//  Cellar — Views/Map
//
//  PRD §7 / §6.1, and the brief above it in capital letters: an occupied slot is
//  a FOIL CAPSULE VIEWED HEAD-ON — the round foil-wrapped neck he actually sees
//  with the door open, stored neck-out. Never a label thumbnail; the label lives
//  on the bottle detail screen, which this file has no knowledge of.
//
//  Placeholder-first (Build Guide): pure programmatic SwiftUI — gradients,
//  shapes, shadows. No image assets, no generated textures.
//

import SwiftUI

/// Purely cosmetic foil-color variety (PRD §6.1: "gold / burgundy / black / matte
/// variety"). Has nothing to do with readiness — readiness is the ring, foil
/// color is just what the capsule looks like, deterministic per bottle so it
/// doesn't flicker between renders.
enum FoilVariant: CaseIterable {
    case gold, burgundy, black, matte

    var gradient: LinearGradient {
        let (light, dark): (Color, Color)
        switch self {
        case .gold: (light, dark) = (CellarPalette.foilGoldLight, CellarPalette.foilGoldDark)
        case .burgundy: (light, dark) = (CellarPalette.foilBurgundyLight, CellarPalette.foilBurgundyDark)
        case .black: (light, dark) = (CellarPalette.foilBlackLight, CellarPalette.foilBlackDark)
        case .matte: (light, dark) = (CellarPalette.foilMatteLight, CellarPalette.foilMatteDark)
        }
        return LinearGradient(colors: [light, dark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Deterministic per bottle identity — a given bottle always renders the same
    /// foil color; it's cosmetic variety, not a signal, so it must not shuffle.
    static func forID(_ id: UUID) -> FoilVariant {
        let bucket = Int(UInt(bitPattern: id.hashValue) % UInt(allCases.count))
        return allCases[bucket]
    }
}

/// The ring around an occupied capsule (PRD §7: "Restrained — a ring, not a
/// highlighter."). `.unknown` gets the neutral treatment called out explicitly
/// in the brief — never an error color.
private extension Readiness {
    var ringColor: Color {
        switch self {
        case .ready: CellarPalette.readinessReady
        case .hold: CellarPalette.readinessHold
        case .drinkSoon: CellarPalette.readinessDrinkSoon
        case .unknown: CellarPalette.readinessUnknown
        }
    }
}

/// A single foil capsule, head-on. `wine == nil` (recognition still pending) is
/// its own calm, frequent, non-error state — see the frosted/unresolved branch
/// below, which deliberately carries no ring and no color signal at all.
struct FoilCapsule: View {
    enum Content {
        /// Recognition resolved: a named wine, with a readiness ring.
        case resolved(foil: FoilVariant, readiness: Readiness)
        /// `wine == nil` — normal, frequent, calm. Never an error, never a
        /// warning icon.
        case unresolved
    }

    let content: Content
    var diameter: CGFloat = 34

    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        ZStack {
            switch content {
            case let .resolved(foil, readiness):
                capsuleBody(fill: AnyShapeStyle(foil.gradient))
                    .overlay(
                        Circle()
                            .strokeBorder(readiness.ringColor, lineWidth: readiness == .unknown ? 1 : 2)
                            .padding(-3)
                    )
            case .unresolved:
                capsuleBody(
                    fill: AnyShapeStyle(
                        LinearGradient(
                            colors: [CellarPalette.unresolvedLight, CellarPalette.unresolvedDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .opacity(0.78 + 0.1 * shimmerPhase)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                        shimmerPhase = 1
                    }
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func capsuleBody(fill: AnyShapeStyle) -> some View {
        Circle()
            .fill(fill)
            .overlay(
                // Metallic top-left highlight — reads as foil under the interior LED.
                Circle()
                    .trim(from: 0.55, to: 0.98)
                    .stroke(Color.white.opacity(0.35), lineWidth: diameter * 0.06)
                    .rotationEffect(.degrees(-135))
                    .blur(radius: 0.4)
            )
            .overlay(
                Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.55), radius: 2.5, x: 0, y: 2)
    }
}

#Preview {
    HStack(spacing: 16) {
        FoilCapsule(content: .resolved(foil: .gold, readiness: .ready))
        FoilCapsule(content: .resolved(foil: .burgundy, readiness: .hold))
        FoilCapsule(content: .resolved(foil: .black, readiness: .drinkSoon))
        FoilCapsule(content: .resolved(foil: .matte, readiness: .unknown))
        FoilCapsule(content: .unresolved)
    }
    .padding(40)
    .background(CellarPalette.glassBlack)
}
