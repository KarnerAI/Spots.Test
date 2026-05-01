//
//  LocationSavingViewModel.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation
import SwiftUI

@MainActor
class LocationSavingViewModel: ObservableObject {
    @Published var userLists: [UserList] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    
    private let service = LocationSavingService.shared
    private var userListsLastLoadedAt: Date?
    private let userListsStaleInterval: TimeInterval = 30

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
    
    // MARK: - Save Spot
    
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

        // First, upsert the spot (including photo data if available)
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

        // Then, add it to the list
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
    
    // MARK: - Remove Spot
    
    func removeSpot(placeId: String, fromListId: UUID) async throws {
        try await service.removeSpotFromList(placeId: placeId, listId: fromListId)
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

    // MARK: - Save to multiple lists (diff)

    func saveSpotToLists(spotData: PlaceAutocompleteResult, listIds: Set<UUID>) async throws {
        let original = Set(try await service.getListsContainingSpot(placeId: spotData.placeId))
        let diff = ListSaveDiff(selected: listIds, original: original)

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
        for id in diff.toRemove {
            try await service.removeSpotFromList(placeId: spotData.placeId, listId: id)
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

