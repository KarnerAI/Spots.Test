//
//  SearchViewModelTests.swift
//  Spots.TestTests
//
//  Covers the filter behavior the chips bar drives: each SpotCategory
//  narrows the visible nearby list to the right subset, nil shows everything,
//  and the header label tracks the active filter.
//

import Testing
import Foundation
@testable import Spots_Test

@MainActor
struct SearchViewModelTests {

    /// Synthetic nearby list spanning every category the chips can match
    /// plus an entry ("Museum") that no chip should match — verifies the
    /// "intersection only" contract.
    private static func sampleSpots() -> [NearbySpot] {
        [
            spot(id: "1", name: "Sightglass",   category: "Coffee"),
            spot(id: "2", name: "Cafe Reveille", category: "Cafe"),
            spot(id: "3", name: "Tartine",      category: "Bakery"),
            spot(id: "4", name: "Zuni Cafe",    category: "Restaurant"),
            spot(id: "5", name: "Trick Dog",    category: "Bar"),
            spot(id: "6", name: "Dolores Park", category: "Park"),
            spot(id: "7", name: "Bi-Rite",      category: "Store"),
            spot(id: "8", name: "SFMOMA",       category: "Museum"),
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

    /// Test-only helper that seeds the VM's nearbySpots without going
    /// through the real PlacesAPIService. The VM exposes `nearbySpots` as
    /// `private(set)` so we mutate via the recordRecent path... no — we
    /// actually need a way to inject. The simplest, least-invasive trick
    /// is to read the published list after a manual assignment in the test
    /// scope using key-path mutation through an `@testable` member.
    private func seed(_ vm: SearchViewModel, with spots: [NearbySpot]) {
        // `private(set)` is internal-accessible from @testable, so direct
        // assignment via setValue isn't needed — Swift will let us reach
        // into the underlying storage by exposing a test-only setter via
        // the model. Avoiding that here: drive filteredNearby by writing
        // the underlying property via reflection-free direct access.
        vm.setNearbyForTesting(spots)
    }

    @Test func nilFilterReturnsAllSpots() {
        let vm = SearchViewModel(store: isolatedStore())
        seed(vm, with: Self.sampleSpots())

        vm.activeFilter = nil
        #expect(vm.filteredNearby.count == Self.sampleSpots().count)
    }

    @Test func coffeeFilterMatchesCoffeeAndCafe() {
        let vm = SearchViewModel(store: isolatedStore())
        seed(vm, with: Self.sampleSpots())

        vm.activeFilter = .coffee
        let ids = vm.filteredNearby.map(\.placeId)
        #expect(ids == ["1", "2"])
    }

    @Test func foodFilterMatchesRestaurantBakeryAndFood() {
        let vm = SearchViewModel(store: isolatedStore())
        seed(vm, with: Self.sampleSpots())

        vm.activeFilter = .food
        let names = Set(vm.filteredNearby.map(\.name))
        #expect(names == ["Tartine", "Zuni Cafe"])
    }

    @Test func barsFilterMatchesBarOnly() {
        let vm = SearchViewModel(store: isolatedStore())
        seed(vm, with: Self.sampleSpots())

        vm.activeFilter = .bars
        #expect(vm.filteredNearby.map(\.placeId) == ["5"])
    }

    @Test func outdoorsFilterMatchesPark() {
        let vm = SearchViewModel(store: isolatedStore())
        seed(vm, with: Self.sampleSpots())

        vm.activeFilter = .outdoors
        #expect(vm.filteredNearby.map(\.placeId) == ["6"])
    }

    @Test func shoppingFilterMatchesStore() {
        let vm = SearchViewModel(store: isolatedStore())
        seed(vm, with: Self.sampleSpots())

        vm.activeFilter = .shopping
        #expect(vm.filteredNearby.map(\.placeId) == ["7"])
    }

    @Test func filterReturnsEmptyWhenNoMatches() {
        let vm = SearchViewModel(store: isolatedStore())
        // Sample without any park entries.
        seed(vm, with: [Self.spot(id: "1", name: "Sightglass", category: "Coffee")])

        vm.activeFilter = .outdoors
        #expect(vm.filteredNearby.isEmpty)
    }

    @Test func nearbyHeaderTracksActiveFilter() {
        let vm = SearchViewModel(store: isolatedStore())
        #expect(vm.nearbyHeader == "Nearby now")

        vm.activeFilter = .coffee
        #expect(vm.nearbyHeader == "Nearby coffee")

        vm.activeFilter = .outdoors
        #expect(vm.nearbyHeader == "Nearby outdoors")
    }

    // MARK: - Helpers

    private func isolatedStore() -> RecentSearchStore {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return RecentSearchStore(defaults: defaults)
    }
}
