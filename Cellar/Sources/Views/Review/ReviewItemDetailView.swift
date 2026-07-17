//
//  ReviewItemDetailView.swift
//  Cellar — Views/Review
//
//  Tiers 2 and 3 of PRD §6.4:
//    2. Pick alternate — the model's next 2-3 candidates. Tap one.
//    3. Type a hint — one word, re-query, pick from the narrowed set.
//
//  The hint re-query goes through `RecognitionQueue.submit(bottleID:photo:
//  hint:)` — the SAME fire-and-forget entry point the shutter uses. Nothing
//  here awaits it. PRD: "if a re-query fails, the item stays queued. Items
//  are never dropped" — so submitting a hint does NOT delete this item; it
//  stays visible (ReviewQueueView's dedupe keeps only the newest per
//  bottle) until either a fresh low-confidence ReviewItem supersedes it or
//  the bottle resolves outright and disappears from the queue.
//

import SwiftUI
import SwiftData
import UIKit

struct ReviewItemDetailView: View {
    let item: ReviewItem
    let recognitionQueue: RecognitionQueue

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var hintText: String = ""
    @State private var hintSubmitted = false

    private var trimmedHint: String { hintText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            CellarPalette.glassBlackDeep.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    thumbnail

                    if !item.candidates.isEmpty {
                        candidatesSection
                    }

                    if item.bottle != nil {
                        hintSection
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CellarPalette.glassBlack, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    // MARK: - Photo

    private var thumbnail: some View {
        Group {
            if let uiImage = UIImage(data: item.photo) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                FoilCapsule(content: .unresolved, diameter: 60)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Tier 2: pick alternate

    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick the right one")
                .cellarLabelType(size: 11)
                .foregroundStyle(.white.opacity(0.45))

            ForEach(Array(item.candidates.enumerated()), id: \.offset) { _, candidate in
                Button {
                    accept(candidate)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.producer)
                                .cellarLabelType(size: 9)
                                .foregroundStyle(.white.opacity(0.4))
                            Text(title(for: candidate))
                                .wineListType(size: 14, weight: .medium)
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Tier 3: hint

    private var hintSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Still not it? Type a hint")
                .cellarLabelType(size: 11)
                .foregroundStyle(.white.opacity(0.45))

            HStack(spacing: 10) {
                TextField("Duck...", text: $hintText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    .foregroundStyle(.white.opacity(0.92))
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .onSubmit(submitHint)

                Button(action: submitHint) {
                    Text(hintSubmitted ? "Looking…" : "Search")
                        .wineListType(size: 13, weight: .semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(CellarPalette.ledGlow.opacity(trimmedHint.isEmpty ? 0.3 : 0.9)))
                        .foregroundStyle(CellarPalette.glassBlackDeep)
                }
                .buttonStyle(.plain)
                .disabled(trimmedHint.isEmpty)
            }

            if hintSubmitted {
                Text("Re-checking with your hint. This stays in the queue until it comes back.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Actions

    private func title(for candidate: WineCandidate) -> String {
        if let vintage = candidate.vintage {
            "\(candidate.name) \(String(vintage))"
        } else {
            candidate.name
        }
    }

    private func accept(_ candidate: WineCandidate) {
        ReviewResolution.accept(candidate: candidate, for: item, in: context)
        dismiss()
    }

    private func submitHint() {
        guard let bottle = item.bottle, !trimmedHint.isEmpty else { return }
        hintSubmitted = true
        // Fire-and-forget — same non-blocking contract as the shutter.
        // Deliberately does NOT delete `item`: a failed re-query must leave
        // it queued (PRD §6.4), and a successful one is superseded, not
        // erased, by whatever RecognitionQueue.apply does next.
        recognitionQueue.submit(bottleID: bottle.id, photo: item.photo, hint: trimmedHint)
        dismiss()
    }
}
