//
//  FakeCameraSupport.swift
//  Cellar — Views/Add
//
//  Camera work needs a real device — the simulator has no camera hardware.
//  This is the ONE gate that lets `-fakeCamera` feed a bundled/generated
//  sample "label photo" into the exact same capture -> Bottle -> submit path
//  a real shutter tap uses, so the add flow stays screenshot-verifiable on
//  the sim.
//
//  THE GATE: `isActive` is wrapped in `#if targetEnvironment(simulator)`, not
//  just a runtime launch-arg check. On a device build that branch of the
//  `#if` doesn't exist in the compiled binary at all — passing `-fakeCamera`
//  to a real install is structurally inert, not just unlikely. This mirrors
//  DemoSeed's "structurally incapable of touching the real store" pattern
//  from Views/Map, applied to hardware instead of data.
//
//  Placeholder-first (Build Guide / PRD §7): the sample "label" is rendered
//  programmatically via SwiftUI + ImageRenderer, not a bundled binary image
//  asset — there is nothing in this file that isn't code.
//

import Foundation
import SwiftUI

enum FakeCameraSupport {
    /// True only on the simulator AND only when `-fakeCamera` is passed.
    /// Real device builds never even compile the `true` branch.
    static var isActive: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-fakeCamera")
        #else
        false
        #endif
    }

    /// A second, narrower gate for the non-blocking-proof harness (see
    /// AddFlowView): auto-fires the shutter without a tap, since `simctl`
    /// cannot tap. Requires `isActive` itself, so it inherits the same
    /// simulator-only compile-time gate — this can never fire on device
    /// even if both launch args were somehow passed.
    static var autoCaptureRequested: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("-autoAddForTest")
    }

    /// Renders a small placeholder "label" — enough visual variety that a
    /// screenshot doesn't look like a blank rectangle — to JPEG data, the
    /// same shape a real `AVCapturePhotoOutput` capture would hand back.
    @MainActor
    static func sampleBottlePhotoData() -> Data {
        let renderer = ImageRenderer(content: SampleLabelArt())
        renderer.scale = 2
        guard let uiImage = renderer.uiImage, let data = uiImage.jpegData(compressionQuality: 0.85) else {
            return Data([0xFF, 0xD8, 0xFF, 0xD9]) // minimal valid-looking JPEG stub, never actually decoded by the app
        }
        return data
    }
}

/// A tiny generated "wine label" — just enough to not be a blank frame in a
/// screenshot. Never shown to Justin as real product UI; it only ever stands
/// in for a photograph.
private struct SampleLabelArt: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [CellarPalette.foilBurgundyLight, CellarPalette.foilBurgundyDark],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 10) {
                Text("SIMULATOR")
                    .cellarLabelType(size: 11)
                    .foregroundStyle(.white.opacity(0.6))
                Text("Fake Bottle")
                    .wineListType(size: 22, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.95))
                Text("Sample Label")
                    .cellarLabelType(size: 10)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 360, height: 480)
    }
}
