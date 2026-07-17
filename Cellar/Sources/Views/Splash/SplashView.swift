//
//  SplashView.swift
//  Cellar — Views/Splash
//
//  The ONE branded beat on a cold launch, shown once over the map while it
//  loads (CellarApp decides when — this view has no idea it's "cold launch
//  only," it just runs its sequence once and calls back). No progress bar,
//  no bouncing logo — PRD tone words apply here too: warm, dim, expensive,
//  quiet. ~1.2s hold, 0.4s fade, done.
//
//  Reduce Motion: skip the shimmer sweep and the dot's breathe animation —
//  both are pure decoration. The exit fade stays (a crossfade, not motion).
//

import SwiftUI

struct SplashView: View {
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appear = false
    @State private var shimmerX: CGFloat = 0
    @State private var dotScale: CGFloat = 1
    @State private var dotOpacity: Double = 0.6
    @State private var overlayOpacity: Double = 1

    var body: some View {
        ZStack {
            CellarPalette.glassBlackDeep.ignoresSafeArea()

            VStack(spacing: 26) {
                foilTitle
                breathingDot
            }
            .opacity(appear ? 1 : 0)
        }
        .opacity(overlayOpacity)
        .task { await runIntro() }
    }

    // MARK: - Title

    /// Same face as `cellarLabelType` but lighter and much wider than the
    /// helper's default — that default is tuned for small in-UI section
    /// labels, not a hero wordmark. At this scale the engraved-label read
    /// comes from air between glyphs, not weight. The leading padding
    /// balances the phantom space `.tracking` appends after the final glyph,
    /// which would otherwise pull the wordmark off optical center.
    private static let titleTracking: CGFloat = 15

    private var titleText: some View {
        Text("CELLAR")
            .cellarLabelType(size: 38, weight: .medium)
            .tracking(Self.titleTracking)
            .padding(.leading, Self.titleTracking)
    }

    private var foilTitle: some View {
        titleText
            .foregroundStyle(
                LinearGradient(
                    colors: [CellarPalette.foilGoldLight, CellarPalette.foilGoldDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if !reduceMotion {
                    shimmerSweep.mask(titleText)
                }
            }
    }

    /// A soft diagonal highlight sweeping once across the foil text — masked
    /// to the text's own shape so it reads as light catching foil, not a
    /// generic loading shimmer.
    private var shimmerSweep: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, .white.opacity(0.65), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .rotationEffect(.degrees(20))
            .frame(width: geo.size.width * 0.5)
            .offset(x: shimmerX * geo.size.width * 1.8 - geo.size.width * 0.4)
        }
    }

    // MARK: - Dot

    /// Styled like a FoilCapsule's warm glow, not the component itself — this
    /// isn't a bottle, it's the "system is alive" beat, so it stays a plain
    /// glowing dot rather than borrowing bottle-specific readiness states.
    private var breathingDot: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [CellarPalette.ledGlow, CellarPalette.ledGlow.opacity(0.3)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 9
                )
            )
            .frame(width: 10, height: 10)
            .shadow(color: CellarPalette.ledGlow.opacity(0.7), radius: 6)
            .scaleEffect(dotScale)
            .opacity(dotOpacity)
    }

    // MARK: - Sequence

    private func runIntro() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) {
                appear = true
                dotOpacity = 1
            }
        } else {
            withAnimation(.easeOut(duration: 0.5)) { appear = true }
            withAnimation(.easeInOut(duration: 0.9).delay(0.15)) { shimmerX = 1 }
            withAnimation(.easeInOut(duration: 0.45).delay(0.2)) {
                dotScale = 1.3
                dotOpacity = 1
            }
            withAnimation(.easeInOut(duration: 0.45).delay(0.65)) {
                dotScale = 1.0
                dotOpacity = 0.75
            }
        }

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        withAnimation(.easeOut(duration: 0.4)) { overlayOpacity = 0 }
        try? await Task.sleep(nanoseconds: 400_000_000)
        onFinished()
    }
}

#Preview {
    SplashView()
}
