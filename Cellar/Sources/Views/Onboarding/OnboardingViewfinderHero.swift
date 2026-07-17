//
//  OnboardingViewfinderHero.swift
//  Cellar — Views/Onboarding — Page 2: "Point. Don't type."
//
//  Hero is a SwiftUI-drawn viewfinder (thin corner brackets, no camera feed —
//  there's nothing to preview here) around a placeholder label card that
//  snaps once from "unrecognized" to "recognized": a ledGlow ring appears
//  plus a small readinessReady checkmark badge. That one-way snap is the
//  whole point — recognition happens once, in the background, and you don't
//  sit and watch it happen more than once either.
//

import SwiftUI

struct OnboardingPageViewfinder: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            OnboardingViewfinderHero()
                .frame(height: 220)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Text("Point. Don't type.")
                    .onboardingTitle()
                Text("Recognition runs in the background — you never wait on it.")
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

struct OnboardingViewfinderHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recognized = false

    var body: some View {
        ZStack {
            labelCard
            ViewfinderBrackets(cornerLength: 22)
                .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 232, height: 172)
        }
        .onAppear { snap() }
    }

    private var labelCard: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [CellarPalette.foilBlackLight.opacity(0.55), CellarPalette.glassBlack],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .topLeading) {
                // Placeholder label typography — plain shapes standing in for
                // text lines, never an actual illustration of a real label.
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(Color.white.opacity(0.4)).frame(width: 92, height: 8)
                    Capsule().fill(Color.white.opacity(0.2)).frame(width: 132, height: 6)
                    Capsule().fill(Color.white.opacity(0.2)).frame(width: 70, height: 6)
                }
                .padding(20)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(recognized ? CellarPalette.ledGlow : Color.white.opacity(0.1), lineWidth: recognized ? 2 : 1)
            }
            .overlay(alignment: .bottomTrailing) {
                if recognized {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(CellarPalette.readinessReady)
                        .background(Circle().fill(CellarPalette.glassBlackDeep))
                        .offset(x: 8, y: 8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: recognized ? CellarPalette.ledGlow.opacity(0.3) : .clear, radius: 16)
            .frame(width: 190, height: 130)
    }

    private func snap() {
        if reduceMotion {
            recognized = true
        } else {
            withAnimation(.easeOut(duration: 0.5).delay(0.9)) {
                recognized = true
            }
        }
    }
}

/// Thin corner brackets, drawn — never a raster camera-UI asset.
private struct ViewfinderBrackets: Shape {
    var cornerLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = cornerLength

        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))

        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))

        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))

        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))

        return p
    }
}

#Preview {
    OnboardingPageViewfinder()
        .background(CellarPalette.glassBlackDeep)
}
