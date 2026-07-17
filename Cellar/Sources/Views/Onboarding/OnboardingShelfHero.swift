//
//  OnboardingShelfHero.swift
//  Cellar — Views/Onboarding — Page 3: "Your fridge, mapped."
//
//  Hero is three shelf rows of small FoilCapsule dots, most neutral, a few
//  shifting to the real readiness colors (green/amber/red) in sequence — the
//  only page where those colors get explained, matching PRD "a ring, not a
//  highlighter": restrained, a handful of dots, not the whole grid lit up.
//
//  CTA style is copied from FridgeSetupView's "Add a shelf" button (capsule,
//  ledGlow fill, glassBlackDeep text) — the same "commit" affordance used
//  elsewhere in the app, not a new button style invented for onboarding.
//

import SwiftUI

struct OnboardingPageShelf: View {
    let onSetUpFridge: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            OnboardingShelfHero()
                .frame(height: 220)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Text("Your fridge, mapped.")
                    .onboardingTitle()
                Text("Every slot, every bottle, ready-to-drink at a glance.")
                    .onboardingSubline()
            }
            .padding(.horizontal, 36)

            Spacer()

            Button(action: onSetUpFridge) {
                Text("Set up your fridge")
                    .wineListType(size: 15, weight: .semibold)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(CellarPalette.ledGlow.opacity(0.9)))
                    .foregroundStyle(CellarPalette.glassBlackDeep)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.top, 64)
        .padding(.bottom, 96)
    }
}

struct OnboardingShelfHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let columns = 5
    private static let rows = 3

    /// (index into the flat rows*columns grid, the readiness it settles on).
    /// A handful, not "a few dots" turning into "most dots" — restrained.
    private static let highlights: [(index: Int, readiness: Readiness)] = [
        (2, .ready),
        (7, .hold),
        (11, .drinkSoon),
        (13, .ready),
    ]

    @State private var readiness = Array(
        repeating: Readiness.unknown,
        count: OnboardingShelfHero.rows * OnboardingShelfHero.columns
    )

    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<Self.rows, id: \.self) { row in
                HStack(spacing: 16) {
                    ForEach(0..<Self.columns, id: \.self) { col in
                        let i = row * Self.columns + col
                        FoilCapsule(
                            content: .resolved(foil: FoilVariant.allCases[i % FoilVariant.allCases.count], readiness: readiness[i]),
                            diameter: 26
                        )
                    }
                }
            }
        }
        .onAppear { animateSequence() }
    }

    private func animateSequence() {
        if reduceMotion {
            for h in Self.highlights { readiness[h.index] = h.readiness }
            return
        }
        for (offset, h) in Self.highlights.enumerated() {
            withAnimation(.easeOut(duration: 0.5).delay(0.3 + Double(offset) * 0.35)) {
                readiness[h.index] = h.readiness
            }
        }
    }
}

#Preview {
    OnboardingPageShelf(onSetUpFridge: {})
        .background(CellarPalette.glassBlackDeep)
}
