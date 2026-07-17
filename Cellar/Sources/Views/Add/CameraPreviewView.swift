//
//  CameraPreviewView.swift
//  Cellar — Views/Add
//
//  UIViewRepresentable wrapping AVCaptureVideoPreviewLayer. On a device this
//  is the live viewfinder; on the simulator (no camera hardware) it renders
//  as an empty black layer, which is fine — the simulator path always runs
//  under `-fakeCamera`, which never shows this view at all (see
//  CameraCaptureCore).
//

import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewUIView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
