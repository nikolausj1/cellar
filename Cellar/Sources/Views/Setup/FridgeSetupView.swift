//
//  FridgeSetupView.swift
//  Cellar — Views/Setup
//
//  PRD §6.12: define shelves, slots per shelf, and shelf style — runtime
//  configurable, persisted, editable after first run. PRD §12 open question 1:
//  the real fridge geometry is UNKNOWN (model number hasn't landed). This ships
//  working and genuinely empty — no hardcoded shelf count, no seeded fake data.
//  Justin enters reality later, and can come back and change it any time.
//
//  Shelf CRUD writes straight through SwiftData — Shelf isn't gated behind
//  CellarStore the way Bottle placement is (see Bottle.swift), so this view
//  owns its own persistence with no other worker's code in the loop.
//

import SwiftUI
import SwiftData

struct FridgeSetupView: View {
    @Query(sort: \Shelf.index) private var shelves: [Shelf]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CellarPalette.glassBlackDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                if shelves.isEmpty {
                    Spacer(minLength: 0)
                    emptyState
                    Spacer(minLength: 0)
                } else {
                    list
                }

                ScanStationSettingsView()
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
            }
        }
        .navigationTitle("Fridge Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CellarPalette.glassBlack, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: addShelf) {
                    Image(systemName: "plus")
                }
            }
            if !shelves.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.25))

            VStack(spacing: 6) {
                Text("No shelves yet")
                    .wineListType(size: 17, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Add a shelf for each rack in your fridge, top to bottom.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: addShelf) {
                Label("Add a shelf", systemImage: "plus")
                    .wineListType(size: 15, weight: .semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(CellarPalette.ledGlow.opacity(0.9)))
                    .foregroundStyle(CellarPalette.glassBlackDeep)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            Section {
                ForEach(Array(shelves.enumerated()), id: \.element.persistentModelID) { position, shelf in
                    ShelfEditorRow(shelf: shelf, position: position, onDelete: { delete(shelf) })
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .onMove(perform: move)
                .onDelete(perform: deleteAtOffsets)
            } footer: {
                Text("Shelves are numbered top to bottom, matching what you see with the door open.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 4)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    // MARK: - Mutations

    private func addShelf() {
        let shelf = Shelf(index: shelves.count, slotCount: 6, style: .storage)
        context.insert(shelf)
        save()
    }

    private func delete(_ shelf: Shelf) {
        context.delete(shelf)
        reindexSequentially(excluding: shelf)
    }

    private func deleteAtOffsets(_ offsets: IndexSet) {
        let toDelete = offsets.map { shelves[$0] }
        for shelf in toDelete { context.delete(shelf) }
        reindexSequentially(excluding: nil, removed: Set(toDelete.map(\.persistentModelID)))
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = shelves
        ordered.move(fromOffsets: source, toOffset: destination)
        assignIndices(ordered)
        save()
    }

    /// Reindexes the surviving shelves to a contiguous 0..<n sequence after a
    /// deletion, preserving their current top-to-bottom order.
    private func reindexSequentially(excluding removedShelf: Shelf?, removed: Set<PersistentIdentifier> = []) {
        var removedIDs = removed
        if let removedShelf { removedIDs.insert(removedShelf.persistentModelID) }
        let ordered = shelves.filter { !removedIDs.contains($0.persistentModelID) }
        assignIndices(ordered)
        save()
    }

    /// Assigns 0..<n sequentially in list order. Bumps everything to a
    /// temporary, guaranteed-unused range first so no in-place reassignment
    /// ever collides with another shelf's still-current index (`index` is
    /// `@Attribute(.unique)`).
    private func assignIndices(_ ordered: [Shelf]) {
        for (offset, shelf) in ordered.enumerated() {
            shelf.index = 100_000 + offset
        }
        for (offset, shelf) in ordered.enumerated() {
            shelf.index = offset
        }
    }

    private func save() {
        try? context.save()
    }
}

#Preview {
    NavigationStack {
        FridgeSetupView()
    }
    .modelContainer(for: [Wine.self, Bottle.self, Shelf.self, DrinkEvent.self, Memory.self, ReviewItem.self], inMemory: true)
}
