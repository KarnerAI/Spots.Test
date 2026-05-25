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
//    user picks lists → coerceToSingleDefault (radio across .liked / .favorites / .wantToGo)
//      → optimistic spotListKindMap[placeId] = kind for new default
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
    @Published var spotListKindMap: [String: ListKind] = [:]
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

    // MARK: - Custom Lists CRUD (T21)
    //
    // All methods are optimistic where it's safe: createList appends on success,
    // deleteList removes from userLists on success (rolls back on failure), and
    // the field-updating methods (rename / setVisibility / setCoverEmoji /
    // setCoverImageUrl) replace the row in-place on success.
    //
    // Views call these via @EnvironmentObject locationSavingVM. Errors surface
    // through errorMessage so the caller can show a toast or inline error.

    /// Create a new custom list. Appends to `userLists` on success and returns
    /// the inserted row so the caller (CreateListView) can dismiss + scroll the
    /// new list into view.
    func createList(
        name: String,
        visibility: ListVisibility = .private,
        coverEmoji: String? = nil
    ) async throws -> UserList {
        let inserted = try await service.createList(
            name: name,
            visibility: visibility,
            coverEmoji: coverEmoji
        )
        userLists.append(inserted)
        userListsLastLoadedAt = Date()
        return inserted
    }

    /// Rename a list. Replaces the row in-place on success.
    func renameList(id: UUID, newName: String) async throws -> UserList {
        let updated = try await service.renameList(id: id, newName: newName)
        replaceList(updated)
        return updated
    }

    /// Change visibility (private / shared / public). Replaces the row in-place.
    func setListVisibility(id: UUID, visibility: ListVisibility) async throws -> UserList {
        let updated = try await service.setListVisibility(id: id, visibility: visibility)
        replaceList(updated)
        return updated
    }

    /// Set the emoji shown when the list has no auto-cover photo. Pass nil to clear.
    func setListCoverEmoji(id: UUID, emoji: String?) async throws -> UserList {
        let updated = try await service.setListCoverEmoji(id: id, emoji: emoji)
        replaceList(updated)
        return updated
    }

    /// Override the auto-cover with a specific image URL. Pass nil to clear the
    /// override and resume auto-cover from the most-recent spot.
    func setListCoverImageUrl(id: UUID, imageUrl: String?) async throws -> UserList {
        let updated = try await service.setListCoverImageUrl(id: id, imageUrl: imageUrl)
        replaceList(updated)
        return updated
    }

    /// Soft-delete a custom list. Removes optimistically from `userLists`,
    /// rolls back on failure (e.g. RLS rejects deleting a default list).
    /// Returns the tombstoned row so the caller can show "Undo" / restore copy.
    @discardableResult
    func deleteList(id: UUID) async throws -> UserList {
        let priorIndex = userLists.firstIndex(where: { $0.id == id })
        let priorList = priorIndex.map { userLists[$0] }

        // Optimistic remove
        if let idx = priorIndex {
            userLists.remove(at: idx)
        }

        do {
            let tombstoned = try await service.deleteList(id: id)
            userListsLastLoadedAt = Date()
            return tombstoned
        } catch {
            // Roll back the optimistic remove
            if let idx = priorIndex, let prior = priorList {
                userLists.insert(prior, at: min(idx, userLists.count))
            }
            throw error
        }
    }

    /// Restore a soft-deleted list within the 30-day window. Re-inserts the
    /// restored row into `userLists` on success.
    @discardableResult
    func restoreList(id: UUID) async throws -> UserList {
        let restored = try await service.restoreList(id: id)
        // Avoid double-inserting if already present (e.g. concurrent refresh).
        if !userLists.contains(where: { $0.id == restored.id }) {
            userLists.append(restored)
        }
        userListsLastLoadedAt = Date()
        return restored
    }

    /// Fetch tombstoned lists within the 30-day recovery window. Powers the
    /// "Recently deleted" section in Settings. Does not mutate userLists.
    func getDeletedLists() async throws -> [DeletedListSummary] {
        try await service.getDeletedLists()
    }

    /// Replace a list in `userLists` by id. No-op if the id isn't present.
    private func replaceList(_ list: UserList) {
        if let idx = userLists.firstIndex(where: { $0.id == list.id }) {
            userLists[idx] = list
        }
    }

    // MARK: - Load Saved Places
    //
    // Pulls every spot in the three default lists, dedupes by placeId merging
    // listKinds sets, then computes spotListKindMap via the priority resolver
    // (bucketList > starred > favorites). Lifted from MapViewModel so both
    // Explore (map markers) and Newsfeed (per-card icon) read one truth.

    func loadSavedPlaces(forceRefresh: Bool = false) async {
        if !forceRefresh, hasLoadedSavedPlacesOnce, let last = savedPlacesLastLoadedAt,
           Date().timeIntervalSince(last) < savedPlacesStaleInterval {
            return
        }

        do {
            let starredList = try await service.getListByKind(.favorites)
            let favoritesList = try await service.getListByKind(.liked)
            let bucketList = try await service.getListByKind(.wantToGo)

            var allPlaces: [SpotWithMetadata] = []

            if let starredId = starredList?.id {
                let starredPlaces = try await service.getSpotsInList(listId: starredId, kind: .favorites)
                allPlaces.append(contentsOf: starredPlaces)
            }
            if let favoritesId = favoritesList?.id {
                let favoritesPlaces = try await service.getSpotsInList(listId: favoritesId, kind: .liked)
                allPlaces.append(contentsOf: favoritesPlaces)
            }
            if let bucketId = bucketList?.id {
                let bucketPlaces = try await service.getSpotsInList(listId: bucketId, kind: .wantToGo)
                allPlaces.append(contentsOf: bucketPlaces)
            }

            // Aggregate by placeId — merge listKinds sets, keep most-recent savedAt.
            var uniquePlaces: [String: SpotWithMetadata] = [:]
            for place in allPlaces {
                if let existing = uniquePlaces[place.spot.placeId] {
                    let mergedListTypes = existing.listKinds.union(place.listKinds)
                    let mostRecentSavedAt = max(existing.savedAt, place.savedAt)
                    uniquePlaces[place.spot.placeId] = SpotWithMetadata(
                        spot: existing.spot,
                        savedAt: mostRecentSavedAt,
                        listKinds: mergedListTypes
                    )
                } else {
                    uniquePlaces[place.spot.placeId] = place
                }
            }

            savedPlaces = Array(uniquePlaces.values)

            // O(1) lookup map for cards: placeId → display ListKind (priority resolver).
            spotListKindMap = Dictionary(uniqueKeysWithValues:
                savedPlaces.compactMap { spot in
                    guard let kind = displayKind(for: spot.listKinds) else { return nil }
                    return (spot.spot.placeId, kind)
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
        locality: String? = nil,
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
        var resolvedLocality = locality
        var resolvedCountry = country
        var resolvedTypes = types
        var resolvedPhotoUrl = photoUrl
        var resolvedPhotoReference = photoReference
        var resolvedRating = rating

        let needsDetails = (resolvedCountry?.isEmpty ?? true)
            || (resolvedRating == nil)
            || (resolvedCity?.isEmpty ?? true)
            || (resolvedLocality?.isEmpty ?? true)
            || (resolvedTypes?.isEmpty ?? true)
        if needsDetails {
            // Previously this used `try?`, which silently swallowed every
            // Place Details failure — the save still proceeded but the row
            // landed with NULL country/rating/types. The backfill script
            // (Scripts/backfill-spots-city-country.mjs) cleans those up
            // periodically, but we want to know when enrichment fails at
            // save time so we can spot patterns (quota exhaustion, network
            // outages, retired place_ids) instead of finding them weeks
            // later in the table.
            do {
                if let details = try await PlacesAPIService.shared.fetchPlaceDetails(placeId: placeId) {
                    if (resolvedCity?.isEmpty ?? true) { resolvedCity = details.city }
                    if (resolvedLocality?.isEmpty ?? true) { resolvedLocality = details.locality }
                    if (resolvedCountry?.isEmpty ?? true) { resolvedCountry = details.country }
                    if (resolvedTypes?.isEmpty ?? true), !details.category.isEmpty {
                        resolvedTypes = [details.category.lowercased().replacingOccurrences(of: " ", with: "_")]
                    }
                    if (resolvedPhotoUrl?.isEmpty ?? true) { resolvedPhotoUrl = details.photoUrl }
                    if (resolvedPhotoReference?.isEmpty ?? true) { resolvedPhotoReference = details.photoReference }
                    if resolvedRating == nil { resolvedRating = details.rating }
                } else {
                    // nil return = Google had no record for this place_id (retired,
                    // removed, or never indexed). Same operational signal as the
                    // catch block — surface it through DebugLogger so we can spot
                    // patterns instead of finding them weeks later in NULL columns.
                    DebugLogger.log(
                        runId: "pre-fix",
                        hypothesisId: "H2",
                        location: "LocationSavingViewModel.saveSpot:enrichmentNilResult",
                        message: "Place Details returned nil; saving with caller-provided fields only",
                        data: [
                            "placeId": placeId,
                            "missingCity": (resolvedCity?.isEmpty ?? true),
                            "missingCountry": (resolvedCountry?.isEmpty ?? true),
                            "missingRating": (resolvedRating == nil),
                            "missingTypes": (resolvedTypes?.isEmpty ?? true)
                        ]
                    )
                }
            } catch {
                print("⚠️ LocationSavingViewModel.saveSpot: Place Details enrichment failed for \(placeId): \(error.localizedDescription). Proceeding with shallow save; row will be backfilled later.")
                DebugLogger.log(
                    runId: "pre-fix",
                    hypothesisId: "H2",
                    location: "LocationSavingViewModel.saveSpot:enrichmentFailed",
                    message: "Place Details enrichment failed; saving with caller-provided fields only",
                    data: [
                        "placeId": placeId,
                        "error": error.localizedDescription,
                        "missingCity": (resolvedCity?.isEmpty ?? true),
                        "missingCountry": (resolvedCountry?.isEmpty ?? true),
                        "missingRating": (resolvedRating == nil),
                        "missingTypes": (resolvedTypes?.isEmpty ?? true)
                    ]
                )
                // Intentionally do NOT rethrow — the save itself should still
                // succeed even if enrichment fails. The user gets their spot
                // saved; the data quality issue is recoverable via backfill.
            }
        }

        try await service.upsertSpot(
            placeId: placeId,
            name: name,
            address: address,
            city: resolvedCity,
            locality: resolvedLocality,
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
            let prior = self.spotListKindMap[placeId]
            self.spotListKindMap[placeId] = nil
            do {
                try await self.service.removeSpotFromList(placeId: placeId, listId: fromListId)
            } catch {
                self.spotListKindMap[placeId] = prior
                self.lastSaveError = "Couldn't remove. Try again."
                throw error
            }
        }
    }

    // MARK: - Get Spots in List

    func getSpotsInList(listId: UUID, kind: ListKind) async throws -> [SpotWithMetadata] {
        return try await service.getSpotsInList(listId: listId, kind: kind)
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
    //   coerceToSingleDefault (drop extras across .liked/.favorites/.wantToGo,
    //                          keep at most one default; user-created lists pass through)
    //         │
    //         ▼
    //   snapshot prior spotListKindMap[placeId]
    //   optimistic spotListKindMap[placeId] = kind for new single default (or nil)
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

        let prior = spotListKindMap[placeId]
        let newListType = Self.kind(for: coerced, userLists: userLists)
        spotListKindMap[placeId] = newListType

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
                    locality: spotData.locality,
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
            spotListKindMap[placeId] = prior
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

    /// If the input contains more than one of the three system default lists
    /// (.favorites / .liked / .wantToGo), drop the extras and keep one using
    /// the same priority order as `displayKind` (wantToGo wins, then
    /// favorites, then liked). Custom / trip / date_plan lists always pass
    /// through unfiltered.
    /// Defensive — the picker UI prevents users from selecting >1 default,
    /// but this guarantees the invariant for non-UI callers (share extension,
    /// deep links, tests).
    static func coerceToSingleDefault(
        _ selected: Set<UUID>,
        userLists: [UserList]
    ) -> Set<UUID> {
        let defaultListsInSelection = userLists.filter { list in
            list.kind.isSystemKind && selected.contains(list.id)
        }
        guard defaultListsInSelection.count > 1 else { return selected }

        // Pick the canonical default by priority.
        let priorityOrder: [ListKind] = [.wantToGo, .favorites, .liked]
        var winner: UserList?
        for type in priorityOrder {
            if let match = defaultListsInSelection.first(where: { $0.kind == type }) {
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

    /// Returns the system `ListKind` of the single default list in `selected`,
    /// or nil if no system list is selected. Custom / trip / date_plan kinds
    /// return nil. Assumes input has already passed through
    /// `coerceToSingleDefault` so at most one system default is present.
    static func kind(for selected: Set<UUID>, userLists: [UserList]) -> ListKind? {
        for list in userLists {
            if list.kind.isSystemKind, selected.contains(list.id) {
                return list.kind
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
