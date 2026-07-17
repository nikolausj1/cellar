//
//  PiStatusDot.swift
//  Cellar — Views/Map
//
//  PRD §6.1 Error state: "unreachable Pi shows a small, non-blocking status
//  dot. Never a modal. The map does not depend on the Pi." This view never
//  awaits anything the map's first paint depends on — it renders instantly in
//  the "unknown" state and updates itself once a health check resolves,
//  entirely off to the side of the render path.
//

import SwiftUI

struct PiStatusDot: View {
    enum Status {
        case checking
        case healthy
        case unreachable
    }

    let client: PiClientProtocol
    @State private var status: Status = .checking

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 0.5))
            .task {
                await refresh()
            }
            .accessibilityLabel(accessibilityText)
    }

    private var color: Color {
        switch status {
        case .checking: Color.white.opacity(0.18)
        case .healthy: CellarPalette.readinessReady.opacity(0.85)
        case .unreachable: Color.white.opacity(0.3)
        }
    }

    private var accessibilityText: String {
        switch status {
        case .checking: "Checking scan station"
        case .healthy: "Scan station online"
        case .unreachable: "Scan station unreachable"
        }
    }

    private func refresh() async {
        do {
            _ = try await client.health()
            status = .healthy
        } catch {
            status = .unreachable
        }
    }
}
