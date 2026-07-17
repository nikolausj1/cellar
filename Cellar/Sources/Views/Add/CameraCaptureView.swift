//
//  CameraCaptureView.swift
//  Cellar — Views/Add
//
//  PRD §6.2 step 1-2: camera opens, bottle in hand, label to lens. Shutter →
//  photo captured locally. This view's only output is `onCapture: (Data) ->
//  Void` — it does not create a Bottle or touch SwiftData; AddFlowView does
//  that the instant this fires, per THE RULE (never await the network).
//

import SwiftUI

struct CameraCaptureView: View {
    let onCapture: (Data) -> Void
    let onClose: () -> Void
    var autoCaptureOnAppear: Bool = false

    /// PRD §6.2: "First-run coach: one line... Once, not forever."
    @AppStorage("Cellar.hasSeenCameraCoach") private var hasSeenCoach = false

    var body: some View {
        CameraCaptureCore(onCapture: handleCapture, autoCaptureOnAppear: autoCaptureOnAppear) {
            VStack {
                topBar
                if !hasSeenCoach {
                    coachMark
                        .padding(.top, 8)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var coachMark: some View {
        Text("Hold the bottle so the label faces the camera.")
            .wineListType(size: 13, weight: .medium)
            .foregroundStyle(.white.opacity(0.9))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Color.black.opacity(0.4))
            )
            .padding(.horizontal, 36)
    }

    private func handleCapture(_ data: Data) {
        hasSeenCoach = true
        onCapture(data)
    }
}
