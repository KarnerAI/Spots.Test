//
//  ListKindTests.swift
//  Spots.TestTests
//
//  Ticket T2: locks the ListKind enum's raw values + display attributes.
//  These are the load-bearing strings between the iOS app, the Postgres
//  `list_kind_enum`, and the user-facing UI labels. If any of them drift,
//  saves silently land in the wrong list or the wrong icon shows up.
//

import SwiftUI
import Testing
@testable import Spots_Test

struct ListKindTests {

    // MARK: - Raw values match DB enum

    @Test func rawValuesMatchDatabaseEnum() {
        #expect(ListKind.favorites.rawValue == "favorites")
        #expect(ListKind.liked.rawValue == "liked")
        #expect(ListKind.wantToGo.rawValue == "want_to_go")
        #expect(ListKind.custom.rawValue == "custom")
        #expect(ListKind.trip.rawValue == "trip")
        #expect(ListKind.datePlan.rawValue == "date_plan")
    }

    @Test func allCasesCoversEverySixKind() {
        // Catches silent additions / removals during future migrations.
        #expect(ListKind.allCases.count == 6)
    }

    // MARK: - Display labels

    @Test func systemKindDisplayLabels() {
        // These are what the user sees. Must match DESIGN.md's Modern + Utility
        // direction (sentence-case, no decoration).
        #expect(ListKind.favorites.displayName == "Favorites")
        #expect(ListKind.liked.displayName == "Liked")
        #expect(ListKind.wantToGo.displayName == "Want to Go")
    }

    @Test func nonSystemKindDisplayLabels() {
        // Non-system kinds use these as fallbacks when name is nil — the
        // real UI usually shows the user-supplied name instead.
        #expect(ListKind.custom.displayName == "List")
        #expect(ListKind.trip.displayName == "Trip")
        #expect(ListKind.datePlan.displayName == "Date plan")
    }

    // MARK: - System-kind partition

    @Test func systemKindPredicateMatchesThreeDefaults() {
        #expect(ListKind.favorites.isSystemKind)
        #expect(ListKind.liked.isSystemKind)
        #expect(ListKind.wantToGo.isSystemKind)
        #expect(!ListKind.custom.isSystemKind)
        #expect(!ListKind.trip.isSystemKind)
        #expect(!ListKind.datePlan.isSystemKind)
    }

    // MARK: - Icon mapping

    @Test func systemKindIconsCarryOverFromLegacyListType() {
        // Tier mapping: favorites = elite (heart, red), liked = mid (thumb, blue),
        // wantToGo = wishlist (flag, emerald). Preserved across the
        // ListType -> ListKind rename so existing UI doesn't shift visually.
        #expect(ListKind.favorites.iconName == "heart.fill")
        #expect(ListKind.liked.iconName == "hand.thumbsup.fill")
        #expect(ListKind.wantToGo.iconName == "flag.fill")
    }

    // MARK: - displayKind priority resolver

    @Test func displayKindPrefersWantToGoOverFavoritesAndLiked() {
        let saved: Set<ListKind> = [.favorites, .liked, .wantToGo]
        #expect(displayKind(for: saved) == .wantToGo)
    }

    @Test func displayKindFavoritesBeatsLiked() {
        let saved: Set<ListKind> = [.favorites, .liked]
        #expect(displayKind(for: saved) == .favorites)
    }

    @Test func displayKindReturnsNilWhenNoSystemKindPresent() {
        #expect(displayKind(for: []) == nil)
        #expect(displayKind(for: [.custom]) == nil)
        #expect(displayKind(for: [.trip, .datePlan]) == nil)
    }

    @Test func displayKindIgnoresNonSystemKindsInMixedSet() {
        let saved: Set<ListKind> = [.custom, .trip, .liked]
        #expect(displayKind(for: saved) == .liked)
    }
}
