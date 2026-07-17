//
//  FridgeMapView.swift
//  Cellar — Views/Map
//
//  PRD §6.1: the app opens HERE, not to a camera. Renders instantly from local
//  SwiftData — there is no network path to this screen, ever (PRD principle 2).
//  The Pi status dot and any enrichment/recognition state are read from data
//  that's already on disk; nothing here awaits a network call to draw a frame.
//
//  This view does not create, place, or delete bottles, and does not own
//  navigation to the add flow, review queue, or bottle detail screens — those
//  belong to other workers. It only calls the closures it's handed.
//

import SwiftUI
import SwiftData

enum MapArea: String, CaseIterable {
    case fridge = "Fridge"
    case boxes = "Boxes"
}

struct FridgeMapView: View {
    @Query(sort: \Shelf.index) private var shelves: [Shelf]
    @Query private var allBottles: [Bottle]
    @Query private var reviewItems: [ReviewItem]
    @Query(sort: \DrinkEvent.drankAt, order: .reverse) private var drinkEvents: [DrinkEvent]

    @State private var area: MapArea = .fridge
    @State private var dismissedCardKeys: Set<String> = []

    /// Navigation out — every one of these is owned by another worker's screen.
    /// This view's only job is to call the right one at the right time.
    var onSelectBottle: (Bottle) -> Void = { _ in }
    var onSelectEmptySlot: (SlotAddress) -> Void = { _ in }
    var onTapCamera: () -> Void = {}
    var onOpenSetup: () -> Void = {}
    var onTapReviewQueue: () -> Void = {}
    var onTapMemoryCard: (DrinkEvent) -> Void = { _ in }

    /// Read-only, used only for the non-blocking status dot. Defaults to a real
    /// PiClient reading whatever base URL (if any) is configured in Settings —
    /// with none configured, health() throws `.notConfigured` and the dot just
    /// shows muted, exactly per PRD ("the map does not depend on the Pi").
    var piClient: PiClientProtocol = PiClient(settings: PiClientSettings())

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    private var presentBottles: [Bottle] { allBottles.filter { $0.status == .present } }

    private var fridgeBottlesByAddress: [SlotAddress: Bottle] {
        var dict: [SlotAddress: Bottle] = [:]
        for bottle in presentBottles {
            if case let .fridge(shelfIndex, slot) = bottle.location {
                dict[SlotAddress(shelfIndex: shelfIndex, slot: slot)] = bottle
            }
        }
        return dict
    }

    private var boxesBottles: [Bottle] {
        presentBottles.filter { if case .boxes = $0.location { return true } else { return false } }
    }

    private var layoutShelves: [ShelfLayout] { shelves.map(\.layout) }

    private var isCellarEmpty: Bool { presentBottles.isEmpty }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CellarPalette.glassBlackDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                cards
                if area == .fridge, isCellarEmpty {
                    // Not scrollable — there's nothing to scroll to, and the
                    // empty cabinet should fill the screen, not float in a
                    // sliver at the top (PRD §6.1: "feel like an invitation").
                    mapContent
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                } else {
                    ScrollView {
                        mapContent
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 110)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            cameraButton
                .padding(.trailing, 22)
                .padding(.bottom, 28)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Cellar")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.95))

                PiStatusDot(client: piClient)

                Spacer()

                Button(action: onOpenSetup) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .accessibilityLabel("Fridge setup")
            }

            Picker("Location", selection: $area) {
                ForEach(MapArea.allCases, id: \.self) { area in
                    Text(area.rawValue).tag(area)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    // MARK: - Cards

    private var cards: some View {
        VStack(spacing: 8) {
            if reviewItems.count > 0, !dismissedCardKeys.contains("review") {
                MapCard(
                    icon: "tray.full",
                    text: reviewCardText,
                    action: onTapReviewQueue,
                    onDismiss: { dismissedCardKeys.insert("review") }
                )
            }

            if let event = memoryPromptEvent, !dismissedCardKeys.contains(memoryCardKey(for: event)) {
                MapCard(
                    icon: "text.bubble",
                    text: memoryCardText(for: event),
                    action: { onTapMemoryCard(event) },
                    onDismiss: { dismissedCardKeys.insert(memoryCardKey(for: event)) }
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, hasVisibleCards ? 10 : 0)
    }

    private var hasVisibleCards: Bool {
        (reviewItems.count > 0 && !dismissedCardKeys.contains("review"))
            || (memoryPromptEvent.map { !dismissedCardKeys.contains(memoryCardKey(for: $0)) } ?? false)
    }

    private var reviewCardText: String {
        let n = reviewItems.count
        return "\(n) bottle\(n == 1 ? "" : "s") need\(n == 1 ? "s" : "") review"
    }

    /// Rung 2 of the memory cascade (PRD §6.6): if the slot is still empty next
    /// time he opens the app, ask. Scoped to the last 3 days so this stays a
    /// gentle prompt, not a permanent reproach for something from months ago.
    private var memoryPromptEvent: DrinkEvent? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .distantPast
        return drinkEvents.first { event in
            event.drankAt >= cutoff && (event.memory == nil || event.memory?.isFilled == false)
        }
    }

    private func memoryCardKey(for event: DrinkEvent) -> String { "memory-\(event.id.uuidString)" }

    private func memoryCardText(for event: DrinkEvent) -> String {
        if let wine = event.wine {
            return "Tell me about \(wine.name)"
        }
        return "Tell me about last night's bottle"
    }

    // MARK: - Content

    @ViewBuilder
    private var mapContent: some View {
        switch area {
        case .fridge:
            if isCellarEmpty {
                EmptyFridgeView(shelves: layoutShelves, onAdd: onTapCamera)
            } else {
                FridgeCabinetView(
                    shelves: layoutShelves,
                    bottleForSlot: { fridgeBottlesByAddress[$0] },
                    currentYear: currentYear,
                    onSelectBottle: onSelectBottle,
                    onSelectEmptySlot: onSelectEmptySlot
                )
            }
        case .boxes:
            BoxesPileView(bottles: boxesBottles, currentYear: currentYear, onSelectBottle: onSelectBottle)
        }
    }

    // MARK: - Camera button

    private var cameraButton: some View {
        Button(action: onTapCamera) {
            Image(systemName: "camera.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CellarPalette.glassBlackDeep)
                .frame(width: 58, height: 58)
                .background(
                    Circle().fill(
                        RadialGradient(
                            colors: [CellarPalette.ledGlow, CellarPalette.ledGlow.opacity(0.75)],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 60
                        )
                    )
                )
                .shadow(color: CellarPalette.ledGlow.opacity(0.4), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add bottle")
    }
}

#Preview {
    FridgeMapView()
        .modelContainer(for: [Wine.self, Bottle.self, Shelf.self, DrinkEvent.self, Memory.self, ReviewItem.self], inMemory: true)
}
