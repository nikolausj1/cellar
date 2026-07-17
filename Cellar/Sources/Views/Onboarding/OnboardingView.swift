//
//  OnboardingView.swift
//  Cellar — Views/Onboarding
//
//  Shown once, ever — @AppStorage("Cellar.hasSeenOnboarding") mirrors the
//  existing "Cellar.hasSeenCameraCoach" pattern (CameraCaptureView): the view
//  that shows the one-time thing owns the flag and flips it when it's done.
//  CellarApp reads the same UserDefaults key at launch (before this view
//  exists) to decide whether to present it at all — see CellarApp.swift.
//
//  Three pages, all SwiftUI-native art built from the app's own palette and
//  FoilCapsule — no raster images, no stock illustration. `onFinished`
//  hands navigation back to CellarApp rather than owning it: Skip means
//  "just dismiss," the final CTA means "dismiss AND open Fridge Setup," and
//  only the app shell knows how to do the latter.
//

import SwiftUI

struct OnboardingView: View {
    /// `openSetup`: true only from the page-3 CTA. CellarApp decides what
    /// that means (it opens FridgeSetupView); this view never navigates
    /// itself.
    var onFinished: (_ openSetup: Bool) -> Void

    /// Debug-only entry point for `-onboardingPage N` (simctl can't swipe a
    /// TabView, so screenshotting page 2 or 3 needs a way to land there
    /// directly).
    var initialPage: Int = 0

    @AppStorage("Cellar.hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var page: Int

    init(onFinished: @escaping (Bool) -> Void, initialPage: Int = 0) {
        self.onFinished = onFinished
        self.initialPage = initialPage
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        ZStack {
            CellarPalette.glassBlackDeep.ignoresSafeArea()

            TabView(selection: $page) {
                OnboardingPageCatalog()
                    .tag(0)
                OnboardingPageViewfinder()
                    .tag(1)
                OnboardingPageShelf(onSetUpFridge: { finish(openSetup: true) })
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    if page < 2 {
                        Button("Skip") { finish(openSetup: false) }
                            .wineListType(size: 13, weight: .semibold)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                pageDots
                    .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == page ? CellarPalette.ledGlow : Color.white.opacity(0.22))
                    .frame(width: i == page ? 18 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.25), value: page)
    }

    private func finish(openSetup: Bool) {
        hasSeenOnboarding = true
        onFinished(openSetup)
    }
}

// MARK: - Shared type helpers

/// Onboarding-specific text roles. `wineListType`/`cellarLabelType` are tuned
/// for compact in-UI text; a full-bleed onboarding page needs its own scale,
/// built from the same font (SF Pro, the system default) and the same
/// restrained tone rather than editing those shared helpers for one screen.
extension View {
    func onboardingTitle() -> some View {
        self
            .font(.system(size: 26, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(.white.opacity(0.95))
            .multilineTextAlignment(.center)
    }

    func onboardingSubline() -> some View {
        self
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
    }
}

#Preview {
    OnboardingView(onFinished: { _ in })
}
