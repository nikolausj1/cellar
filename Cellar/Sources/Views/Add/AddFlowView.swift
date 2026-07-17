//
//  AddFlowView.swift
//  Cellar — Views/Add
//
//  The single-bottle add flow coordinator — PRD §6.2, and THE RULE that
//  outranks everything in this package: capture -> Bottle(wine: nil) ->
//  submit (fire-and-forget) -> slot picker -> next bottle. Nothing in this
//  file ever awaits RecognitionQueue.submit — it isn't `async`, so there is
//  nothing TO await, which is the whole point.
//
//  `preTargetedSlot` implements PRD §6.1: "Tap an empty slot -> Add flow,
//  pre-targeted to that slot." Rather than showing the picker and asking the
//  user to tap the same slot they just tapped on the map, capture goes
//  straight to that address and the flow returns to the map — the picker
//  only appears as a fallback if that exact slot got taken out from under it
//  (e.g. another bottle placed there moments earlier).
//

import SwiftUI
import SwiftData

struct AddFlowView: View {
    /// Set when entered via a tap on an empty slot on the map (PRD §6.1).
    /// Nil for the normal camera-button entry, where the picker always shows.
    var preTargetedSlot: SlotAddress? = nil
    /// Called once this bottle (or the whole session, for the camera-button
    /// entry) is done and the flow should return to the map.
    var onFinished: () -> Void
    /// Offered only from the general camera-button entry (nil when
    /// pre-targeted — that entry is a single specific action, not a
    /// load-day session). Switches the presenting screen into bulk mode.
    var onEnterBulkMode: (() -> Void)? = nil

    let recognitionQueue: RecognitionQueue

    @Environment(\.modelContext) private var context
    @Query(sort: \Shelf.index) private var shelves: [Shelf]

    private enum Phase {
        case camera
        case slotPicker(Bottle)
    }
    @State private var phase: Phase = .camera

    private var layout: FridgeLayout { FridgeLayout(shelves: shelves.map(\.layout)) }

    var body: some View {
        switch phase {
        case .camera:
            CameraCaptureView(
                onCapture: handleCapture,
                onClose: onFinished,
                autoCaptureOnAppear: FakeCameraSupport.autoCaptureRequested
            )
            .overlay(alignment: .bottomLeading) {
                if let onEnterBulkMode, preTargetedSlot == nil {
                    loadDayButton(action: onEnterBulkMode)
                }
            }
        case let .slotPicker(bottle):
            SlotPickerView(bottle: bottle, onPlaced: { phase = .camera })
        }
    }

    // MARK: - Capture -> create -> submit -> place (THE RULE lives here)

    private func handleCapture(_ photoData: Data) {
        // 1. Bottle created locally, `wine == nil`. Nothing here has touched
        //    the network yet, and nothing below blocks on anything that will.
        let bottle = Bottle(wine: nil, location: .boxes, labelPhoto: photoData, addedAt: .now, status: .present)
        context.insert(bottle)
        try? context.save()

        // 2. Fire-and-forget. `submit` is `nonisolated` and NOT `async` —
        //    there is nothing to await here even by mistake.
        recognitionQueue.submit(bottleID: bottle.id, photo: photoData, hint: nil)

        // 3. Slot picker, pre-targeted if we know where this one goes.
        if let preTargetedSlot {
            let store = CellarStore(context: context)
            if (try? store.place(bottle, at: preTargetedSlot, layout: layout)) != nil {
                onFinished()
                return
            }
            // Backstop, not the expected path: the pre-targeted slot was
            // taken between the map tap and this capture. Fall through to
            // the normal picker rather than stranding the bottle.
        }
        phase = .slotPicker(bottle)
    }

    private func loadDayButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Load day", systemImage: "square.stack.3d.up")
                .wineListType(size: 13, weight: .semibold)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.42)))
                .foregroundStyle(.white.opacity(0.88))
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.bottom, 130)
    }
}
