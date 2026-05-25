//
//  DesignTokens.swift
//  Spots.Test
//
//  Shared design tokens for T21 + future Direction D surfaces.
//  Source of truth: Spots.Test/DESIGN.md (Modern + Utility, locked 2026-05-23).
//
//  Lifted from CreateListView.swift in the eng-review round 2 polish pass
//  (2026-05-25) once a second view (ListSettingsSheet) plus a third
//  (AllListsView) and a touch on ListPickerView started referencing these
//  tokens. Keeping them at the bottom of CreateListView coupled four files
//  to that one — moving them here decouples the dependency graph and makes
//  the design system surface explicit.
//
//  When adding a new color or font helper:
//    1. First check DESIGN.md to confirm the value lives there.
//    2. Add to DESIGN.md if it doesn't (the design system is the source of
//       truth, not this file).
//    3. Then add the Swift mapping here.
//

import SwiftUI

// MARK: - Color tokens (DESIGN.md §4)

extension Color {
    /// Cool blue accent #2563EB — single accent color for Modern + Utility.
    static let spotsAccent = Color(red: 0.145, green: 0.388, blue: 0.922)

    /// Accent-tinted background for pickers, hints, soft surfaces. #EFF4FE.
    static let spotsAccentSoft = Color(red: 0.937, green: 0.957, blue: 0.996)

    /// Primary text color. #0A0A0A.
    static let spotsText = Color(red: 0.039, green: 0.039, blue: 0.039)

    /// Secondary text, captions, meta. #6B6B6B.
    static let spotsTextMuted = Color(red: 0.42, green: 0.42, blue: 0.42)

    /// Tertiary / placeholder / timestamp text. #9B9B9B.
    static let spotsTextSubtle = Color(red: 0.608, green: 0.608, blue: 0.608)

    /// Hairline divider, default border. #EEEEEE.
    static let spotsBorder = Color(red: 0.933, green: 0.933, blue: 0.933)

    /// Stronger border for input focus or extra separation. #D1D5DB.
    static let spotsBorderStrong = Color(red: 0.82, green: 0.835, blue: 0.859)

    /// Destructive / error red. #DC2626.
    static let spotsError = Color(red: 0.863, green: 0.149, blue: 0.149)
}

// MARK: - Geist font helpers (DESIGN.md §3)
//
// DESIGN.md calls for Geist body + Geist Mono. The .ttf/.otf files aren't
// bundled yet (no UIAppFonts entry in Info.plist), so these helpers fall
// back to .system() with matching weights. When Geist ships in the bundle,
// swap the implementations to .custom("Geist-...") — call sites won't need
// to change.

extension Font {
    /// Display / body font. Will switch to Geist once fonts are bundled.
    static func geist(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Monospace variant for tabular numerals (char counters, timestamps).
    static func geistMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
