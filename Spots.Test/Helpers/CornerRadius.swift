//
//  CornerRadius.swift
//  Spots.Test
//
//  Centralized corner radius design tokens.
//  Use these constants everywhere instead of hardcoded values so the
//  entire app can be re-tuned from one place.
//

import CoreGraphics

enum CornerRadius {
    /// Badges, small tags (4pt)
    static let xSmall: CGFloat  = 4
    /// Minor UI accents (8pt)
    static let small: CGFloat   = 8
    /// Form input fields (10pt)
    static let field: CGFloat   = 10
    /// Cards and list tiles (16pt)
    static let card: CGFloat    = 16
    /// Floating search bars (24pt)
    static let searchBar: CGFloat = 24
    /// CTA buttons (22pt)
    static let button: CGFloat  = 22
    /// Bottom sheets and profile card — all sheet-style surfaces (32pt)
    static let sheet: CGFloat   = 32
    /// Pill-shaped buttons — set large so full height/2 is always exceeded (9999pt)
    static let pill: CGFloat    = 9999
}
