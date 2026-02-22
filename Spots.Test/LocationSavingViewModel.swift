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
    
    // MARK: - Load Lists
    
    func loadUserLists() async {
        isLoading = true
        errorMessage = nil
        
        do {
            userLists = try await service.getUserLists()
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
        latitude: Double?,
        longitude: Double?,
        types: [String]?,
        photoUrl: String? = nil,
        photoReference: String? = nil,
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
        
        // First, upsert the spot (including photo data if available)
        try await service.upsertSpot(
            placeId: placeId,
            name: name,
            address: address,
            city: city,
            latitude: latitude,
            longitude: longitude,
            types: types,
            photoUrl: photoUrl,
            photoReference: photoReference
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
}

