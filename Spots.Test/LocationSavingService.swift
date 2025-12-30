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
        
        let response: [UserList] = try await supabase
            .from("user_lists")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("list_type", ascending: true)
            .execute()
            .value
        
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
    
    // MARK: - Spots
    
    /// Upsert a spot (insert or update)
    func upsertSpot(
        placeId: String,
        name: String,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        types: [String]?
    ) async throws {
        // Call the database function
        // Custom Encodable to ensure all 6 parameters are always included
        // even when optionals are nil (encode as JSON null)
        struct UpsertParams: Encodable {
            let p_place_id: String
            let p_name: String
            let p_address: String?
            let p_latitude: Double?
            let p_longitude: Double?
            let p_types: [String]?
            
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
            }
            
            enum CodingKeys: String, CodingKey {
                case p_place_id
                case p_name
                case p_address
                case p_latitude
                case p_longitude
                case p_types
            }
        }
        
        let params = UpsertParams(
            p_place_id: placeId,
            p_name: name,
            p_address: address,
            p_latitude: latitude,
            p_longitude: longitude,
            p_types: types
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
            throw error
        }
    }
    
    /// Get all spots in a list (ordered by recency)
    func getSpotsInList(listId: UUID) async throws -> [SpotWithMetadata] {
        // Response structure for nested query
        struct SpotListItemResponse: Codable {
            let spot_id: String
            let saved_at: String
            let spots: SpotResponse
        }
        
        struct SpotResponse: Codable {
            let place_id: String
            let name: String
            let address: String?
            let latitude: Double?
            let longitude: Double?
            let types: [String]?
            let created_at: String?
            let updated_at: String?
        }
        
        let response: [SpotListItemResponse] = try await supabase
            .from("spot_list_items")
            .select("spot_id, saved_at, spots(place_id, name, address, latitude, longitude, types, created_at, updated_at)")
            .eq("list_id", value: listId.uuidString)
            .order("saved_at", ascending: false)
            .execute()
            .value
        
        // Transform response to SpotWithMetadata
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Fallback formatter without fractional seconds
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        
        return response.compactMap { item in
            // Try parsing with fractional seconds first, then fallback
            let savedAt = dateFormatter.date(from: item.saved_at) ?? fallbackFormatter.date(from: item.saved_at)
            guard let savedAt = savedAt else {
                print("Warning: Could not parse saved_at: \(item.saved_at)")
                return nil
            }
            
            let createdAt = item.spots.created_at.flatMap { 
                dateFormatter.date(from: $0) ?? fallbackFormatter.date(from: $0)
            }
            let updatedAt = item.spots.updated_at.flatMap { 
                dateFormatter.date(from: $0) ?? fallbackFormatter.date(from: $0)
            }
            
            let spot = Spot(
                placeId: item.spots.place_id,
                name: item.spots.name,
                address: item.spots.address,
                latitude: item.spots.latitude,
                longitude: item.spots.longitude,
                types: item.spots.types,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            
            return SpotWithMetadata(spot: spot, savedAt: savedAt, listId: listId)
        }
    }
    
    /// Get spot count for a list
    func getSpotCount(listId: UUID) async throws -> Int {
        // Query spot_list_items and count results
        let response: [SpotListItem] = try await supabase
            .from("spot_list_items")
            .select("id")
            .eq("list_id", value: listId.uuidString)
            .execute()
            .value
        
        return response.count
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
    
    // MARK: - Helper
    
    private func getCurrentUserId() async throws -> UUID {
        let session = try await supabase.auth.session
        return session.user.id
    }
}

