//
//  CameraCaptureCore.swift
//  Cellar — Views/Add
//
//  The shared shutter + preview surface behind both the single-bottle add
//  flow (CameraCaptureView) and bulk mode (BulkCaptureView) — PRD §6.2 step 1
//  and §6.3 "scan -> scan -> scan" are the same camera, just wrapped by
//  different chrome (a coach mark vs. a running count). This view owns
//  NOTHING about bottles, SwiftData, or recognition — it only turns a tap
//  into `Data` and hands it to `onCapture`. THE RULE: `onCapture` must not be
//  awaited or gated on anything network-shaped; it fires the instant local
//  bytes exist, real or fake.
//

import SwiftUI

struct CameraCaptureCore<Overlay: View>: View {
    let onCapture: (Data) -> Void
    /// When true (only ever true under `-fakeCamera` + `-autoAddForTest`,
    /// see FakeCameraSupport), fires one capture automatically on first
    /// appearance — `simctl` cannot tap a shutter button, so the
    /// never-block-the-network proof (see AddFlowView) needs a way to
    /// trigger a capture with no human involved.
    var autoCaptureOnAppear: Bool = false
    @ViewBuilder var overlay: () -> Overlay

    @StateObject private var controller = CameraController()
    @State private var hasAutoCaptured = false

    var body: some View {
        ZStack {
            CellarPalette.glassBlackDeep.ignoresSafeArea()

            if FakeCameraSupport.isActive {
                fakePreview
            } else {
                CameraPreviewView(session: controller.session)
                    .ignoresSafeArea()
            }

            overlay()

            VStack {
                Spacer()
                shutterButton
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            if !FakeCameraSupport.isActive { controller.start() }
            if autoCaptureOnAppear, !hasAutoCaptured {
                hasAutoCaptured = true
                capture()
            }
        }
        .onDisappear {
            if !FakeCameraSupport.isActive { controller.stop() }
        }
    }

    // MARK: - Fake preview (simulator only, `-fakeCamera`)

    private var fakePreview: some View {
        ZStack {
            LinearGradient(
                colors: [CellarPalette.glassBlack, CellarPalette.glassBlackDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(.white.opacity(0.18))
                Text("Simulator · fake camera")
                    .cellarLabelType(size: 10)
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Shutter

    private var shutterButton: some View {
        Button(action: capture) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(Color.white)
                    .frame(width: 62, height: 62)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shutter")
        // Deliberately no `.disabled(...)` tied to any network/in-flight
        // state — the shutter is ALWAYS live (PRD: "never disable the
        // shutter while a request is in flight").
    }

    private func capture() {
        if FakeCameraSupport.isActive {
            onCapture(FakeCameraSupport.sampleBottlePhotoData())
        } else {
            controller.capturePhoto { data in
                guard let data else { return }
                onCapture(data)
            }
        }
    }
}
