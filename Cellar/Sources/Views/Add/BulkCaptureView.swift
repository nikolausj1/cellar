//
//  BulkCaptureView.swift
//  Cellar — Views/Add
//
//  PRD §6.3 load day: "Scan -> scan -> scan, continuously. No slot prompt, no
//  confirm, no 'done' tap between bottles. ... Running count on screen.
//  Nothing else." Every capture creates a Bottle in `.boxes` (the same THE
//  RULE as the single flow: local, instant, fire-and-forget recognition) and
//  stays on this screen — slot assignment is a separate screen entirely
//  (BulkSlottingView), reached only via the explicit "Done" tap.
//
//  "Quitting mid-session must lose nothing": every bottle is inserted and
//  saved into SwiftData the instant it's captured, already sitting in
//  `.boxes`. Backing out via the X needs no cleanup step to satisfy that —
//  there is no staging area this could lose data from.
//

import SwiftUI
import SwiftData

struct BulkCaptureView: View {
    /// Fires once per capture with the newly created bottle, so the
    /// coordinator (BulkAddFlowView) can hand the whole session's bottles to
    /// the slotting screen afterward.
    let onCapture: (Bottle) -> Void
    /// "Done" — ends the session and moves to slot assignment.
    let onDone: () -> Void
    /// Quit mid-session straight back to the map. Structurally identical to
    /// "Done" in terms of data safety (see file header) — offered
    /// separately only because going straight to the map, skipping the
    /// slotting screen, is a legitimate choice too.
    let onQuit: () -> Void
    let recognitionQueue: RecognitionQueue

    @Environment(\.modelContext) private var context
    @State private var capturedCount = 0

    var body: some View {
        CameraCaptureCore(onCapture: handleCapture) {
            VStack {
                topBar
                Spacer()
                countBadge
                    .padding(.bottom, 148)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button(action: onQuit) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quit load day")

            Spacer()

            Button(action: onDone) {
                Text("Done")
                    .wineListType(size: 14, weight: .semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(CellarPalette.ledGlow.opacity(0.92)))
                    .foregroundStyle(CellarPalette.glassBlackDeep)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var countBadge: some View {
        VStack(spacing: 2) {
            Text("\(capturedCount)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
            Text(capturedCount == 1 ? "bottle scanned" : "bottles scanned")
                .cellarLabelType(size: 11)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 28)
        .background(Capsule().fill(Color.black.opacity(0.35)))
    }

    private func handleCapture(_ photoData: Data) {
        let bottle = Bottle(wine: nil, location: .boxes, labelPhoto: photoData, addedAt: .now, status: .present)
        context.insert(bottle)
        try? context.save()

        // Fire-and-forget, identical contract to the single flow.
        recognitionQueue.submit(bottleID: bottle.id, photo: photoData, hint: nil)

        capturedCount += 1
        onCapture(bottle)
    }
}
