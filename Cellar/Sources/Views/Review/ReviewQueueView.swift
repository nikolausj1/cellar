//
//  ReviewQueueView.swift
//  Cellar — Views/Review
//
//  PRD §6.4: "The single place decisions happen." Lists every ReviewItem
//  still awaiting a decision, newest first. Empty state reads as calm, not
//  as an achievement (PRD: "the NORMAL state").
//
//  DEDUPE NOTE: RecognitionQueue.apply (Services, off-limits to edit) always
//  inserts a NEW ReviewItem on low confidence — it has no way to know about
//  an existing one for the same bottle (e.g. after a hint re-query). Rather
//  than showing two cards for one bottle, `visibleItems` below keeps only
//  the most recent item per bottle and hides any item whose bottle already
//  resolved (bottle.wine != nil) — resolved elsewhere, effectively done,
//  even though the row itself isn't deleted. This is read-only filtering;
//  nothing here mutates ReviewItem rows to achieve it.
//

import SwiftUI
import SwiftData

struct ReviewQueueView: View {
    @Query(sort: \ReviewItem.createdAt, order: .reverse) private var items: [ReviewItem]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let recognitionQueue: RecognitionQueue

    private var visibleItems: [ReviewItem] {
        let unresolved = items.filter { $0.bottle == nil || $0.bottle?.wine == nil }

        var latestByBottle: [PersistentIdentifier: ReviewItem] = [:]
        var standalone: [ReviewItem] = []
        for item in unresolved {
            if let bottle = item.bottle {
                let key = bottle.persistentModelID
                if let existing = latestByBottle[key], existing.createdAt >= item.createdAt {
                    continue
                }
                latestByBottle[key] = item
            } else {
                standalone.append(item)
            }
        }
        return (Array(latestByBottle.values) + standalone).sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ZStack {
            CellarPalette.glassBlackDeep.ignoresSafeArea()

            if visibleItems.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CellarPalette.glassBlack, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(CellarPalette.ledGlow)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(.white.opacity(0.22))
            Text("Nothing to review.")
                .wineListType(size: 16, weight: .medium)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(visibleItems, id: \.id) { item in
                    ReviewItemCard(item: item, recognitionQueue: recognitionQueue)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }
}
