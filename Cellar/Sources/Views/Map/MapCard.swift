//
//  MapCard.swift
//  Cellar — Views/Map
//
//  PRD §6.1: "Cards surface above the map when something needs him... N
//  bottles need review... Tell me about last night's Ornellaia. Non-blocking,
//  dismissible." Never a sheet, never a modal — just a card the map scrolls
//  past if he ignores it.
//

import SwiftUI

struct MapCard: View {
    let icon: String
    let text: String
    let action: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(CellarPalette.ledGlow)
                .font(.system(size: 15, weight: .medium))

            Text(text)
                .wineListType(size: 14, weight: .medium)
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: action)
    }
}
