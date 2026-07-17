//
//  CameraController.swift
//  Cellar — Views/Add
//
//  Thin AVFoundation wrapper. PRD §6.2: "Bottle in hand, label to lens — the
//  only condition recognition ever runs in." This owns the capture session
//  and turns a shutter press into JPEG `Data`, nothing more — it does not
//  create a Bottle, does not touch SwiftData, and does not know about
//  RecognitionQueue. AddFlowView / CameraCaptureCore own what happens to the
//  bytes once captured.
//
//  Not gated behind `#if targetEnvironment(simulator)` — this class compiles
//  and runs on the simulator too (harmlessly: no camera device is found, so
//  the session simply has no input). That's deliberate: it means a Simulator
//  build actually exercises this file's compile-and-basic-runtime path
//  instead of skipping it entirely. Only the FAKE capture path
//  (FakeCameraSupport) is compile-gated to the simulator; this file is the
//  real one and stays real everywhere.
//

import AVFoundation
import Foundation

@MainActor
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private var hasConfiguredInput = false
    private var captureCompletion: ((Data?) -> Void)?

    override init() {
        super.init()
        configureSessionIfNeeded()
    }

    /// Idempotent — safe to call from `onAppear` every time the camera
    /// screen reappears (e.g. returning from the slot picker for the next
    /// bottle, PRD §6.2 step 4).
    func start() {
        guard !session.isRunning else { return }
        let session = self.session
        Task.detached(priority: .userInitiated) {
            session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        let session = self.session
        Task.detached(priority: .userInitiated) {
            session.stopRunning()
        }
    }

    /// Captures one photo and hands back JPEG-ish `Data`, or `nil` if no
    /// camera is configured (e.g. simulator without `-fakeCamera`, or camera
    /// access was denied) — the caller (CameraCaptureCore) simply drops a
    /// `nil` capture rather than creating a bottle with no photo.
    func capturePhoto(completion: @escaping (Data?) -> Void) {
        guard hasConfiguredInput, session.isRunning else {
            completion(nil)
            return
        }
        captureCompletion = completion
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    private func configureSessionIfNeeded() {
        // CameraCaptureCore always constructs a CameraController (it's a
        // @StateObject, initialized unconditionally regardless of which
        // branch `body` takes), even when `-fakeCamera` means this session
        // will never be used. Without this guard, the simulator would still
        // pop the real system camera-permission dialog under `-fakeCamera`
        // — which `simctl` cannot dismiss, stalling any automated/headless
        // run. `FakeCameraSupport.isActive` is itself simulator+launch-arg
        // gated, so this guard is a no-op on every real device.
        guard !FakeCameraSupport.isActive else { return }

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            Task { @MainActor in
                self?.configureSession()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            return // no camera hardware (simulator) — session stays inputless, capturePhoto no-ops
        }
        session.addInput(input)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        hasConfiguredInput = true
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        Task { @MainActor in
            self.captureCompletion?(data)
            self.captureCompletion = nil
        }
    }
}
