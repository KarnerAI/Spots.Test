//
//  LocationSavingService.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation
import Supabase

class LocationSavingService {
    static let shared = LocationSavingService()
    
    private let supabase = SupabaseManager.shared.client
    
    private init() {}
    
    // MARK: - Lists
    
    /// Get all lists for the current user
    func getUserLists() async throws -> [UserList] {
        let userId = try await getCurrentUserId()
        
        var response: [UserList] = try await supabase
            .from("user_lists")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("list_type", ascending: true)
            .execute()
            .value
        
        if response.isEmpty {
            try await ensureDefaultListsForCurrentUser()
            response = try await supabase
                .from("user_lists")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("list_type", ascending: true)
                .execute()
                .value
        }
        
        return response
    }
    
    /// Get a specific list by type
    func getListByType(_ listType: ListType) async throws -> UserList? {
        let userId = try await getCurrentUserId()
        
        let response: [UserList] = try await supabase
            .from("user_lists")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("list_type", value: listType.rawValue)
            .limit(1)
            .execute()
            .value
        
        return response.first
    }
    
    /// Creates the three default lists (Starred, Favorites, Bucket List) for the current user if they don't exist.
    /// Idempotent; safe to call after signup, login, or when lists are missing.
    func ensureDefaultListsForCurrentUser() async throws {
        let userId = try await getCurrentUserId()
        try await supabase.rpc("create_default_lists_for_user", params: ["p_user_id": userId.uuidString]).execute()
    }
    
    // MARK: - Spots
    
    /// Upsert a spot (insert or update)
    func upsertSpot(
        placeId: String,
        name: String,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        types: [String]?,
        photoUrl: String? = nil,
        photoReference: String? = nil
    ) async throws {
        // Call the database function
        // Custom Encodable to ensure all parameters are always included
        // even when optionals are nil (encode as JSON null)
        struct UpsertParams: Encodable {
            let p_place_id: String
            let p_name: String
            let p_address: String?
            let p_latitude: Double?
            let p_longitude: Double?
            let p_types: [String]?
            let p_photo_url: String?
            let p_photo_reference: String?
            
            // Custom encoding to always include all parameters, even when nil
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(p_place_id, forKey: .p_place_id)
                try container.encode(p_name, forKey: .p_name)
                // Always encode optional values - use encodeNil to force null in JSON
                if let address = p_address {
                    try container.encode(address, forKey: .p_address)
                } else {
                    try container.encodeNil(forKey: .p_address)
                }
                if let latitude = p_latitude {
                    try container.encode(latitude, forKey: .p_latitude)
                } else {
                    try container.encodeNil(forKey: .p_latitude)
                }
                if let longitude = p_longitude {
                    try container.encode(longitude, forKey: .p_longitude)
                } else {
                    try container.encodeNil(forKey: .p_longitude)
                }
                if let types = p_types {
                    try container.encode(types, forKey: .p_types)
                } else {
                    try container.encodeNil(forKey: .p_types)
                }
                if let photoUrl = p_photo_url {
                    try container.encode(photoUrl, forKey: .p_photo_url)
                } else {
                    try container.encodeNil(forKey: .p_photo_url)
                }
                if let photoReference = p_photo_reference {
                    try container.encode(photoReference, forKey: .p_photo_reference)
                } else {
                    try container.encodeNil(forKey: .p_photo_reference)
                }
            }
            
            enum CodingKeys: String, CodingKey {
                case p_place_id
                case p_name
                case p_address
                case p_latitude
                case p_longitude
                case p_types
                case p_photo_url
                case p_photo_reference
            }
        }
        
        let params = UpsertParams(
            p_place_id: placeId,
            p_name: name,
            p_address: address,
            p_latitude: latitude,
            p_longitude: longitude,
            p_types: types,
            p_photo_url: photoUrl,
            p_photo_reference: photoReference
        )
        
        do {
            try await supabase.rpc("upsert_spot", params: params).execute()
        } catch {
            print("Error calling upsert_spot RPC: \(error)")
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain), code: \(nsError.code)")
                if let errorMessage = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                    print("Error message: \(errorMessage)")
                }
                if let hint = nsError.userInfo["hint"] as? String {
                    print("Error hint: \(hint)")
                }
            }
            
            // #region agent log
            let nsError = error as NSError
            DebugLogger.log(
                runId: "pre-fix",
                hypothesisId: "H2",
                location: "LocationSavingService.upsertSpot:catch",
                message: "Upsert spot failed",
                data: [
                    "placeId": placeId,
                    "errorDomain": nsError.domain,
                    "errorCode": nsError.code,
                    "errorDescription": nsError.localizedDescription
                ]
            )
            // #endregion
            
            throw error
        }
    }
    
    /// Get all spots in a list (ordered by recency)
    func getSpotsInList(listId: UUID, listType: ListType) async throws -> [SpotWithMetadata] {
        // Use a simpler approach: query spot_list_items to get spot_ids and saved_at
        // Then query spots table for each spot's details
        
        struct SpotListItemSimple: Codable {
            let spot_id: String
            let saved_at: String
        }
        
        // First query: get spot IDs and saved_at times
        let listItems: [SpotListItemSimple] = try await supabase
            .from("spot_list_items")
            .select("spot_id, saved_at")
            .eq("list_id", value: listId.uuidString)
            .order("saved_at", ascending: false)
            .execute()
            .value
        
        guard !listItems.isEmpty else {
            return []
        }
        
        // Second query: get all spots for the place_ids we found
        let placeIds = listItems.map { $0.spot_id }
        
        // Query spots one by one (simpler than bulk query which causes type inference issues)
        var spotsMap: [String: Spot] = [:]
        for placeId in placeIds {
            if let spot = try? await getSpotByPlaceId(placeId) {
                spotsMap[placeId] = spot
            }
        }
        
        // Transform to SpotWithMetadata
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        
        let spots = listItems.compactMap { item -> SpotWithMetadata? in
            guard let spot = spotsMap[item.spot_id] else {
                return nil
            }
            
            let savedAt = dateFormatter.date(from: item.saved_at) ?? fallbackFormatter.date(from: item.saved_at)
            guard let savedAt = savedAt else {
                print("Warning: Could not parse saved_at: \(item.saved_at)")
                return nil
            }
            
            // Trigger lazy image fetch if needed (in background)
            // Temporarily disabled to fix compilation - will re-enable after build succeeds
            // if spot.photoUrl == nil, let photoRef = spot.photoReference {
            //     Task {
            //         await fetchAndUpdateSpotImage(placeId: spot.placeId, photoReference: photoRef)
            //     }
            // }
            
            return SpotWithMetadata(spot: spot, savedAt: savedAt, listTypes: [listType])
        }
        
        return spots
    }
    
    /// Helper: Get a single spot by place_id
    private func getSpotByPlaceId(_ placeId: String) async throws -> Spot? {
        struct SpotResponse: Codable {
            let place_id: String
            let name: String
            let address: String?
            let latitude: Double?
            let longitude: Double?
            let types: [String]?
            let photo_url: String?
            let photo_reference: String?
            let created_at: String?
            let updated_at: String?
        }
        
        let response: [SpotResponse] = try await supabase
            .from("spots")
            .select("place_id, name, address, latitude, longitude, types, photo_url, photo_reference, created_at, updated_at")
            .eq("place_id", value: placeId)
            .limit(1)
            .execute()
            .value
        
        guard let spotData = response.first else {
            return nil
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        
        let createdAt = spotData.created_at.flatMap {
            dateFormatter.date(from: $0) ?? fallbackFormatter.date(from: $0)
        }
        let updatedAt = spotData.updated_at.flatMap {
            dateFormatter.date(from: $0) ?? fallbackFormatter.date(from: $0)
        }
        
        return Spot(
            placeId: spotData.place_id,
            name: spotData.name,
            address: spotData.address,
            latitude: spotData.latitude,
            longitude: spotData.longitude,
            types: spotData.types,
            photoUrl: spotData.photo_url,
            photoReference: spotData.photo_reference,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    /// Get spot count for a list
    func getSpotCount(listId: UUID) async throws -> Int {
        // PostgREST returns scalar function results as the scalar value directly
        let count: Int = try await supabase
            .rpc("get_list_spot_count", params: ["list_id": listId.uuidString])
            .execute()
            .value
        
        return count
    }
    
    // MARK: - Saving/Removing Spots
    
    /// Save a spot to a list
    func saveSpotToList(placeId: String, listId: UUID) async throws {
        struct InsertParams: Encodable {
            let spot_id: String
            let list_id: String
        }
        
        let params = InsertParams(spot_id: placeId, list_id: listId.uuidString)
        
        do {
            try await supabase
                .from("spot_list_items")
                .insert(params)
                .execute()
        } catch {
            // If it's a duplicate error, that's okay (constraint prevents duplicates)
            if let error = error as NSError?,
               let errorMessage = error.userInfo[NSLocalizedDescriptionKey] as? String,
               errorMessage.contains("duplicate") || errorMessage.contains("unique") {
                // Silently ignore duplicate errors
                return
            }
            
            // #region agent log
            let nsError = error as NSError
            DebugLogger.log(
                runId: "pre-fix",
                hypothesisId: "H3",
                location: "LocationSavingService.saveSpotToList:catch",
                message: "Save spot to list failed",
                data: [
                    "placeId": placeId,
                    "listId": listId.uuidString,
                    "errorDomain": nsError.domain,
                    "errorCode": nsError.code,
                    "errorDescription": nsError.localizedDescription
                ]
            )
            // #endregion
            
            throw error
        }
    }
    
    /// Remove a spot from a list
    func removeSpotFromList(placeId: String, listId: UUID) async throws {
        try await supabase
            .from("spot_list_items")
            .delete()
            .eq("spot_id", value: placeId)
            .eq("list_id", value: listId.uuidString)
            .execute()
    }
    
    /// Check which lists contain a spot
    func getListsContainingSpot(placeId: String) async throws -> [UUID] {
        struct Response: Codable {
            let list_id: String
        }
        
        let response: [Response] = try await supabase
            .from("spot_list_items")
            .select("list_id")
            .eq("spot_id", value: placeId)
            .execute()
            .value
        
        return response.compactMap { UUID(uuidString: $0.list_id) }
    }
    
    /// Check which place IDs are already in the bucketlist
    /// - Parameter placeIds: Array of place IDs to check
    /// - Returns: Set of place IDs that are already in the bucketlist
    func checkPlacesInBucketlist(_ placeIds: [String]) async throws -> Set<String> {
        // Get the bucketlist
        guard let bucketList = try await getListByType(.bucketList) else {
            // No bucketlist exists yet, so none of the places are in it
            return Set<String>()
        }
        
        // Get all spots in the bucketlist
        let spotsInList = try await getSpotsInList(listId: bucketList.id, listType: .bucketList)
        let existingPlaceIds = Set(spotsInList.map { $0.spot.placeId })
        
        // Return intersection of provided placeIds and existing placeIds
        return Set(placeIds).intersection(existingPlaceIds)
    }
    
    // MARK: - Lazy Image Fetching
    
    /// Fetches and uploads image for a spot that doesn't have a cached photo URL
    /// This runs in the background and updates the database with the new photo URL
    private func fetchAndUpdateSpotImage(placeId: String, photoReference: String) async {
        // Upload image to Supabase Storage
        guard let photoUrl = await ImageStorageService.shared.uploadSpotImage(
            photoReference: photoReference,
            placeId: placeId
        ) else {
            print("⚠️ LocationSavingService: Failed to lazy load image for \(placeId)")
            return
        }
        
        // Update the spot in database with the new photo URL
        do {
            try await supabase
                .from("spots")
                .update(["photo_url": photoUrl])
                .eq("place_id", value: placeId)
                .execute()
            
            print("✅ LocationSavingService: Successfully lazy loaded image for \(placeId)")
        } catch {
            print("❌ LocationSavingService: Error updating spot with photo URL: \(error.localizedDescription)")
        }
    }
    
    /// Updates a spot's latitude and longitude (e.g. to sync with Google's POI tap location).
    func updateSpotLocation(placeId: String, latitude: Double, longitude: Double) async throws {
        try await supabase
            .from("spots")
            .update(["latitude": latitude, "longitude": longitude])
            .eq("place_id", value: placeId)
            .execute()
    }
    
    // MARK: - Helper
    
    private func getCurrentUserId() async throws -> UUID {
        let session = try await supabase.auth.session
        return session.user.id
    }
}

