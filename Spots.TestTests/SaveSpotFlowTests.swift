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
    var listsByType: [ListKind: UserList] = [:]
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

    func getListByKind(_ kind: ListKind) async throws -> UserList? {
        return listsByType[kind]
    }

    func getSpotsInList(listId: UUID, kind: ListKind) async throws -> [SpotWithMetadata] {
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
        locality: String?,
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

    var moveSpotCalls: [(placeId: String, from: UUID?, to: UUID?, source: SpotSaveSource)] = []
    /// If set, moveSpotBetweenLists throws this error. Used by the T10
    /// failure-mode test that asserts the VM surfaces the error rather than
    /// silently degrading to a plain add+remove.
    var moveSpotShouldThrow: Error?

    func moveSpotBetweenLists(
        placeId: String,
        fromListId: UUID?,
        toListId: UUID?,
        source: SpotSaveSource
    ) async throws {
        if let err = moveSpotShouldThrow {
            moveSpotCalls.append((placeId, fromListId, toListId, source))
            throw err
        }
        moveSpotCalls.append((placeId, fromListId, toListId, source))
        // Mirror DB state so getListsContainingSpot reflects the move.
        var current = listsContainingSpot[placeId] ?? []
        if let from = fromListId { current.removeAll { $0 == from } }
        if let to = toListId, !current.contains(to) { current.append(to) }
        listsContainingSpot[placeId] = current
    }

    // MARK: - T21 Custom Lists CRUD mocks
    //
    // Configurable: set createListResult / renameListResult / etc. to control
    // what each method returns. Set the corresponding ShouldThrow to make the
    // method throw instead. Call recorders capture inputs for assertions.

    var createListCalls: [(name: String, visibility: ListVisibility, coverEmoji: String?)] = []
    var createListResult: UserList?
    var createListShouldThrow: Error?

    var renameListCalls: [(id: UUID, newName: String)] = []
    var renameListResult: UserList?
    var renameListShouldThrow: Error?

    var setListVisibilityCalls: [(id: UUID, visibility: ListVisibility)] = []
    var setListVisibilityResult: UserList?
    var setListVisibilityShouldThrow: Error?

    var setListCoverEmojiCalls: [(id: UUID, emoji: String?)] = []
    var setListCoverEmojiResult: UserList?
    var setListCoverEmojiShouldThrow: Error?

    var setListCoverImageUrlCalls: [(id: UUID, imageUrl: String?)] = []
    var setListCoverImageUrlResult: UserList?
    var setListCoverImageUrlShouldThrow: Error?

    var setListDescriptionCalls: [(id: UUID, description: String?)] = []
    var setListDescriptionResult: UserList?
    var setListDescriptionShouldThrow: Error?

    var deleteListCalls: [UUID] = []
    var deleteListResult: UserList?
    var deleteListShouldThrow: Error?

    var restoreListCalls: [UUID] = []
    var restoreListResult: UserList?
    var restoreListShouldThrow: Error?

    var getDeletedListsCalls: Int = 0
    var getDeletedListsResult: [DeletedListSummary] = []
    var getDeletedListsShouldThrow: Error?

    func createList(name: String, visibility: ListVisibility, coverEmoji: String?) async throws -> UserList {
        createListCalls.append((name, visibility, coverEmoji))
        if let err = createListShouldThrow { throw err }
        return createListResult ?? UserList(
            id: UUID(), userId: UUID(), kind: .custom,
            name: name, visibility: visibility, coverEmoji: coverEmoji
        )
    }

    func renameList(id: UUID, newName: String) async throws -> UserList {
        renameListCalls.append((id, newName))
        if let err = renameListShouldThrow { throw err }
        return renameListResult ?? UserList(id: id, userId: UUID(), kind: .custom, name: newName)
    }

    func setListVisibility(id: UUID, visibility: ListVisibility) async throws -> UserList {
        setListVisibilityCalls.append((id, visibility))
        if let err = setListVisibilityShouldThrow { throw err }
        return setListVisibilityResult ?? UserList(id: id, userId: UUID(), kind: .custom, name: "List", visibility: visibility)
    }

    func setListCoverEmoji(id: UUID, emoji: String?) async throws -> UserList {
        setListCoverEmojiCalls.append((id, emoji))
        if let err = setListCoverEmojiShouldThrow { throw err }
        return setListCoverEmojiResult ?? UserList(id: id, userId: UUID(), kind: .custom, name: "List", coverEmoji: emoji)
    }

    func setListCoverImageUrl(id: UUID, imageUrl: String?) async throws -> UserList {
        setListCoverImageUrlCalls.append((id, imageUrl))
        if let err = setListCoverImageUrlShouldThrow { throw err }
        return setListCoverImageUrlResult ?? UserList(id: id, userId: UUID(), kind: .custom, name: "List", coverImageUrl: imageUrl)
    }

    func setListDescription(id: UUID, description: String?) async throws -> UserList {
        setListDescriptionCalls.append((id, description))
        if let err = setListDescriptionShouldThrow { throw err }
        return setListDescriptionResult ?? UserList(id: id, userId: UUID(), kind: .custom, name: "List", description: description)
    }

    func deleteList(id: UUID) async throws -> UserList {
        deleteListCalls.append(id)
        if let err = deleteListShouldThrow { throw err }
        return deleteListResult ?? UserList(
            id: id, userId: UUID(), kind: .custom, name: "List",
            deletedAt: Date()
        )
    }

    func restoreList(id: UUID) async throws -> UserList {
        restoreListCalls.append(id)
        if let err = restoreListShouldThrow { throw err }
        return restoreListResult ?? UserList(id: id, userId: UUID(), kind: .custom, name: "List")
    }

    func getDeletedLists() async throws -> [DeletedListSummary] {
        getDeletedListsCalls += 1
        if let err = getDeletedListsShouldThrow { throw err }
        return getDeletedListsResult
    }
}

// MARK: - Fixtures

@MainActor
private struct Fixtures {
    static let userId = UUID()
    static let likedId = UUID()
    static let favoritesId = UUID()
    static let wantToGoId = UUID()
    static let customListId = UUID()

    static let favoritesList = UserList(
        id: likedId, userId: userId, kind: .liked,
        name: nil, createdAt: nil, updatedAt: nil
    )
    static let starredList = UserList(
        id: favoritesId, userId: userId, kind: .favorites,
        name: nil, createdAt: nil, updatedAt: nil
    )
    static let bucketList = UserList(
        id: wantToGoId, userId: userId, kind: .wantToGo,
        name: nil, createdAt: nil, updatedAt: nil
    )
    static let customList = UserList(
        id: customListId, userId: userId, kind: .custom,
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
            [Fixtures.likedId, Fixtures.customListId],
            userLists: Fixtures.allLists
        )
        #expect(result == [Fixtures.likedId, Fixtures.customListId])
    }

    @Test func dropsExtraDefaultsKeepingFavoritesWinner() {
        // T10 (2026-05-26): favorites wins per the flipped priority — the
        // conversion-routing semantic. Before T10, wantToGo silently won
        // here, which is the bug E4 + T10 fix.
        let result = LocationSavingViewModel.coerceToSingleDefault(
            [Fixtures.likedId, Fixtures.favoritesId, Fixtures.wantToGoId],
            userLists: Fixtures.allLists
        )
        #expect(result == [Fixtures.favoritesId])
    }

    @Test func dropsExtraDefaultsKeepingFavoritesOverLiked() {
        let result = LocationSavingViewModel.coerceToSingleDefault(
            [Fixtures.likedId, Fixtures.favoritesId],
            userLists: Fixtures.allLists
        )
        #expect(result == [Fixtures.favoritesId])
    }

    @Test func keepsCustomListAlongsideCoercedDefault() {
        // T10: liked wins over wantToGo (favorites not in selection).
        let result = LocationSavingViewModel.coerceToSingleDefault(
            [Fixtures.likedId, Fixtures.wantToGoId, Fixtures.customListId],
            userLists: Fixtures.allLists
        )
        #expect(result == [Fixtures.likedId, Fixtures.customListId])
    }

    @Test func dropsWantToGoWhenFavoritesAlsoSelected_T10Conversion() {
        // The canonical T10 conversion-detection shape at the coerce layer:
        // user has spot in Want-to-Go, opens picker (WTG shown checked),
        // checks Favorites. selected = {WTG, Favorites}. After T10, the
        // coercion drops WTG so the diff against `original = {WTG}` becomes
        // toAdd={Favorites}, toRemove={WTG} — the pattern the routing
        // pre-pass recognises as a conversion.
        let result = LocationSavingViewModel.coerceToSingleDefault(
            [Fixtures.wantToGoId, Fixtures.favoritesId],
            userLists: Fixtures.allLists
        )
        #expect(result == [Fixtures.favoritesId])
    }

    @Test func dropsWantToGoWhenLikedAlsoSelected_T10Conversion() {
        let result = LocationSavingViewModel.coerceToSingleDefault(
            [Fixtures.wantToGoId, Fixtures.likedId],
            userLists: Fixtures.allLists
        )
        #expect(result == [Fixtures.likedId])
    }
}

// MARK: - kind helper

@MainActor
struct ListTypeHelperTests {
    @Test func returnsNilWhenNoDefaultSelected() {
        let result = LocationSavingViewModel.kind(
            for: [Fixtures.customListId],
            userLists: Fixtures.allLists
        )
        #expect(result == nil)
    }

    @Test func returnsTheDefaultListTypeWhenOneSelected() {
        let result = LocationSavingViewModel.kind(
            for: [Fixtures.likedId],
            userLists: Fixtures.allLists
        )
        #expect(result == .liked)
    }
}

// MARK: - saveSpotToLists

@MainActor
struct SaveSpotToListsTests {

    @Test func singleDefaultListSelected_setsListType() async throws {
        let svc = MockLocationSavingService()
        let vm = Fixtures.makeVM(service: svc)
        let placeId = "place-1"

        try await vm.saveSpotToLists(spotData: Fixtures.spotData(placeId: placeId), listIds: [Fixtures.likedId])

        #expect(vm.spotListKindMap[placeId] == .liked)
        #expect(svc.saveSpotToListCalls.contains(where: { $0.listId == Fixtures.likedId }))
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
            listIds: [Fixtures.likedId, Fixtures.wantToGoId]
        )

        // T10 (2026-05-26): liked wins over wantToGo per the flipped
        // priority (favorites not in selection). Optimistic map reflects
        // the winner.
        #expect(vm.spotListKindMap[placeId] == .liked)
        // Only one default add hits the service.
        let defaultAdds = svc.saveSpotToListCalls.filter { call in
            call.listId == Fixtures.likedId || call.listId == Fixtures.wantToGoId
        }
        #expect(defaultAdds.count == 1)
        #expect(defaultAdds.first?.listId == Fixtures.likedId)
    }

    @Test func addFails_revertsMapAndSetsError() async throws {
        let svc = MockLocationSavingService()
        svc.saveSpotToListShouldThrow = NSError(domain: "test", code: 99)
        let vm = Fixtures.makeVM(service: svc)
        let placeId = "place-1"
        // Pre-populate so we can assert rollback restores the prior state, not nil.
        vm.spotListKindMap[placeId] = .favorites

        await #expect(throws: Error.self) {
            try await vm.saveSpotToLists(
                spotData: Fixtures.spotData(placeId: placeId),
                listIds: [Fixtures.likedId]
            )
        }

        #expect(vm.spotListKindMap[placeId] == .favorites)         // rolled back
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
        svc.listsContainingSpot[placeId] = [Fixtures.likedId]
        svc.removeSpotFromListShouldThrowOnceForListId = Fixtures.likedId
        let vm = Fixtures.makeVM(service: svc)

        try await vm.saveSpotToLists(
            spotData: Fixtures.spotData(placeId: placeId),
            listIds: [Fixtures.wantToGoId]
        )

        #expect(vm.spotListKindMap[placeId] == .wantToGo)      // optimistic flip stuck
        #expect(vm.lastSaveError == nil)                         // remove failure is swallowed
        // Add was called, remove was attempted but threw.
        #expect(svc.saveSpotToListCalls.contains { $0.listId == Fixtures.wantToGoId })
        #expect(svc.removeSpotFromListCalls.contains { $0.listId == Fixtures.likedId })
    }

    @Test func unsave_clearsMap() async throws {
        // Spot is currently in favorites. User clears all selections.
        // Diff: toAdd = [], toRemove = favorites. Map should clear.
        let svc = MockLocationSavingService()
        let placeId = "place-1"
        svc.listsContainingSpot[placeId] = [Fixtures.likedId]
        let vm = Fixtures.makeVM(service: svc)
        vm.spotListKindMap[placeId] = .liked

        try await vm.saveSpotToLists(
            spotData: Fixtures.spotData(placeId: placeId),
            listIds: []
        )

        #expect(vm.spotListKindMap[placeId] == nil)
        #expect(svc.removeSpotFromListCalls.contains { $0.listId == Fixtures.likedId })
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
            listIds: [Fixtures.likedId]
        )
        async let second: Void = vm.saveSpotToLists(
            spotData: Fixtures.spotData(placeId: placeId),
            listIds: [Fixtures.favoritesId]
        )

        try await first
        try await second

        // The second save should win — final state is .favorites, the spot is
        // in the starred list, and is no longer in favorites.
        #expect(vm.spotListKindMap[placeId] == .favorites)
        #expect(svc.listsContainingSpot[placeId]?.contains(Fixtures.favoritesId) == true)
        #expect(svc.listsContainingSpot[placeId]?.contains(Fixtures.likedId) != true)
    }
}

// MARK: - removeSpot

@MainActor
struct RemoveSpotTests {

    @Test func happyPath_clearsMap() async throws {
        let svc = MockLocationSavingService()
        let placeId = "place-1"
        let vm = Fixtures.makeVM(service: svc)
        vm.spotListKindMap[placeId] = .liked

        try await vm.removeSpot(placeId: placeId, fromListId: Fixtures.likedId)

        #expect(vm.spotListKindMap[placeId] == nil)
        #expect(vm.lastSaveError == nil)
    }

    @Test func failure_restoresPriorAndSetsError() async throws {
        let svc = MockLocationSavingService()
        svc.removeSpotFromListShouldThrow = NSError(domain: "test", code: 5)
        let placeId = "place-1"
        let vm = Fixtures.makeVM(service: svc)
        vm.spotListKindMap[placeId] = .liked

        await #expect(throws: Error.self) {
            try await vm.removeSpot(placeId: placeId, fromListId: Fixtures.likedId)
        }

        #expect(vm.spotListKindMap[placeId] == .liked)       // restored
        #expect(vm.lastSaveError != nil)
    }
}

// MARK: - T10: detectWantToGoConversion (pure helper)
//
// Pure-function tests for the conversion-detection helper added in T10
// Phase A. No async, no mocks — just the routing decision logic.

@MainActor
struct DetectWantToGoConversionTests {

    @Test func returnsNilWhenNoWantToGoInRemove() {
        // toAdd has Favorites but no Want-to-Go in toRemove.
        let result = LocationSavingViewModel.detectWantToGoConversion(
            toAdd: [Fixtures.favoritesId],
            toRemove: [Fixtures.customListId],
            userLists: Fixtures.allLists
        )
        #expect(result == nil)
    }

    @Test func returnsNilWhenNoVisitedKindInAdd() {
        // Want-to-Go in toRemove, but only a custom list is being added.
        // That's a non-conversion remove → plain remove path.
        let result = LocationSavingViewModel.detectWantToGoConversion(
            toAdd: [Fixtures.customListId],
            toRemove: [Fixtures.wantToGoId],
            userLists: Fixtures.allLists
        )
        #expect(result == nil)
    }

    @Test func detectsWantToGoToFavorites() {
        let result = LocationSavingViewModel.detectWantToGoConversion(
            toAdd: [Fixtures.favoritesId],
            toRemove: [Fixtures.wantToGoId],
            userLists: Fixtures.allLists
        )
        #expect(result?.fromListId == Fixtures.wantToGoId)
        #expect(result?.toListId == Fixtures.favoritesId)
        #expect(result?.toKind == .favorites)
    }

    @Test func detectsWantToGoToLiked() {
        let result = LocationSavingViewModel.detectWantToGoConversion(
            toAdd: [Fixtures.likedId],
            toRemove: [Fixtures.wantToGoId],
            userLists: Fixtures.allLists
        )
        #expect(result?.fromListId == Fixtures.wantToGoId)
        #expect(result?.toListId == Fixtures.likedId)
        #expect(result?.toKind == .liked)
    }

    @Test func prefersFavoritesOverLikedAsTieBreaker() {
        // Both Favorites and Liked in toAdd — Favorites wins.
        let result = LocationSavingViewModel.detectWantToGoConversion(
            toAdd: [Fixtures.favoritesId, Fixtures.likedId],
            toRemove: [Fixtures.wantToGoId],
            userLists: Fixtures.allLists
        )
        #expect(result?.toListId == Fixtures.favoritesId)
        #expect(result?.toKind == .favorites)
    }

    @Test func ignoresCustomListAddsAlongsideConversion() {
        // Custom list also in toAdd. Detection still finds the conversion;
        // the custom list will be handled by the residual ADD loop.
        let result = LocationSavingViewModel.detectWantToGoConversion(
            toAdd: [Fixtures.favoritesId, Fixtures.customListId],
            toRemove: [Fixtures.wantToGoId],
            userLists: Fixtures.allLists
        )
        #expect(result?.toListId == Fixtures.favoritesId)
    }
}

// MARK: - T10: saveSpotToLists routing through moveSpotBetweenLists
//
// VM-level tests for the conversion routing pre-pass added in
// `_saveSpotToListsImpl`. The mock service records `moveSpotBetweenLists`
// calls so we can assert (1) the right RPC fires with the right params,
// (2) the conversion is NOT double-issued via the add+remove loops,
// (3) errors surface to the VM.

@MainActor
struct T10ConversionRoutingTests {

    @Test func wantToGoToFavorites_routesThroughMoveRPC() async throws {
        // Spot is currently in Want-to-Go. User checks Favorites.
        // After coerceToSingleDefault (favorites wins), the diff is
        // toAdd={Favorites}, toRemove={WTG}. The pre-pass should rewrite
        // that into ONE moveSpotBetweenLists call — NOT a save+remove pair.
        let svc = MockLocationSavingService()
        let placeId = "place-1"
        svc.listsContainingSpot[placeId] = [Fixtures.wantToGoId]
        let vm = Fixtures.makeVM(service: svc)

        try await vm.saveSpotToLists(
            spotData: Fixtures.spotData(placeId: placeId),
            listIds: [Fixtures.favoritesId]
        )

        // Exactly one move call with the right params.
        #expect(svc.moveSpotCalls.count == 1)
        let move = svc.moveSpotCalls.first
        #expect(move?.placeId == placeId)
        #expect(move?.from == Fixtures.wantToGoId)
        #expect(move?.to == Fixtures.favoritesId)
        #expect(move?.source == .manual)

        // No parallel saveSpotToList(Favorites) — the move owns that add.
        #expect(svc.saveSpotToListCalls.contains { $0.listId == Fixtures.favoritesId } == false)
        // No parallel removeSpotFromList(WTG) — the move owns that remove.
        #expect(svc.removeSpotFromListCalls.contains { $0.listId == Fixtures.wantToGoId } == false)

        // Optimistic map flipped to favorites.
        #expect(vm.spotListKindMap[placeId] == .favorites)
        #expect(vm.lastSaveError == nil)
    }

    @Test func wantToGoToLiked_routesThroughMoveRPC() async throws {
        let svc = MockLocationSavingService()
        let placeId = "place-1"
        svc.listsContainingSpot[placeId] = [Fixtures.wantToGoId]
        let vm = Fixtures.makeVM(service: svc)

        try await vm.saveSpotToLists(
            spotData: Fixtures.spotData(placeId: placeId),
            listIds: [Fixtures.likedId]
        )

        #expect(svc.moveSpotCalls.count == 1)
        #expect(svc.moveSpotCalls.first?.to == Fixtures.likedId)
        #expect(vm.spotListKindMap[placeId] == .liked)
    }

    @Test func conversionAlongsideCustomList_movesAndAddsBoth() async throws {
        // Spot in Want-to-Go. User checks Favorites AND a custom list.
        // The conversion routes through move RPC; the custom list addition
        // still flows through the residual ADD loop.
        let svc = MockLocationSavingService()
        let placeId = "place-1"
        svc.listsContainingSpot[placeId] = [Fixtures.wantToGoId]
        let vm = Fixtures.makeVM(service: svc)

        try await vm.saveSpotToLists(
            spotData: Fixtures.spotData(placeId: placeId),
            listIds: [Fixtures.favoritesId, Fixtures.customListId]
        )

        // One move (for the conversion pair).
        #expect(svc.moveSpotCalls.count == 1)
        #expect(svc.moveSpotCalls.first?.to == Fixtures.favoritesId)
        // One plain add (for the custom list).
        #expect(svc.saveSpotToListCalls.contains { $0.listId == Fixtures.customListId })
        // No double-issue: Favorites wasn't also added via saveSpotToList.
        #expect(svc.saveSpotToListCalls.contains { $0.listId == Fixtures.favoritesId } == false)
    }

    @Test func directAddToFavorites_doesNotRoute() async throws {
        // Spot has no prior Want-to-Go membership. User adds to Favorites.
        // Diff: toAdd={Favorites}, toRemove={}. Not a conversion shape.
        // Path: plain saveSpotToList(Favorites). The visited feed activity
        // for this case is generated server-side by the feed RPC's dedupe
        // logic — NOT by a list_moves row (correct per T10-D2).
        let svc = MockLocationSavingService()
        let placeId = "place-1"
        let vm = Fixtures.makeVM(service: svc)

        try await vm.saveSpotToLists(
            spotData: Fixtures.spotData(placeId: placeId),
            listIds: [Fixtures.favoritesId]
        )

        #expect(svc.moveSpotCalls.isEmpty)
        #expect(svc.saveSpotToListCalls.contains { $0.listId == Fixtures.favoritesId })
    }

    @Test func moveRPCFailure_surfacesErrorAndRollsBack() async throws {
        // The move RPC throws (e.g. network drop, RLS rejection). The VM
        // must surface the error AND roll back the optimistic spotListKindMap
        // to its prior value — NOT silently degrade to a plain add+remove.
        let svc = MockLocationSavingService()
        svc.moveSpotShouldThrow = NSError(domain: "test", code: 42)
        let placeId = "place-1"
        svc.listsContainingSpot[placeId] = [Fixtures.wantToGoId]
        let vm = Fixtures.makeVM(service: svc)
        // Prior optimistic value reflects the spot being in WTG.
        vm.spotListKindMap[placeId] = .wantToGo

        await #expect(throws: Error.self) {
            try await vm.saveSpotToLists(
                spotData: Fixtures.spotData(placeId: placeId),
                listIds: [Fixtures.favoritesId]
            )
        }

        // Map rolled back to prior (.wantToGo, not nil and not .favorites).
        #expect(vm.spotListKindMap[placeId] == .wantToGo)
        #expect(vm.lastSaveError != nil)

        // The move was attempted (and threw).
        #expect(svc.moveSpotCalls.count == 1)
        // Critical: no fallback add+remove happened. The save fully aborted.
        #expect(svc.saveSpotToListCalls.contains { $0.listId == Fixtures.favoritesId } == false)
        #expect(svc.removeSpotFromListCalls.contains { $0.listId == Fixtures.wantToGoId } == false)
    }

    // MARK: - TODO: server-side dedupe tests (require real Supabase scaffolding)
    //
    // Two acceptance criteria from the T10 plan still need coverage:
    //
    //   1. testConversion_directAddToFavorites_emitsNoMoveRow
    //      Direct add to Favorites (no prior WTG) → assert no list_moves
    //      row is written. The visited feed activity should still surface
    //      via get_following_feed dedupe. Requires real DB.
    //
    //   2. testConversion_dedupeAcrossReAdd
    //      Add → remove → re-add → assert get_following_feed returns
    //      exactly ONE visited activity for the (user, spot) pair.
    //      Requires real DB.
    //
    // The codebase doesn't currently have a Supabase-integration test
    // harness — `MockLocationSavingService` mocks at the protocol layer and
    // doesn't touch SQL. Wiring up integration tests would add real value
    // here (and unlock similar coverage for other DB-touching features),
    // but is out of scope for T10 itself. Track in TODOS.md.
}
