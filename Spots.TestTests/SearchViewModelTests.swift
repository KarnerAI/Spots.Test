//
//  SearchViewModelTests.swift
//  Spots.TestTests
//
//  Covers the filter behavior the chips bar drives: nil filter shows the
//  All fetch, a category filter shows the per-category cache entry, and
//  the header label tracks the active filter. The per-chip fetch itself
//  goes through PlacesAPIService and is not exercised here — these tests
//  seed both sides of the cache via the @testable hooks.
//

import Testing
import Foundation
@testable import Spots_Test

@MainActor
struct SearchViewModelTests {

    /// Synthetic "All" list — mixed categories, like what the broad
    /// nearby fetch would return.
    private static func allSampleSpots() -> [NearbySpot] {
        [
            spot(id: "1", name: "Sightglass",   category: "Coffee"),
            spot(id: "2", name: "Tartine",      category: "Bakery"),
            spot(id: "3", name: "Zuni Cafe",    category: "Restaurant"),
            spot(id: "4", name: "Trick Dog",    category: "Bar"),
            spot(id: "5", name: "Dolores Park", category: "Park"),
        ]
    }

    /// Synthetic per-category list — what a chip-restricted fetch returns.
    /// Notably bigger than the slice you'd get from filtering allSampleSpots,
    /// which is the entire point of the per-chip API call.
    private static func coffeeSampleSpots() -> [NearbySpot] {
        [
            spot(id: "c1", name: "Sightglass",            category: "Coffee"),
            spot(id: "c2", name: "Cafe Reveille",         category: "Cafe"),
            spot(id: "c3", name: "Saint Frank",           category: "Coffee"),
            spot(id: "c4", name: "Ritual Coffee",         category: "Coffee"),
        ]
    }

    private static func spot(id: String, name: String, category: String) -> NearbySpot {
        NearbySpot(
            placeId: id,
            name: name,
            address: "addr",
            category: category,
            latitude: 0,
            longitude: 0
        )
    }

    @Test func nilFilterReturnsAllSpots() {
        let vm = SearchViewModel(store: isolatedStore())
        vm.setNearbyForTesting(Self.allSampleSpots())

        vm.setFilter(nil)
        #expect(vm.filteredNearby.count == Self.allSampleSpots().count)
    }

    @Test func categoryFilterReturnsCachedEntry() {
        let vm = SearchViewModel(store: isolatedStore())
        vm.setNearbyForTesting(Self.allSampleSpots())
        vm.setFilteredForTesting(Self.coffeeSampleSpots(), for: .coffee)

        vm.setFilter(.coffee)
        let ids = vm.filteredNearby.map(\.placeId)
        #expect(ids == ["c1", "c2", "c3", "c4"])
    }

    @Test func categoryFilterReturnsEmptyWhenCacheMisses() {
        let vm = SearchViewModel(store: isolatedStore())
        vm.setNearbyForTesting(Self.allSampleSpots())
        // No cache for .bars — the fetch task would normally fire and
        // populate it; in tests with no PlacesAPIService stand-in the
        // miss surfaces as an empty list, which the view interprets as
        // "show the spinner or filtered-empty row."
        vm.setFilter(.bars)
        #expect(vm.filteredNearby.isEmpty)
    }

    @Test func clearingFilterReturnsAllAgain() {
        let vm = SearchViewModel(store: isolatedStore())
        vm.setNearbyForTesting(Self.allSampleSpots())
        vm.setFilteredForTesting(Self.coffeeSampleSpots(), for: .coffee)

        vm.setFilter(.coffee)
        #expect(vm.filteredNearby.count == 4)
        vm.setFilter(nil)
        #expect(vm.filteredNearby.count == Self.allSampleSpots().count)
    }

    @Test func nearbyHeaderTracksActiveFilter() {
        let vm = SearchViewModel(store: isolatedStore())
        #expect(vm.nearbyHeader == "Nearby now")

        vm.setFilter(.coffee)
        #expect(vm.nearbyHeader == "Nearby coffee")

        vm.setFilter(.outdoors)
        #expect(vm.nearbyHeader == "Nearby outdoors")
    }

    @Test func eachSpotCategoryHasPrimaryTypes() {
        // Drives the per-chip API call's `includedPrimaryTypes` field —
        // an empty list would silently turn into an unrestricted fetch
        // and break the "10 cafes" contract, so guard against future
        // typos that wipe a case's mapping.
        for category in SpotCategory.allCases {
            #expect(!category.primaryTypes.isEmpty, "\(category) must declare at least one Google Places primary type")
        }
    }

    @Test func coffeeMapsToCafeAndCoffeeShop() {
        // Smoke test on the most-used category to catch reorderings or
        // accidental rename of the canonical Google primary types.
        let types = Set(SpotCategory.coffee.primaryTypes)
        #expect(types.contains("cafe"))
        #expect(types.contains("coffee_shop"))
    }

    @Test func clearRecentsProxiesToStore() {
        // Each test injects its own UserDefaults so the proxy effect is
        // observable without polluting other suites. Direct store
        // reference also serves as the assertion target.
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = RecentSearchStore(defaults: defaults)
        store.record(placeId: "a", name: "Alpha", address: "1 Way")
        store.record(placeId: "b", name: "Bravo", address: "2 Way")
        let vm = SearchViewModel(store: store)
        #expect(vm.recents.count == 2)

        vm.clearRecents()
        #expect(store.recents.isEmpty)
        #expect(vm.recents.isEmpty)
    }

    @Test func removeRecentProxiesToStore() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = RecentSearchStore(defaults: defaults)
        store.record(placeId: "a", name: "Alpha", address: "1 Way")
        store.record(placeId: "b", name: "Bravo", address: "2 Way")
        let vm = SearchViewModel(store: store)

        vm.removeRecent(placeId: "a")
        #expect(store.recents.map(\.placeId) == ["b"])
        #expect(vm.recents.map(\.placeId) == ["b"])
    }

    // MARK: - Helpers

    private func isolatedStore() -> RecentSearchStore {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return RecentSearchStore(defaults: defaults)
    }
}
