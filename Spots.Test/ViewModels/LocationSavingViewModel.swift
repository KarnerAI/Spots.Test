//
//  LocationSavingViewModel.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//
//  Owns saved-places state for the whole app: which spots the current user has
//  saved, which list each one lives in, and the optimistic-update / rollback
//  machinery for the save flow. MapViewModel and the Newsfeed both read from
//  this VM so the bookmark/list icon stays in sync across tabs.
//
//  Save flow (see saveSpotToLists):
//
//    user picks lists → coerceToSingleDefault (radio across .favorites / .starred / .bucketList)
//      → optimistic spotListTypeMap[placeId] = listType for new default
//      → ADD to new lists (if any add fails → throw → rollback)
//      → REMOVE from de-selected lists (best-effort; failures don't roll back the add)
//
//  Concurrency: per-placeId in-flight Tasks serialize calls so two rapid taps
//  on the same spot can't snapshot the same stale `prior` state.
//

import Foundation
import SwiftUI

@MainActor
class LocationSavingViewModel: ObservableObject {
    @Published var userLists: [UserList] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    // MARK: - Saved-places state (lifted from MapViewModel)
    @Published var savedPlaces: [SpotWithMetadata] = []
    @Published var spotListTypeMap: [String: ListType] = [:]
    @Published var hasLoadedSavedPlacesOnce: Bool = false

    /// Drives a transient toast at the app root when an optimistic save/remove
    /// fails. Read by MainTabView's overlay; cleared after display.
    @Published var lastSaveError: String?

    private let service: LocationSavingServiceProtocol
    private var userListsLastLoadedAt: Date?
    private let userListsStaleInterval: TimeInterval = 30
    private var savedPlacesLastLoadedAt: Date?
    private let savedPlacesStaleInterval: TimeInterval = 30

    /// In-flight save/remove Tasks keyed by placeId. Serializes mutations so
    /// concurrent calls for the same spot observe each other's results — the
    /// second tap's `prior` snapshot reflects the first tap's outcome instead
    /// of a stale baseline.
    private var inflightTasks: [String: Task<Void, Error>] = [:]

    init(service: LocationSavingServiceProtocol = LocationSavingService.shared) {
        self.service = service
    }

    // MARK: - Load Lists

    func loadUserLists(forceRefresh: Bool = false) async {
        if !forceRefresh, let last = userListsLastLoadedAt,
           Date().timeIntervalSince(last) < userListsStaleInterval {
            return
        }
        isLoading = true
        errorMessage = nil

        do {
            userLists = try await service.getUserLists()
            userListsLastLoadedAt = Date()
        } catch {
            errorMessage = "Failed to load lists: \(error.localizedDescription)"
            print("Error loading lists: \(error)")
        }

        isLoading = false
    }

    // MARK: - Load Saved Places
    //
    // Pulls every spot in the three default lists, dedupes by placeId merging
    // listTypes sets, then computes spotListTypeMap via the priority resolver
    // (bucketList > starred > favorites). Lifted from MapViewModel so both
    // Explore (map markers) and Newsfeed (per-card icon) read one truth.

    func loadSavedPlaces(forceRefresh: Bool = false) async {
        if !forceRefresh, hasLoadedSavedPlacesOnce, let last = savedPlacesLastLoadedAt,
           Date().timeIntervalSince(last) < savedPlacesStaleInterval {
            return
        }

        do {
            let starredList = try await service.getListByType(.starred)
            let favoritesList = try await service.getListByType(.favorites)
            let bucketList = try await service.getListByType(.bucketList)

            var allPlaces: [SpotWithMetadata] = []

            if let starredId = starredList?.id {
                let starredPlaces = try await service.getSpotsInList(listId: starredId, listType: .starred)
                allPlaces.append(contentsOf: starredPlaces)
            }
            if let favoritesId = favoritesList?.id {
                let favoritesPlaces = try await service.getSpotsInList(listId: favoritesId, listType: .favorites)
                allPlaces.append(contentsOf: favoritesPlaces)
            }
            if let bucketId = bucketList?.id {
                let bucketPlaces = try await service.getSpotsInList(listId: bucketId, listType: .bucketList)
                allPlaces.append(contentsOf: bucketPlaces)
            }

            // Aggregate by placeId — merge listTypes sets, keep most-recent savedAt.
            var uniquePlaces: [String: SpotWithMetadata] = [:]
            for place in allPlaces {
                if let existing = uniquePlaces[place.spot.placeId] {
                    let mergedListTypes = existing.listTypes.union(place.listTypes)
                    let mostRecentSavedAt = max(existing.savedAt, place.savedAt)
                    uniquePlaces[place.spot.placeId] = SpotWithMetadata(
                        spot: existing.spot,
                        savedAt: mostRecentSavedAt,
                        listTypes: mergedListTypes
                    )
                } else {
                    uniquePlaces[place.spot.placeId] = place
                }
            }

            savedPlaces = Array(uniquePlaces.values)

            // O(1) lookup map for cards: placeId → display ListType (priority resolver).
            spotListTypeMap = Dictionary(uniqueKeysWithValues:
                savedPlaces.compactMap { spot in
                    guard let listType = displayListType(for: spot.listTypes) else { return nil }
                    return (spot.spot.placeId, listType)
                }
            )

            hasLoadedSavedPlacesOnce = true
            savedPlacesLastLoadedAt = Date()

        } catch {
            print("Error loading saved places: \(error)")
        }
    }

    // MARK: - Save Spot (single list — internal helper, also used by saveSpotToLists)

    func saveSpot(
        placeId: String,
        name: String,
        address: String?,
        city: String? = nil,
        country: String? = nil,
        latitude: Double?,
        longitude: Double?,
        types: [String]?,
        photoUrl: String? = nil,
        photoReference: String? = nil,
        rating: Double? = nil,
        toListId: UUID
    ) async throws {
        // #region agent log
        DebugLogger.log(
            runId: "pre-fix",
            hypothesisId: "H2",
            location: "LocationSavingViewModel.saveSpot:entry",
            message: "Save spot requested",
            data: [
                "placeId": placeId,
                "listId": toListId.uuidString,
                "hasLatitude": latitude != nil,
                "hasLongitude": longitude != nil,
                "hasTypes": types != nil
            ]
        )
        // #endregion

        isSaving = true
        defer { isSaving = false }

        // If the caller doesn't already have country/rating (or any of the
        // other display fields the new feed hero card needs), fetch Place
        // Details once and merge in. This keeps the spots row fully populated
        // on first write so feed-time enrichment is only a fallback for legacy
        // rows. fetchPlaceDetails is cache-backed; subsequent saves of the same
        // placeId in this session don't pay the API cost.
        var resolvedCity = city
        var resolvedCountry = country
        var resolvedTypes = types
        var resolvedPhotoUrl = photoUrl
        var resolvedPhotoReference = photoReference
        var resolvedRating = rating

        let needsDetails = (resolvedCountry?.isEmpty ?? true)
            || (resolvedRating == nil)
            || (resolvedCity?.isEmpty ?? true)
            || (resolvedTypes?.isEmpty ?? true)
        if needsDetails {
            if let details = try? await PlacesAPIService.shared.fetchPlaceDetails(placeId: placeId) {
                if (resolvedCity?.isEmpty ?? true) { resolvedCity = details.city }
                if (resolvedCountry?.isEmpty ?? true) { resolvedCountry = details.country }
                if (resolvedTypes?.isEmpty ?? true), !details.category.isEmpty {
                    resolvedTypes = [details.category.lowercased().replacingOccurrences(of: " ", with: "_")]
                }
                if (resolvedPhotoUrl?.isEmpty ?? true) { resolvedPhotoUrl = details.photoUrl }
                if (resolvedPhotoReference?.isEmpty ?? true) { resolvedPhotoReference = details.photoReference }
                if resolvedRating == nil { resolvedRating = details.rating }
            }
        }

        try await service.upsertSpot(
            placeId: placeId,
            name: name,
            address: address,
            city: resolvedCity,
            country: resolvedCountry,
            latitude: latitude,
            longitude: longitude,
            types: resolvedTypes,
            photoUrl: resolvedPhotoUrl,
            photoReference: resolvedPhotoReference,
            rating: resolvedRating
        )

        try await service.saveSpotToList(placeId: placeId, listId: toListId)

        // #region agent log
        DebugLogger.log(
            runId: "pre-fix",
            hypothesisId: "H2",
            location: "LocationSavingViewModel.saveSpot:success",
            message: "Save spot completed",
            data: [
                "placeId": placeId,
                "listId": toListId.uuidString
            ]
        )
        // #endregion
    }

    // MARK: - Remove Spot (with optimistic clear + rollback)

    func removeSpot(placeId: String, fromListId: UUID) async throws {
        try await runSerialized(forPlaceId: placeId) { [weak self] in
            guard let self else { return }
            let prior = self.spotListTypeMap[placeId]
            self.spotListTypeMap[placeId] = nil
            do {
                try await self.service.removeSpotFromList(placeId: placeId, listId: fromListId)
            } catch {
                self.spotListTypeMap[placeId] = prior
                self.lastSaveError = "Couldn't remove. Try again."
                throw error
            }
        }
    }

    // MARK: - Get Spots in List

    func getSpotsInList(listId: UUID, listType: ListType) async throws -> [SpotWithMetadata] {
        return try await service.getSpotsInList(listId: listId, listType: listType)
    }

    // MARK: - Get Spot Count

    func getSpotCount(listId: UUID) async throws -> Int {
        return try await service.getSpotCount(listId: listId)
    }

    // MARK: - Check Lists

    func getListsContainingSpot(placeId: String) async throws -> [UUID] {
        return try await service.getListsContainingSpot(placeId: placeId)
    }

    // MARK: - Save to multiple lists (optimistic + single-default coercion)
    //
    //   incoming selection
    //         │
    //         ▼
    //   coerceToSingleDefault (drop extras across .favorites/.starred/.bucketList,
    //                          keep at most one default; user-created lists pass through)
    //         │
    //         ▼
    //   snapshot prior spotListTypeMap[placeId]
    //   optimistic spotListTypeMap[placeId] = listType for new single default (or nil)
    //         │
    //         ▼
    //   diff(coerced, original) → toAdd, toRemove
    //   add-first ordering: each add throws on failure → rollback + lastSaveError
    //         │
    //         ▼
    //   removes are best-effort (try?) — failed remove leaves spot saved in
    //   the old list, recoverable by next loadSavedPlaces. Save itself is
    //   considered successful, so no rollback or error toast.
    //
    func saveSpotToLists(spotData: PlaceAutocompleteResult, listIds: Set<UUID>) async throws {
        try await runSerialized(forPlaceId: spotData.placeId) { [weak self] in
            guard let self else { return }
            try await self._saveSpotToListsImpl(spotData: spotData, listIds: listIds)
        }
    }

    private func _saveSpotToListsImpl(spotData: PlaceAutocompleteResult, listIds: Set<UUID>) async throws {
        let coerced = Self.coerceToSingleDefault(listIds, userLists: userLists)
        let placeId = spotData.placeId

        let prior = spotListTypeMap[placeId]
        let newListType = Self.listType(for: coerced, userLists: userLists)
        spotListTypeMap[placeId] = newListType

        do {
            let original = Set(try await service.getListsContainingSpot(placeId: placeId))
            let diff = ListSaveDiff(selected: coerced, original: original)

            // ADD first — never lose a save. If any add throws, rollback.
            for id in diff.toAdd {
                try await saveSpot(
                    placeId: spotData.placeId,
                    name: spotData.name,
                    address: spotData.address,
                    city: spotData.city,
                    latitude: spotData.coordinate?.latitude,
                    longitude: spotData.coordinate?.longitude,
                    types: spotData.types,
                    photoUrl: spotData.photoUrl,
                    photoReference: spotData.photoReference,
                    toListId: id
                )
            }
            // REMOVE second — best-effort. A partial failure here leaves the
            // spot in a stale list, recoverable on next loadSavedPlaces. The
            // save still counts as successful from the user's perspective.
            for id in diff.toRemove {
                try? await service.removeSpotFromList(placeId: spotData.placeId, listId: id)
            }
        } catch {
            spotListTypeMap[placeId] = prior
            lastSaveError = "Couldn't save. Try again."
            throw error
        }
    }

    /// Pure diff calculation. Public for unit testing.
    struct ListSaveDiff: Equatable {
        let toAdd: Set<UUID>
        let toRemove: Set<UUID>

        init(selected: Set<UUID>, original: Set<UUID>) {
            self.toAdd = selected.subtracting(original)
            self.toRemove = original.subtracting(selected)
        }
    }

    // MARK: - Single-default coercion (pure helpers, exposed for testing)

    /// If the input contains more than one of the three default lists
    /// (.favorites / .starred / .bucketList), drop the extras and keep one
    /// using the same priority order as `displayListType` (bucketList wins,
    /// then starred, then favorites). User-created lists always pass through.
    /// Defensive — the picker UI prevents users from selecting >1 default,
    /// but this guarantees the invariant for non-UI callers (share extension,
    /// deep links, tests).
    static func coerceToSingleDefault(
        _ selected: Set<UUID>,
        userLists: [UserList]
    ) -> Set<UUID> {
        let defaultListsInSelection = userLists.filter { list in
            list.listType != nil && selected.contains(list.id)
        }
        guard defaultListsInSelection.count > 1 else { return selected }

        // Pick the canonical default by priority.
        let priorityOrder: [ListType] = [.bucketList, .starred, .favorites]
        var winner: UserList?
        for type in priorityOrder {
            if let match = defaultListsInSelection.first(where: { $0.listType == type }) {
                winner = match
                break
            }
        }

        var coerced = selected
        for list in defaultListsInSelection where list.id != winner?.id {
            coerced.remove(list.id)
        }
        return coerced
    }

    /// Returns the `ListType` of the single default list in `selected`, or nil
    /// if no default list is selected. Assumes input has already passed
    /// through `coerceToSingleDefault` so at most one default is present.
    static func listType(for selected: Set<UUID>, userLists: [UserList]) -> ListType? {
        for list in userLists {
            if let type = list.listType, selected.contains(list.id) {
                return type
            }
        }
        return nil
    }

    // MARK: - Per-placeId serialization

    /// Serializes mutations on the same placeId. If a Task is in-flight for
    /// this placeId, the new caller awaits it (treating any thrown error as
    /// "the predecessor failed, but my own work is independent") then runs.
    private func runSerialized(
        forPlaceId placeId: String,
        body: @escaping () async throws -> Void
    ) async throws {
        if let inflight = inflightTasks[placeId] {
            // Wait for the predecessor; ignore its error — we'll run anyway.
            _ = try? await inflight.value
        }
        let task = Task { try await body() }
        inflightTasks[placeId] = task
        defer { inflightTasks[placeId] = nil }
        try await task.value
    }

    // MARK: - Parallel count load

    func getSpotCounts(listIds: [UUID]) async -> [UUID: Int] {
        await withTaskGroup(of: (UUID, Int).self) { group in
            for id in listIds {
                group.addTask { [service] in
                    let count = (try? await service.getSpotCount(listId: id)) ?? 0
                    return (id, count)
                }
            }
            var result: [UUID: Int] = [:]
            for await (id, count) in group { result[id] = count }
            return result
        }
    }
}
