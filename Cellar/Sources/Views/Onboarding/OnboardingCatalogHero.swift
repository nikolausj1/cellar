//
//  OnboardingCatalogHero.swift
//  Cellar — Views/Onboarding — Page 1: "A cellar that catalogs itself."
//
//  Hero is a 4x3 grid of FoilCapsule — the app's own bottle-neck-out capsule,
//  reused wholesale rather than inventing new bottle art for onboarding.
//  Readiness is `.unknown` across the board (neutral ring): this page is
//  about cataloging, not drink-window signal, so the readiness colors stay
//  reserved for page 3 where they're actually explained.
//

import SwiftUI

struct OnboardingPageCatalog: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            OnboardingCatalogHero()
                .frame(height: 220)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Text("A cellar that catalogs itself.")
                    .onboardingTitle()
                Text("Point the camera at a label; the bottle files itself.")
                    .onboardingSubline()
            }
            .padding(.horizontal, 36)

            Spacer()
            Spacer()
        }
        .padding(.top, 64)
        .padding(.bottom, 96)
    }
}

struct OnboardingCatalogHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let count = 12
    private static let highlightIndex = 5

    /// Hand-arranged, not `index % caseCount`: with a 4-wide grid and 4 foil
    /// variants, any stride collapses into color-sorted columns — which reads
    /// as a button palette, not a cellar. Real racks mix foils irregularly.
    private static let foils: [FoilVariant] = [
        .gold, .black, .burgundy, .matte,
        .burgundy, .matte, .gold, .black,
        .black, .gold, .matte, .burgundy,
    ]

    @State private var appeared = Array(repeating: false, count: OnboardingCatalogHero.count)

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(0..<Self.count, id: \.self) { i in
                capsule(at: i)
                    .opacity(appeared[i] ? 1 : 0)
                    .scaleEffect(appeared[i] ? 1 : 0.85)
            }
        }
        .padding(.horizontal, 28)
        .onAppear { animateIn() }
    }

    @ViewBuilder
    private func capsule(at index: Int) -> some View {
        ZStack {
            if index == Self.highlightIndex {
                // The "one of them glowing warm" beat — a soft ledGlow halo
                // behind a single capsule, not a readiness ring, since warmth
                // here means "the light finds one bottle," not a status.
                Circle()
                    .fill(CellarPalette.ledGlow)
                    .blur(radius: 12)
                    .opacity(0.5)
                    .frame(width: 44, height: 44)
            }
            FoilCapsule(
                content: .resolved(foil: Self.foils[index], readiness: .unknown),
                diameter: 34
            )
        }
    }

    private func animateIn() {
        for i in 0..<Self.count {
            if reduceMotion {
                appeared[i] = true
            } else {
                withAnimation(.easeOut(duration: 0.45).delay(Double(i) * 0.045)) {
                    appeared[i] = true
                }
            }
        }
    }
}

#Preview {
    OnboardingPageCatalog()
        .background(CellarPalette.glassBlackDeep)
}
