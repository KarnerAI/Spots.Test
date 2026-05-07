//
//  SaveSpotFlowTests.swift
//  Spots.TestTests
//
//  Behavior tests for LocationSavingViewModel's saveSpotToLists / removeSpot
//  flow. Covers the new optimistic-update + single-default coercion + rollback
//  + per-placeId Task serialization machinery added when the Newsfeed
//  bookmark/list icon shipped.
//
//  Note on PlacesAPIService: saveSpot internally calls
//  `PlacesAPIService.shared.fetchPlaceDetails` (singleton, wrapped in `try?`)
//  to backfill country/rating. In tests with no network, that call fails fast
//  and `try?` swallows it — no test impact. If test runs become slow because
//  of this, the next refactor pass should extract a PlacesAPIServiceProtocol
//  and inject a no-op mock here.
//

import Testing
import Foundation
@testable import Spots_Test

// MARK: - Mock service

@MainActor
final class MockLocationSavingService: LocationSavingServiceProtocol, @unchecked Sendable {
    // Configurable behavior
    var listsContainingSpot: [String: [UUID]] = [:]
    var userListsResult: [UserList] = []
    var listsByType: [ListType: UserList] = [:]
    var spotsInListResult: [UUID: [SpotWithMetadata]] = [:]
    var spotCountResult: [UUID: Int] = [:]

    var upsertShouldThrow: Error?
    var saveSpotToListShouldThrow: Error?
    var removeSpotFromListShouldThrow: Error?

    /// If set, the service throws this error the first time saveSpotToList is
    /// called for the given listId, then resets. Lets us test partial-failure
    /// flows where one add succeeds and a remove fails.
    var saveSpotToListShouldThrowOnceForListId: UUID?
    /// Same semantics for removeSpotFromList — throws once for this listId then resets.
    var removeSpotFromListShouldThrowOnceForListId: UUID?

    // Call recorders
    var upsertSpotCalls: [(placeId: String, name: String)] = []
    var saveSpotToListCalls: [(placeId: String, listId: UUID)] = []
    var removeSpotFromListCalls: [(placeId: String, listId: UUID)] = []
    var getListsContainingSpotCalls: [String] = []

    // Sequencing helper for the concurrent-save serialization test.
    /// Optional async hook fired at the start of each saveSpotToList call —
    /// lets a test pause one call mid-flight to verify the second blocks.
    var saveSpotToListPreHook: (@Sendable (UUID) async -> Void)?

    func getUserLists() async throws -> [UserList] {
        return userListsResult
    }

    func getListByType(_ listType: ListType) async throws -> UserList? {
        return listsByType[listType]
    }

    func getSpotsInList(listId: UUID, listType: ListType) async throws -> [SpotWithMetadata] {
        return spotsInListResult[listId] ?? []
    }

    func getSpotCount(listId: UUID) async throws -> Int {
        return spotCountResult[listId] ?? 0
    }

    func getListsContainingSpot(placeId: String) async throws -> [UUID] {
        getListsContainingSpotCalls.append(placeId)
        return listsContainingSpot[placeId] ?? []
    }

    func saveSpotToList(placeId: String, listId: UUID) async throws {
        if let hook = saveSpotToListPreHook {
            await hook(listId)
        }
        if let err = saveSpotToListShouldThrow {
            saveSpotToListCalls.append((placeId, listId))
            throw err
        }
        if let onceListId = saveSpotToListShouldThrowOnceForListId, onceListId == listId {
            saveSpotToListShouldThrowOnceForListId = nil
            saveSpotToListCalls.append((placeId, listId))
            throw NSError(domain: "test", code: 1)
        }
        saveSpotToListCalls.append((placeId, listId))
        // Mirror DB state so later getListsContainingSpot reflects the add.
        var current = listsContainingSpot[placeId] ?? []
        if !current.contains(listId) { current.append(listId) }
        listsContainingSpot[placeId] = current
    }

    func removeSpotFromList(placeId: String, listId: UUID) async throws {
        if let err = removeSpotFromListShouldThrow {
            removeSpotFromListCalls.append((placeId, listId))
            throw err
        }
        if let onceListId = removeSpotFromListShouldThrowOnceForListId, onceListId == listId {
            removeSpotFromListShouldThrowOnceForListId = nil
            removeSpotFromListCalls.append((placeId, listId))
            throw NSError(domain: "test", code: 2)
        }
        removeSpotFromListCalls.append((placeId, listId))
        var current = listsContainingSpot[placeId] ?? []
        current.removeAll { $0 == listId }
        listsContainingSpot[placeId] = current
    }

    func upsertSpot(
        placeId: String,
        name: String,
        address: String?,
        city: String?,
        country: String?,
        latitude: Double?,
        longitude: Double?,
        types: [String]?,
        photoUrl: String?,
        photoReference: String?,
        rating: Double?
    ) async throws {
        if let err = upsertShouldThrow { throw err }
        upsertSpotCalls.append((placeId, name))
    }
}

// MARK: - Fixtures

@MainActor
private struct Fixtures {
    static let userId = UUID()
    static let favoritesId = UUID()
    static let starredId = UUID()
    static let bucketListId = UUID()
    static let customListId = UUID()

    static let favoritesList = UserList(
        id: favoritesId, userId: userId, listType: .favorites,
        name: nil, createdAt: nil, updatedAt: nil
    )
    static let starredList = UserList(
        id: starredId, userId: userId, listType: .starred,
        name: nil, createdAt: nil, updatedAt: nil
    )
    static let bucketList = UserList(
        id: bucketListId, userId: userId, listType: .bucketList,
        name: nil, createdAt: nil, updatedAt: nil
    )
    static let customList = UserList(
        id: customListId, userId: userId, listType: nil,
        name: "My Custom", createdAt: nil, updatedAt: nil
    )

    static let allLists: [UserList] = [favoritesList, starredList, bucketList, customList]

    static func spotData(placeId: String = "place-1") -> PlaceAutocompleteResult {
        PlaceAutocompleteResult(
            placeId: placeId,
            name: "Test Spot",
            address: "1 Test St",
            city: "Brooklyn",
            types: ["restaurant"],
            coordinate: nil,
            photoUrl: nil,
            photoReference: nil
        )
    }

    @MainActor
    static func makeVM(service: MockLocationSavingService) -> LocationSavingViewModel {
        let vm = LocationSavingViewModel(service: service)
        vm.userLists = allLists
        return vm
    }
}

// MARK: - Coercion (pure helpers)

@MainActor
struct CoerceToSingleDefaultTests {

    @Test func passThroughWhenSelectionHasNoDefaults() {
        let result = LocationSavingViewModel.coerceToSingleDefault(
            [Fixtures.customListId],
            userLists: Fixtures.allLists
        )
        #expect(result == [Fixtures.customListId])
    }

    @Test func passThroughWhenExactlyOneDefault() {
        let result = LocationSavingViewModel.coerceToSingleDefault(
            [Fixtures.favoritesId, Fixtures.customListId],
            userLists: Fixtures.allLists
        )
        #expect(result == [Fixtures.favoritesId, Fixtures.customListId])
    }

    @Test func dropsExtraDefaultsKeepingBucketListWinner() {
        // bucketList wins per priority order (matches displayListType resolver).
        let result = LocationSavingViewModel.coerceToSingleDefault(
            [Fixtures.favoritesId, Fixtures.starredId, Fixtures.bucketListId],
            userLists: Fixtures.allLists
        )
        #expect(result == [Fixtures.bucketListId])
    }

    @Test func dropsExtraDefaultsKeepingStarredOverFavorites() {
        let result = LocationSavingViewModel.coerceToSingleDefault(
            [Fixtures.favoritesId, Fixtures.starredId],
            userLists: Fixtures.allLists
        )
        #expect(result == [Fixtures.starredId])
    }

    @Test func keepsCustomListAlongsideCoercedDefault() {
        let result = LocationSavingViewModel.coerceToSingleDefault(
            [Fixtures.favoritesId, Fixtures.bucketListId, Fixtures.customListId],
            userLists: Fixtures.allLists
        )
        #expect(result == [Fixtures.bucketListId, Fixtures.customListId])
    }
}

// MARK: - listType helper

@MainActor
struct ListTypeHelperTests {
    @Test func returnsNilWhenNoDefaultSelected() {
        let result = LocationSavingViewModel.listType(
            for: [Fixtures.customListId],
            userLists: Fixtures.allLists
        )
        #expect(result == nil)
    }

    @Test func returnsTheDefaultListTypeWhenOneSelected() {
        let result = LocationSavingViewModel.listType(
            for: [Fixtures.favoritesId],
            userLists: Fixtures.allLists
        )
        #expect(result == .favorites)
    }
}

// MARK: - saveSpotToLists

@MainActor
struct SaveSpotToListsTests {

    @Test func singleDefaultListSelected_setsListType() async throws {
        let svc = MockLocationSavingService()
        let vm = Fixtures.makeVM(service: svc)
        let placeId = "place-1"

        try await vm.saveSpotToLists(spotData: Fixtures.spotData(placeId: placeId), listIds: [Fixtures.favoritesId])

        #expect(vm.spotListTypeMap[placeId] == .favorites)
        #expect(svc.saveSpotToListCalls.contains(where: { $0.listId == Fixtures.favoritesId }))
        #expect(vm.lastSaveError == nil)
    }

    @Test func picksTwoDefaultLists_coercesToOne() async throws {
        let svc = MockLocationSavingService()
        let vm = Fixtures.makeVM(service: svc)
        let placeId = "place-1"

        // User somehow selected two defaults (bypassing the radio UI). The VM
        // must coerce so only one default ends up in saveSpotToList calls.
        try await vm.saveSpotToLists(
            spotData: Fixtures.spotData(placeId: placeId),
            listIds: [Fixtures.favoritesId, Fixtures.bucketListId]
        )

        // bucketList wins per priority. Optimistic map reflects the winner.
        #expect(vm.spotListTypeMap[placeId] == .bucketList)
        // Only one default add hits the service.
        let defaultAdds = svc.saveSpotToListCalls.filter { call in
            call.listId == Fixtures.favoritesId || call.listId == Fixtures.bucketListId
        }
        #expect(defaultAdds.count == 1)
        #expect(defaultAdds.first?.listId == Fixtures.bucketListId)
    }

    @Test func addFails_revertsMapAndSetsError() async throws {
        let svc = MockLocationSavingService()
        svc.saveSpotToListShouldThrow = NSError(domain: "test", code: 99)
        let vm = Fixtures.makeVM(service: svc)
        let placeId = "place-1"
        // Pre-populate so we can assert rollback restores the prior state, not nil.
        vm.spotListTypeMap[placeId] = .starred

        await #expect(throws: Error.self) {
            try await vm.saveSpotToLists(
                spotData: Fixtures.spotData(placeId: placeId),
                listIds: [Fixtures.favoritesId]
            )
        }

        #expect(vm.spotListTypeMap[placeId] == .starred)         // rolled back
        #expect(vm.lastSaveError != nil)
    }

    @Test func partialFailure_keepsAddsAndDoesNotError() async throws {
        // Spot was in favorites originally. User selects bucketList only.
        // Diff: toAdd = bucketList, toRemove = favorites.
        // The remove fails. Save should still be considered successful: the
        // add (bucketList) landed, and the orphaned favorites membership
        // cleans up on next loadSavedPlaces.
        let svc = MockLocationSavingService()
        let placeId = "place-1"
        svc.listsContainingSpot[placeId] = [Fixtures.favoritesId]
        svc.removeSpotFromListShouldThrowOnceForListId = Fixtures.favoritesId
        let vm = Fixtures.makeVM(service: svc)

        try await vm.saveSpotToLists(
            spotData: Fixtures.spotData(placeId: placeId),
            listIds: [Fixtures.bucketListId]
        )

        #expect(vm.spotListTypeMap[placeId] == .bucketList)      // optimistic flip stuck
        #expect(vm.lastSaveError == nil)                         // remove failure is swallowed
        // Add was called, remove was attempted but threw.
        #expect(svc.saveSpotToListCalls.contains { $0.listId == Fixtures.bucketListId })
        #expect(svc.removeSpotFromListCalls.contains { $0.listId == Fixtures.favoritesId })
    }

    @Test func unsave_clearsMap() async throws {
        // Spot is currently in favorites. User clears all selections.
        // Diff: toAdd = [], toRemove = favorites. Map should clear.
        let svc = MockLocationSavingService()
        let placeId = "place-1"
        svc.listsContainingSpot[placeId] = [Fixtures.favoritesId]
        let vm = Fixtures.makeVM(service: svc)
        vm.spotListTypeMap[placeId] = .favorites

        try await vm.saveSpotToLists(
            spotData: Fixtures.spotData(placeId: placeId),
            listIds: []
        )

        #expect(vm.spotListTypeMap[placeId] == nil)
        #expect(svc.removeSpotFromListCalls.contains { $0.listId == Fixtures.favoritesId })
    }

    @Test func concurrentSavesSerialize() async throws {
        // Two rapid saves on the same placeId should NOT both observe the
        // same `prior == nil` baseline. The second one's prior must reflect
        // the first one's flip.
        let svc = MockLocationSavingService()
        let vm = Fixtures.makeVM(service: svc)
        let placeId = "place-1"

        async let first: Void = vm.saveSpotToLists(
            spotData: Fixtures.spotData(placeId: placeId),
            listIds: [Fixtures.favoritesId]
        )
        async let second: Void = vm.saveSpotToLists(
            spotData: Fixtures.spotData(placeId: placeId),
            listIds: [Fixtures.starredId]
        )

        try await first
        try await second

        // The second save should win — final state is .starred, the spot is
        // in the starred list, and is no longer in favorites.
        #expect(vm.spotListTypeMap[placeId] == .starred)
        #expect(svc.listsContainingSpot[placeId]?.contains(Fixtures.starredId) == true)
        #expect(svc.listsContainingSpot[placeId]?.contains(Fixtures.favoritesId) != true)
    }
}

// MARK: - removeSpot

@MainActor
struct RemoveSpotTests {

    @Test func happyPath_clearsMap() async throws {
        let svc = MockLocationSavingService()
        let placeId = "place-1"
        let vm = Fixtures.makeVM(service: svc)
        vm.spotListTypeMap[placeId] = .favorites

        try await vm.removeSpot(placeId: placeId, fromListId: Fixtures.favoritesId)

        #expect(vm.spotListTypeMap[placeId] == nil)
        #expect(vm.lastSaveError == nil)
    }

    @Test func failure_restoresPriorAndSetsError() async throws {
        let svc = MockLocationSavingService()
        svc.removeSpotFromListShouldThrow = NSError(domain: "test", code: 5)
        let placeId = "place-1"
        let vm = Fixtures.makeVM(service: svc)
        vm.spotListTypeMap[placeId] = .favorites

        await #expect(throws: Error.self) {
            try await vm.removeSpot(placeId: placeId, fromListId: Fixtures.favoritesId)
        }

        #expect(vm.spotListTypeMap[placeId] == .favorites)       // restored
        #expect(vm.lastSaveError != nil)
    }
}
