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
        latitude: Double?,
        longitude: Double?,
        types: [String]?,
        toListId: UUID
    ) async throws {
        isSaving = true
        defer { isSaving = false }
        
        // First, upsert the spot
        try await service.upsertSpot(
            placeId: placeId,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            types: types
        )
        
        // Then, add it to the list
        try await service.saveSpotToList(placeId: placeId, listId: toListId)
    }
    
    // MARK: - Remove Spot
    
    func removeSpot(placeId: String, fromListId: UUID) async throws {
        try await service.removeSpotFromList(placeId: placeId, listId: fromListId)
    }
    
    // MARK: - Get Spots in List
    
    func getSpotsInList(listId: UUID) async throws -> [SpotWithMetadata] {
        return try await service.getSpotsInList(listId: listId)
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

