//
//  ShelfEditorRow.swift
//  Cellar — Views/Setup
//
//  One shelf's controls: slot count and style (.display vs .storage — PRD
//  §6.12). Writes straight to the SwiftData `Shelf` model it's handed; Shelf
//  CRUD isn't gated behind CellarStore (only Bottle placement is — see
//  Bottle.swift's `_unsafeRelocate` comment), so this is a legitimate direct
//  write.
//

import SwiftUI

struct ShelfEditorRow: View {
    @Bindable var shelf: Shelf
    let position: Int
    let onDelete: () -> Void

    private let slotRange = 1...24

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Shelf \(position + 1)")
                    .cellarLabelType(size: 12)
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Slots")
                        .cellarLabelType(size: 10)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("\(shelf.slotCount)")
                        .wineListType(size: 20, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.92))
                }

                Stepper("", value: $shelf.slotCount, in: slotRange)
                    .labelsHidden()
                    .tint(CellarPalette.ledGlow)

                Spacer()

                Picker("Style", selection: $shelf.style) {
                    Text("Storage").tag(ShelfStyle.storage)
                    Text("Display").tag(ShelfStyle.display)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
