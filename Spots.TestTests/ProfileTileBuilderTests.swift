//
//  ProfileTileBuilderTests.swift
//  Spots.TestTests
//
//  Regression guard for T21 polish-pass change in ProfileTileBuilder. The
//  bug we just fixed: custom lists were excluded from the Profile carousel
//  entirely. Maya created "Mexico City 2026" and it never showed up on
//  Profile until she tapped View all.
//
//  These tests cover the pure helper `customListsInDisplayOrder(from:)`
//  that buildTiles delegates to. Hitting `buildTiles` directly requires
//  the live LocationSavingService.shared singleton (which makes Supabase
//  RPC calls), so we test the deterministic input→output piece instead.
//
//  If a future edit reverts or refactors this filter, these tests fail
//  loud before Maya's lists silently disappear from her own profile.
//

import Testing
import Foundation
@testable import Spots_Test

struct ProfileTileBuilderTests {

    // MARK: - Fixtures

    static let userId = UUID()

    static func sample(
        id: UUID = UUID(),
        kind: ListKind,
        name: String? = nil,
        createdAt: Date? = nil
    ) -> UserList {
        UserList(
            id: id,
            userId: userId,
            kind: kind,
            name: name,
            createdAt: createdAt
        )
    }

    // MARK: - 1. Custom lists are included (the regression we fixed)

    @Test func testCustomListsInDisplayOrder_includesCustomLists() {
        let lists: [UserList] = [
            Self.sample(kind: .favorites),
            Self.sample(kind: .liked),
            Self.sample(kind: .wantToGo),
            Self.sample(kind: .custom, name: "Mexico City 2026")
        ]

        let result = ProfileTileBuilder.customListsInDisplayOrder(from: lists)

        #expect(result.count == 1)
        #expect(result.first?.name == "Mexico City 2026")
        #expect(result.first?.kind == .custom)
    }

    // MARK: - 2. System kinds are excluded

    @Test func testCustomListsInDisplayOrder_excludesSystemKinds() {
        let lists: [UserList] = [
            Self.sample(kind: .favorites, name: nil),
            Self.sample(kind: .liked, name: nil),
            Self.sample(kind: .wantToGo, name: nil)
        ]

        let result = ProfileTileBuilder.customListsInDisplayOrder(from: lists)

        #expect(result.isEmpty,
                "System kinds (favorites/liked/want_to_go) must not appear in the custom-lists section — they belong in the system tiles above.")
    }

    // MARK: - 3. Newest-first ordering by createdAt

    @Test func testCustomListsInDisplayOrder_sortsNewestFirst() {
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023
        let midDate = Date(timeIntervalSince1970: 1_715_000_000) // 2024
        let newDate = Date(timeIntervalSince1970: 1_716_000_000) // 2024-05

        let lists: [UserList] = [
            Self.sample(kind: .custom, name: "Oldest", createdAt: oldDate),
            Self.sample(kind: .custom, name: "Newest", createdAt: newDate),
            Self.sample(kind: .custom, name: "Middle", createdAt: midDate)
        ]

        let result = ProfileTileBuilder.customListsInDisplayOrder(from: lists)

        #expect(result.count == 3)
        #expect(result[0].name == "Newest")
        #expect(result[1].name == "Middle")
        #expect(result[2].name == "Oldest")
    }

    // MARK: - 4. Nil createdAt sorts to the end (distant past fallback)

    @Test func testCustomListsInDisplayOrder_nilCreatedAtSortsLast() {
        let recentDate = Date(timeIntervalSince1970: 1_716_000_000)

        let lists: [UserList] = [
            Self.sample(kind: .custom, name: "Recent", createdAt: recentDate),
            Self.sample(kind: .custom, name: "Unknown date", createdAt: nil)
        ]

        let result = ProfileTileBuilder.customListsInDisplayOrder(from: lists)

        #expect(result[0].name == "Recent")
        #expect(result[1].name == "Unknown date")
    }

    // MARK: - 5. Empty input → empty output (boundary)

    @Test func testCustomListsInDisplayOrder_emptyInputReturnsEmpty() {
        let result = ProfileTileBuilder.customListsInDisplayOrder(from: [])
        #expect(result.isEmpty)
    }

    // MARK: - 6. Mixed kinds, mixed dates — full integration of the rules

    @Test func testCustomListsInDisplayOrder_mixedInputProducesOrderedCustomsOnly() {
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_716_000_000)

        let lists: [UserList] = [
            Self.sample(kind: .favorites, createdAt: t2),      // excluded
            Self.sample(kind: .custom, name: "Custom A", createdAt: t1),
            Self.sample(kind: .liked, createdAt: t2),          // excluded
            Self.sample(kind: .trip, name: "Trip", createdAt: t2),
            Self.sample(kind: .wantToGo, createdAt: t2),       // excluded
            Self.sample(kind: .datePlan, name: "Date plan", createdAt: t1)
        ]

        let result = ProfileTileBuilder.customListsInDisplayOrder(from: lists)

        // 3 non-system kinds (custom, trip, datePlan); newest first.
        #expect(result.count == 3)
        #expect(result.map(\.name) == ["Trip", "Custom A", "Date plan"]
                || result.map(\.name) == ["Trip", "Date plan", "Custom A"],
                "Trip (newer) must come first; the two older entries can swap since they share a createdAt timestamp.")
    }
}
