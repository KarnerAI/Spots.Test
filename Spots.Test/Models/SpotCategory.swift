//
//  SpotCategory.swift
//  Spots.Test
//
//  Coarse user-facing categories that drive the Search screen's filter chips.
//  Each case maps to one or more `NearbySpot.category` strings produced by
//  `NearbySpot.mapCategory(from:)`. Nightlife was dropped in favor of Shopping
//  because NearbySpot.mapCategory has no distinct nightlife output (night_club
//  falls into "Bar") — a separate chip would be visually duplicative.
//

import Foundation

enum SpotCategory: String, CaseIterable, Identifiable {
    case coffee
    case food
    case bars
    case outdoors
    case shopping

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coffee:   return "Coffee"
        case .food:     return "Food"
        case .bars:     return "Bars"
        case .outdoors: return "Outdoors"
        case .shopping: return "Shopping"
        }
    }

    var emoji: String {
        switch self {
        case .coffee:   return "☕"
        case .food:     return "🍴"
        case .bars:     return "🍸"
        case .outdoors: return "🌳"
        case .shopping: return "🛍"
        }
    }

    /// True when a `NearbySpot.category` string belongs to this chip.
    /// Matched against the canonical categories produced by
    /// `NearbySpot.mapCategory(from:)`, case-insensitive.
    func matches(_ category: String) -> Bool {
        let normalized = category.lowercased()
        return matchingCategories.contains(normalized)
    }

    private var matchingCategories: Set<String> {
        switch self {
        case .coffee:   return ["coffee", "cafe"]
        case .food:     return ["restaurant", "bakery", "food"]
        case .bars:     return ["bar"]
        case .outdoors: return ["park"]
        case .shopping: return ["store"]
        }
    }
}
