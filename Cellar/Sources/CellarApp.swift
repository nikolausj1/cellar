//
//  CellarApp.swift
//  Cellar
//
//  Routing only (per the brief). The app opens directly to the fridge map —
//  PRD §6.1's locked decision that reverses the source draft's "camera opens
//  immediately." Camera-first moved to the Pi; the phone opens to the map.
//
//  `-demoLayout` (Build Guide: "give each screen a launch-arg autostart hook")
//  swaps in an entirely separate, in-memory-only ModelContainer pre-populated
//  with sample data, so `simctl` — which cannot tap — can still screenshot a
//  populated map. It is structurally incapable of touching the real store: see
//  DemoSeed.swift.
//
//  This file now also owns the ONE `RecognitionQueue` instance for the whole
//  app (a Services type, but constructing and injecting it is wiring, not
//  feature logic — the add flow and review queue below only ever call
//  `.submit(...)`, never construct their own queue). `resumePending()` is
//  called once at launch (Build Guide / PRD acceptance: "kill the Pi
//  mid-session: adds continue, nothing is lost, queue drains on restart").
//
//  Screens this file routes to but does not own: bottle detail and memory
//  capture remain TODO closures for other workers. The add flow and review
//  queue are wired below.
//
//  Screenshot-only autostart hooks (simctl cannot tap, Build Guide: "give
//  each screen a launch-arg autostart hook"):
//    -showAddFlow        opens the single add flow on the camera screen
//    -showBulkSlotting   jumps straight to the bulk batch-slotting screen,
//                        seeded from whatever is currently in Boxes
//                        (pairs with -demoLayout)
//    -showReviewQueue    opens the review queue
//    -autoAddForTest     (requires -fakeCamera) opens the add flow
//                        pre-targeted at a known-free demo slot and lets
//                        CameraCaptureCore's own auto-capture hook fire the
//                        shutter with no tap — see FakeCameraSupport and the
//                        verification report for what this proves.
//    -showOnboarding     forces OnboardingView regardless of whether the
//                        one-time flag has already been set
//    -onboardingPage N   (requires -showOnboarding) jumps straight to page N
//                        (0-2) — simctl can't swipe a TabView, so this is the
//                        only way to screenshot pages 2 and 3
//

import SwiftUI
import SwiftData

@main
struct CellarApp: App {
    /// nil when running against the real, on-disk store (the normal case).
    /// Non-nil only under `-demoLayout`, in which case it takes over as the
    /// scene's container entirely, in place of the real one.
    private let demoContainer: ModelContainer?

    /// One PiClient, one RecognitionQueue, for the app's whole lifetime —
    /// constructed here so the add flow and review queue never each stand
    /// up their own (which would fragment the pending-recognition disk
    /// queue and the in-flight de-dup set across instances).
    private let piClient: PiClientProtocol
    private let recognitionQueue: RecognitionQueue

    init() {
        let seededContainer = DemoSeed.isRequested ? DemoSeed.makeContainer() : nil
        demoContainer = seededContainer

        let client = PiClient(settings: PiClientSettings())
        piClient = client
        recognitionQueue = RecognitionQueue(container: seededContainer ?? Self.sharedRealContainer, client: client)

        let args = ProcessInfo.processInfo.arguments
        // `-showSetup`: another simctl-can't-tap autostart hook, this one for
        // screenshotting the Setup screen directly.
        _setupPresented = State(initialValue: args.contains("-showSetup"))
        _reviewQueuePresented = State(initialValue: args.contains("-showReviewQueue"))
        _bulkSlottingScreenshotPresented = State(initialValue: args.contains("-showBulkSlotting"))

        if args.contains("-autoAddForTest") {
            // Shelf 0, slot 4 is left open by DemoSeed on purpose — a known
            // free address so this hook is deterministic under -demoLayout.
            _addOverlay = State(initialValue: .single(preTargetedSlot: SlotAddress(shelfIndex: 0, slot: 4)))
        } else if args.contains("-showAddFlow") {
            _addOverlay = State(initialValue: .single(preTargetedSlot: nil))
        } else {
            _addOverlay = State(initialValue: nil)
        }

        // OnboardingView owns the write side of this flag (mirrors
        // hasSeenCameraCoach); this is the one place that has to read it
        // before that view exists, to decide whether to present it at all.
        let hasSeenOnboarding = UserDefaults.standard.bool(forKey: Self.hasSeenOnboardingKey)
        let showOnboardingNow = args.contains("-showOnboarding") || !hasSeenOnboarding
        _onboardingPresented = State(initialValue: showOnboardingNow)
        // Splash is the cold-launch brand beat for the "straight to the map"
        // path. When onboarding is about to show, it already IS that beat —
        // stacking the splash in front of it would be two logo moments back
        // to back.
        _splashPresented = State(initialValue: !showOnboardingNow)

        var onboardingPage = 0
        if let idx = args.firstIndex(of: "-onboardingPage"), idx + 1 < args.count, let n = Int(args[idx + 1]) {
            onboardingPage = n
        }
        _onboardingInitialPage = State(initialValue: onboardingPage)
    }

    private static let hasSeenOnboardingKey = "Cellar.hasSeenOnboarding"

    var body: some Scene {
        WindowGroup {
            ZStack {
                NavigationStack {
                    FridgeMapView(
                        onSelectBottle: { _ in
                            // TODO(bottle-detail worker): push to Bottle Detail.
                        },
                        onSelectEmptySlot: { address in
                            addOverlay = .single(preTargetedSlot: address)
                        },
                        onTapCamera: {
                            addOverlay = .single(preTargetedSlot: nil)
                        },
                        onOpenSetup: {
                            setupPresented = true
                        },
                        onTapReviewQueue: {
                            reviewQueuePresented = true
                        },
                        onTapMemoryCard: { _ in
                            // TODO(memory-cascade worker): open the memory prompt.
                        }
                    )
                    .navigationDestination(isPresented: $setupPresented) {
                        FridgeSetupView()
                    }
                }
                .tint(CellarPalette.ledGlow)
                .fullScreenCover(item: $addOverlay) { overlay in
                    switch overlay {
                    case let .single(preTargetedSlot):
                        AddFlowView(
                            preTargetedSlot: preTargetedSlot,
                            onFinished: { addOverlay = nil },
                            onEnterBulkMode: { addOverlay = .bulk },
                            recognitionQueue: recognitionQueue
                        )
                    case .bulk:
                        BulkAddFlowView(onFinished: { addOverlay = nil }, recognitionQueue: recognitionQueue)
                    }
                }
                .fullScreenCover(isPresented: $bulkSlottingScreenshotPresented) {
                    BulkSlottingScreenshotHost(onFinished: { bulkSlottingScreenshotPresented = false })
                }
                .sheet(isPresented: $reviewQueuePresented) {
                    NavigationStack {
                        ReviewQueueView(recognitionQueue: recognitionQueue)
                    }
                }
                .task {
                    // PRD acceptance: "Kill the Pi mid-session: adds continue,
                    // nothing is lost, queue drains on restart." This resumes
                    // whatever RecognitionQueue's on-disk pending list had left
                    // over from a previous run. Not on THE RULE's hot path —
                    // this happens once, at launch, off to the side.
                    await recognitionQueue.resumePending()
                }

                // The one branded beat on a cold launch that opens straight to
                // the map (see init(): mutually exclusive with onboarding, which
                // is its own branded beat). Sits above the map in the ZStack and
                // self-dismisses via onFinished.
                if splashPresented {
                    SplashView(onFinished: { splashPresented = false })
                        .zIndex(1)
                }
            }
            .fullScreenCover(isPresented: $onboardingPresented) {
                OnboardingView(
                    onFinished: { openSetup in
                        onboardingPresented = false
                        if openSetup {
                            setupPresented = true
                        }
                    },
                    initialPage: onboardingInitialPage
                )
            }
        }
        .modelContainer(demoContainer ?? realContainer)
    }

    // MARK: - Real container

    /// The persistent, on-disk store. Built once, lazily, only when
    /// `-demoLayout` isn't present — the demo path never touches this.
    private var realContainer: ModelContainer {
        Self.sharedRealContainer
    }

    private static let sharedRealContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Wine.self, Bottle.self, Shelf.self, DrinkEvent.self, Memory.self, ReviewItem.self)
        } catch {
            fatalError("Failed to create the Cellar model container: \(error)")
        }
    }()

    @State private var setupPresented = false
    @State private var reviewQueuePresented = false
    @State private var bulkSlottingScreenshotPresented = false
    @State private var addOverlay: AddOverlay?
    @State private var onboardingPresented = false
    @State private var splashPresented = false
    @State private var onboardingInitialPage = 0
}

/// What full-screen add experience (if any) is presented right now.
/// `Identifiable` so `.fullScreenCover(item:)` can drive it directly.
private enum AddOverlay: Identifiable {
    case single(preTargetedSlot: SlotAddress?)
    case bulk

    var id: String {
        switch self {
        case .single: "single"
        case .bulk: "bulk"
        }
    }
}

/// Screenshot-only entry point for `-showBulkSlotting`: skips capture
/// entirely and hands BulkSlottingView whatever bottles are currently
/// sitting in Boxes (under `-demoLayout`, DemoSeed's three Boxes bottles),
/// so the batch-slotting screen is reachable without simctl needing to tap
/// through a real bulk-capture session first.
private struct BulkSlottingScreenshotHost: View {
    @Query private var allBottles: [Bottle]
    let onFinished: () -> Void

    private var boxesBottles: [Bottle] {
        allBottles.filter { bottle in
            guard bottle.status == .present else { return false }
            if case .boxes = bottle.location { return true }
            return false
        }
    }

    var body: some View {
        BulkSlottingView(
            bottles: boxesBottles,
            onFinished: onFinished,
            initialSelectedBottleID: boxesBottles.first?.id
        )
    }
}
