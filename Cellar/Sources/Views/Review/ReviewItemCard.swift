//
//  ReviewItemCard.swift
//  Cellar — Views/Review
//
//  Tier 1 of PRD §6.4: "Accept. Photo + best guess + confidence. Right? One
//  tap." That's this card's primary action. "Not this" pushes into tiers 2
//  and 3 (ReviewItemDetailView) for the cases where the top guess is wrong.
//

import SwiftUI
import SwiftData
import UIKit

struct ReviewItemCard: View {
    let item: ReviewItem
    let recognitionQueue: RecognitionQueue

    @Environment(\.modelContext) private var context

    private var bestGuess: WineCandidate? { item.candidates.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    if let bestGuess {
                        Text(bestGuess.producer)
                            .cellarLabelType(size: 10)
                            .foregroundStyle(.white.opacity(0.45))
                        Text(title(for: bestGuess))
                            .wineListType(size: 15, weight: .semibold)
                            .foregroundStyle(.white.opacity(0.95))
                        Text(confidenceText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    } else {
                        Text("No guess yet")
                            .wineListType(size: 15, weight: .semibold)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                if let bestGuess {
                    Button(action: { accept(bestGuess) }) {
                        Text("Accept")
                            .wineListType(size: 13, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(CellarPalette.ledGlow.opacity(0.9)))
                            .foregroundStyle(CellarPalette.glassBlackDeep)
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    ReviewItemDetailView(item: item, recognitionQueue: recognitionQueue)
                } label: {
                    Text(bestGuess != nil ? "Not this" : "Review")
                        .wineListType(size: 13, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(.white.opacity(0.85))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var thumbnail: some View {
        Group {
            if let uiImage = UIImage(data: item.photo) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                FoilCapsule(content: .unresolved, diameter: 40)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func title(for candidate: WineCandidate) -> String {
        if let vintage = candidate.vintage {
            "\(candidate.name) \(String(vintage))"
        } else {
            candidate.name
        }
    }

    private var confidenceText: String {
        "\(Int((item.confidence * 100).rounded()))% confidence"
    }

    private func accept(_ candidate: WineCandidate) {
        ReviewResolution.accept(candidate: candidate, for: item, in: context)
    }
}
