//
//  BulkAddFlowView.swift
//  Cellar — Views/Add
//
//  Coordinator for PRD §6.3 load day: continuous capture, then one batch
//  slotting screen. Tracks only which bottles were captured THIS session
//  (so the slotting grid shows a coherent batch) — it owns no other state;
//  every bottle it hands off already exists and is already saved.
//

import SwiftUI

struct BulkAddFlowView: View {
    var onFinished: () -> Void
    let recognitionQueue: RecognitionQueue

    private enum Phase {
        case capture
        case slotting
    }
    @State private var phase: Phase = .capture
    @State private var sessionBottles: [Bottle] = []

    var body: some View {
        switch phase {
        case .capture:
            BulkCaptureView(
                onCapture: { bottle in sessionBottles.append(bottle) },
                onDone: { phase = .slotting },
                onQuit: onFinished,
                recognitionQueue: recognitionQueue
            )
        case .slotting:
            BulkSlottingView(bottles: sessionBottles, onFinished: onFinished)
        }
    }
}
