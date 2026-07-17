//
//  CellarTheme.swift
//  Cellar — Views/Map
//
//  The literal palette from PRD §7. Nothing in this file is a judgment call —
//  every color is copied from the spec. Shared by Views/Map and Views/Setup
//  (same compiled module, no import needed) so the setup screen doesn't drift
//  into a different look from the map it configures.
//
//  Tone words from the PRD: warm, dim, expensive, quiet. A cellar at night.
//

import Foundation
import SwiftUI

extension Color {
    /// Hex string like "0A0A0B" or "#0A0A0B", RGB or RGBA.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)

        let r, g, b, a: UInt64
        switch s.count {
        case 8:
            (r, g, b, a) = ((value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
        default:
            (r, g, b, a) = ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF, 0xFF)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum CellarPalette {
    // Near-black glass — the cabinet interior and the app's base background.
    static let glassBlack = Color(hex: "0A0A0B")
    static let glassBlackDeep = Color(hex: "050506")

    // Brushed stainless rails — gradient top to bottom.
    static let railTop = Color(hex: "C8CCD0")
    static let railBottom = Color(hex: "8E9499")

    // Warm interior LED, pooling low-opacity from shelf edges.
    static let ledGlow = Color(hex: "FFE9C4")

    // Readiness ring colors — restrained, a ring not a highlighter.
    static let readinessReady = Color(hex: "4C9A5E")     // green — in window
    static let readinessHold = Color(hex: "C9922F")      // amber — hold, too young
    static let readinessDrinkSoon = Color(hex: "B44B3C") // red — drink soon
    static let readinessUnknown = Color.white.opacity(0.22) // neutral, no data

    // Foil capsule variants — gold / burgundy / black / matte.
    static let foilGoldLight = Color(hex: "E4C878")
    static let foilGoldDark = Color(hex: "8A6A22")
    static let foilBurgundyLight = Color(hex: "7C2E3E")
    static let foilBurgundyDark = Color(hex: "34121A")
    static let foilBlackLight = Color(hex: "3A3A3D")
    static let foilBlackDark = Color(hex: "121213")
    static let foilMatteLight = Color(hex: "9A9A9E")
    static let foilMatteDark = Color(hex: "5C5C60")

    // Unresolved (wine == nil, recognition pending) — a NORMAL frequent state,
    // never rendered as an error. Frosted, desaturated, calm.
    static let unresolvedLight = Color(hex: "747478")
    static let unresolvedDark = Color(hex: "3E3E42")

    // Wood-tone slot dividers, storage shelves (see _inbox photo 3).
    static let woodLight = Color(hex: "B08A5E")
    static let woodDark = Color(hex: "6B4E30")
}

/// Wine names read like a wine list, not a database: optical sizing + generous
/// tracking, SF Pro throughout (the system font already is SF Pro on iOS).
extension View {
    func wineListType(size: CGFloat = 15, weight: Font.Weight = .medium) -> some View {
        self
            .font(.system(size: size, weight: weight, design: .default))
            .tracking(0.6)
    }

    func cellarLabelType(size: CGFloat = 11, weight: Font.Weight = .semibold) -> some View {
        self
            .font(.system(size: size, weight: weight, design: .default))
            .tracking(1.4)
            .textCase(.uppercase)
    }
}
