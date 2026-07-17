//
//  ScanStationSettingsView.swift
//  Cellar — Views/Setup
//
//  The only place in the app that ever writes PiClientSettings.baseURL — until
//  this view existed, the Pi's address could be stored but nothing ever set
//  it, so every Pi call threw .notConfigured forever. PiClientSettings is NOT
//  ObservableObject (see PiClient.swift); it's a thin UserDefaults wrapper, so
//  this view keeps its own @State for the text field and reads/writes through
//  it explicitly rather than pretending it's bindable.
//
//  PiStatusDot only checks health once, via .task on appear, and won't notice
//  an edit made here — so "Test connection" is the owner's only way to get
//  immediate feedback that a URL actually works.
//

import SwiftUI

struct ScanStationSettingsView: View {
    private let settings = PiClientSettings()

    /// Passed as a String, not a literal: a literal binds to the
    /// LocalizedStringKey overload, which runs markdown over it, auto-detects
    /// the URL and tints it like a link — making the placeholder read as an
    /// already-configured address.
    private static let urlPlaceholder = "http://192.168.1.50:8000"

    @State private var urlText: String = ""
    @State private var validationMessage: String?
    @State private var testStatus: TestStatus = .idle
    @FocusState private var isEditing: Bool

    private enum TestStatus: Equatable {
        case idle
        case checking
        case reachable(String)
        case unreachable(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scan station")
                .cellarLabelType(size: 12)
                .foregroundStyle(.white.opacity(0.55))

            VStack(alignment: .leading, spacing: 10) {
                TextField(Self.urlPlaceholder, text: $urlText)
                    .focused($isEditing)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .wineListType(size: 15, weight: .regular)
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .onChange(of: urlText) { _, newValue in commit(newValue) }
                    .onSubmit { commit(urlText) }

                // Held back until editing stops: commit() runs per keystroke, so
                // showing this live would flag "http" as invalid before the rest
                // of the address has been typed.
                if let validationMessage, !isEditing {
                    Text(validationMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(CellarPalette.readinessDrinkSoon.opacity(0.9))
                }

                HStack(spacing: 12) {
                    Button(action: testConnection) {
                        Text("Test connection")
                            .wineListType(size: 13, weight: .semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(CellarPalette.ledGlow.opacity(0.9)))
                            .foregroundStyle(CellarPalette.glassBlackDeep)
                    }
                    .buttonStyle(.plain)
                    .disabled(testStatus == .checking)

                    statusView
                    Spacer()
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

            Text(verbatim: "The address of the Pi scan station on your network, e.g. \(Self.urlPlaceholder).")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
        }
        .onAppear {
            if let baseURL = settings.baseURL {
                urlText = baseURL.absoluteString
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusView: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
                Text("Checking…")
                    .wineListType(size: 12)
                    .foregroundStyle(.white.opacity(0.5))
            }
        case .reachable(let detail):
            HStack(spacing: 6) {
                Circle().fill(CellarPalette.readinessReady).frame(width: 6, height: 6)
                Text("Reachable" + (detail.isEmpty ? "" : " — \(detail)"))
                    .wineListType(size: 12)
                    .foregroundStyle(.white.opacity(0.7))
            }
        case .unreachable(let reason):
            HStack(spacing: 6) {
                Circle().fill(CellarPalette.readinessDrinkSoon).frame(width: 6, height: 6)
                Text(reason)
                    .wineListType(size: 12)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Persistence

    /// Called on every keystroke and on submit. A blank field clears the
    /// stored URL (lets the owner reset to unconfigured); a non-empty field
    /// only overwrites storage once it parses as a usable http(s) URL — an
    /// in-progress, not-yet-valid string is never persisted over a good one.
    private func commit(_ text: String) {
        testStatus = .idle
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            validationMessage = nil
            settings.baseURL = nil
            return
        }

        guard let url = Self.parseServerURL(trimmed) else {
            validationMessage = "Enter a valid http:// or https:// address with a host, e.g. http://192.168.1.50:8000"
            return
        }

        validationMessage = nil
        settings.baseURL = url
    }

    private static func parseServerURL(_ text: String) -> URL? {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              let url = components.url
        else { return nil }
        return url
    }

    // MARK: - Test connection

    private func testConnection() {
        testStatus = .checking
        let client = PiClient(settings: PiClientSettings())
        Task { @MainActor in
            do {
                let health = try await client.health()
                testStatus = .reachable("\(health.hardware), \(health.recognizer)")
            } catch PiClientError.notConfigured {
                testStatus = .unreachable("Enter a URL above first.")
            } catch {
                testStatus = .unreachable("Unreachable — check the address and network.")
            }
        }
    }
}

#Preview {
    ZStack {
        CellarPalette.glassBlackDeep.ignoresSafeArea()
        ScanStationSettingsView()
            .padding(16)
    }
    .preferredColorScheme(.dark)
}
