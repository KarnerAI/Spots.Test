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

    /// PlaceIds whose image fetch failed, so backfillMissingImages can retry them.
    private var failedImageFetchPlaceIds: Set<String> = []

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

    /// Get all lists belonging to an arbitrary user. Read-only — no default-list creation.
    func getUserLists(userId: UUID) async throws -> [UserList] {
        try await supabase
            .from("user_lists")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("list_type", ascending: true)
            .execute()
            .value
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
    
    /// Creates the three default lists (Top Spots, Favorites, Want to Go) for the current user if they don't exist.
    /// DB enum values intentionally remain `starred` / `favorites` / `bucket_list` — only display labels were renamed.
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
        city: String? = nil,
        country: String? = nil,
        latitude: Double?,
        longitude: Double?,
        types: [String]?,
        photoUrl: String? = nil,
        photoReference: String? = nil,
        rating: Double? = nil
    ) async throws {
        // Call the database function
        // Custom Encodable to ensure all parameters are always included
        // even when optionals are nil (encode as JSON null)
        struct UpsertParams: Encodable {
            let p_place_id: String
            let p_name: String
            let p_address: String?
            let p_city: String?
            let p_country: String?
            let p_latitude: Double?
            let p_longitude: Double?
            let p_types: [String]?
            let p_photo_url: String?
            let p_photo_reference: String?
            let p_rating: Double?

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
                if let city = p_city {
                    try container.encode(city, forKey: .p_city)
                } else {
                    try container.encodeNil(forKey: .p_city)
                }
                if let country = p_country {
                    try container.encode(country, forKey: .p_country)
                } else {
                    try container.encodeNil(forKey: .p_country)
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
                if let rating = p_rating {
                    try container.encode(rating, forKey: .p_rating)
                } else {
                    try container.encodeNil(forKey: .p_rating)
                }
            }

            enum CodingKeys: String, CodingKey {
                case p_place_id
                case p_name
                case p_address
                case p_city
                case p_country
                case p_latitude
                case p_longitude
                case p_types
                case p_photo_url
                case p_photo_reference
                case p_rating
            }
        }

        let params = UpsertParams(
            p_place_id: placeId,
            p_name: name,
            p_address: address,
            p_city: city,
            p_country: country,
            p_latitude: latitude,
            p_longitude: longitude,
            p_types: types,
            p_photo_url: photoUrl,
            p_photo_reference: photoReference,
            p_rating: rating
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
        
        // Second query: batch-fetch all spots in a single request
        let placeIds = listItems.map { $0.spot_id }

        struct SpotResponse: Codable {
            let place_id: String
            let name: String
            let address: String?
            let city: String?
            let latitude: Double?
            let longitude: Double?
            let types: [String]?
            let photo_url: String?
            let photo_reference: String?
        }

        // created_at/updated_at intentionally omitted from the SELECT — list
        // UI uses SpotWithMetadata.savedAt, not Spot.createdAt/updatedAt.
        let batchResponse: [SpotResponse] = try await supabase
            .from("spots")
            .select("place_id, name, address, city, latitude, longitude, types, photo_url, photo_reference")
            .in("place_id", values: placeIds)
            .execute()
            .value

        var spotsMap: [String: Spot] = [:]
        for spotData in batchResponse {
            spotsMap[spotData.place_id] = Spot(
                placeId: spotData.place_id,
                name: spotData.name,
                address: spotData.address,
                city: spotData.city,
                latitude: spotData.latitude,
                longitude: spotData.longitude,
                types: spotData.types,
                photoUrl: spotData.photo_url,
                photoReference: spotData.photo_reference,
                createdAt: nil,
                updatedAt: nil
            )
        }

        // Collect (placeId, photoReference) for spots that need image fetch (bounded concurrency later)
        let toFetch: [(String, String)] = spotsMap.compactMap { placeId, spot in
            guard spot.photoUrl == nil, let ref = spot.photoReference else { return nil }
            return (placeId, ref)
        }

        // Transform to SpotWithMetadata
        let spots = listItems.compactMap { item -> SpotWithMetadata? in
            guard let spot = spotsMap[item.spot_id] else {
                return nil
            }

            guard let savedAt = SharedFormatters.date(from: item.saved_at) else {
                print("Warning: Could not parse saved_at: \(item.saved_at)")
                return nil
            }

            return SpotWithMetadata(spot: spot, savedAt: savedAt, listTypes: [listType])
        }

        // Lazy-load images in background with bounded concurrency (max 4 at a time)
        if !toFetch.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                let maxConcurrent = 4
                for batchStart in stride(from: 0, to: toFetch.count, by: maxConcurrent) {
                    let batch = Array(toFetch[batchStart ..< min(batchStart + maxConcurrent, toFetch.count)])
                    await withTaskGroup(of: Void.self) { group in
                        for (placeId, photoRef) in batch {
                            group.addTask { [weak self] in
                                guard let self else { return }
                                let success = await self.fetchAndUpdateSpotImage(placeId: placeId, photoReference: photoRef)
                                if !success {
                                    self.failedImageFetchPlaceIds.insert(placeId)
                                }
                            }
                        }
                    }
                }
            }
        }

        return spots
    }
    
    /// Get all spots across every list for the current user, deduplicated by place_id.
    /// Each SpotWithMetadata.listTypes reflects all lists the spot belongs to.
    func getAllSpots() async throws -> [SpotWithMetadata] {
        let userLists = try await getUserLists()
        guard !userLists.isEmpty else { return [] }

        let listIdStrings = userLists.map { $0.id.uuidString }

        struct SpotListItemRow: Codable {
            let spot_id: String
            let list_id: String
            let saved_at: String
        }

        let allItems: [SpotListItemRow] = try await supabase
            .from("spot_list_items")
            .select("spot_id, list_id, saved_at")
            .in("list_id", values: listIdStrings)
            .order("saved_at", ascending: false)
            .execute()
            .value

        guard !allItems.isEmpty else { return [] }

        // Build a map from list_id UUID → ListType for resolving listTypes later.
        // Use canonical ListType from list when present; otherwise infer from list name
        // so default lists (Starred, Favorites, Bucket List) always contribute to marker icons.
        let listTypeByListId: [String: ListType] = Dictionary(
            uniqueKeysWithValues: userLists.compactMap { list -> (String, ListType)? in
                guard let listType = Self.resolveListType(for: list) else { return nil }
                return (list.id.uuidString, listType)
            }
        )

        // Collect all unique place IDs
        let uniquePlaceIds = Array(Set(allItems.map { $0.spot_id }))

        struct SpotResponse: Codable {
            let place_id: String
            let name: String
            let address: String?
            let city: String?
            let latitude: Double?
            let longitude: Double?
            let types: [String]?
            let photo_url: String?
            let photo_reference: String?
            let created_at: String?
            let updated_at: String?
        }

        let batchResponse: [SpotResponse] = try await supabase
            .from("spots")
            .select("place_id, name, address, city, latitude, longitude, types, photo_url, photo_reference, created_at, updated_at")
            .in("place_id", values: uniquePlaceIds)
            .execute()
            .value

        var spotsMap: [String: Spot] = [:]
        for spotData in batchResponse {
            let createdAt = spotData.created_at.flatMap { SharedFormatters.date(from: $0) }
            let updatedAt = spotData.updated_at.flatMap { SharedFormatters.date(from: $0) }
            spotsMap[spotData.place_id] = Spot(
                placeId: spotData.place_id,
                name: spotData.name,
                address: spotData.address,
                city: spotData.city,
                latitude: spotData.latitude,
                longitude: spotData.longitude,
                types: spotData.types,
                photoUrl: spotData.photo_url,
                photoReference: spotData.photo_reference,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }

        // Deduplicate: for each place_id, keep the most recent saved_at and union all listTypes
        var bestSavedAt: [String: Date] = [:]
        var listTypesPerSpot: [String: Set<ListType>] = [:]

        for item in allItems {
            guard let savedAt = SharedFormatters.date(from: item.saved_at) else { continue }

            if bestSavedAt[item.spot_id] == nil {
                bestSavedAt[item.spot_id] = savedAt
            }
            if let listType = listTypeByListId[item.list_id] {
                listTypesPerSpot[item.spot_id, default: []].insert(listType)
            }
        }

        // Build result ordered by most recent saved_at
        let result: [SpotWithMetadata] = uniquePlaceIds
            .compactMap { placeId -> SpotWithMetadata? in
                guard let spot = spotsMap[placeId], let savedAt = bestSavedAt[placeId] else { return nil }
                let listTypes = listTypesPerSpot[placeId] ?? []
                return SpotWithMetadata(spot: spot, savedAt: savedAt, listTypes: listTypes)
            }
            .sorted { $0.savedAt > $1.savedAt }

        return result
    }

    /// Resolves a canonical ListType for a user list. Uses list_type when present;
    /// otherwise infers from list name so default lists always map to a type for
    /// marker icon resolution in All Spots map. Accepts both current names
    /// (Top Spots / Favorites / Want to Go) and legacy names (Starred / Bucket List)
    /// so rows seeded under the old labels still resolve correctly.
    private static func resolveListType(for list: UserList) -> ListType? {
        if let listType = list.listType { return listType }
        guard let name = list.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let lower = name.lowercased()
        if lower == "top spots" || lower == "starred" { return .starred }
        if lower == "favorites" { return .favorites }
        if lower == "want to go" || lower == "bucket list" { return .bucketList }
        return nil
    }

    /// Helper: Get a single spot by place_id
    private func getSpotByPlaceId(_ placeId: String) async throws -> Spot? {
        struct SpotResponse: Codable {
            let place_id: String
            let name: String
            let address: String?
            let city: String?
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
            .select("place_id, name, address, city, latitude, longitude, types, photo_url, photo_reference, created_at, updated_at")
            .eq("place_id", value: placeId)
            .limit(1)
            .execute()
            .value

        guard let spotData = response.first else {
            return nil
        }

        let createdAt = spotData.created_at.flatMap { SharedFormatters.date(from: $0) }
        let updatedAt = spotData.updated_at.flatMap { SharedFormatters.date(from: $0) }

        return Spot(
            placeId: spotData.place_id,
            name: spotData.name,
            address: spotData.address,
            city: spotData.city,
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

    /// Fetches the most recently saved spot in a list, or nil if the list is empty.
    func getMostRecentSpotInList(listId: UUID) async throws -> Spot? {
        struct SpotIdRow: Codable {
            let spot_id: String
        }
        let rows: [SpotIdRow] = try await supabase
            .from("spot_list_items")
            .select("spot_id")
            .eq("list_id", value: listId.uuidString)
            .order("saved_at", ascending: false)
            .limit(1)
            .execute()
            .value
        guard let spotId = rows.first?.spot_id else { return nil }
        return try await getSpotByPlaceId(spotId)
    }

    /// Fetches the most recently saved spot across a set of lists, or nil if all lists are empty.
    func getMostRecentSpotAcrossLists(listIds: [UUID]) async throws -> Spot? {
        guard !listIds.isEmpty else { return nil }
        struct SpotIdRow: Codable {
            let spot_id: String
        }
        let rows: [SpotIdRow] = try await supabase
            .from("spot_list_items")
            .select("spot_id")
            .in("list_id", values: listIds.map { $0.uuidString })
            .order("saved_at", ascending: false)
            .limit(1)
            .execute()
            .value
        guard let spotId = rows.first?.spot_id else { return nil }
        return try await getSpotByPlaceId(spotId)
    }

    /// Per-list summary returned by `get_list_tile_summaries` RPC.
    /// `mostRecentSpotId` / `mostRecentSavedAt` are nil when the list is empty.
    struct ListTileSummary: Codable {
        let listId: UUID
        let spotCount: Int
        let mostRecentSpotId: String?
        let mostRecentSavedAt: Date?

        enum CodingKeys: String, CodingKey {
            case listId = "list_id"
            case spotCount = "spot_count"
            case mostRecentSpotId = "most_recent_spot_id"
            case mostRecentSavedAt = "most_recent_saved_at"
        }
    }

    /// Batch-fetches spot count + most-recently-saved spot id per list in one RPC call.
    /// Replaces the per-list round-trip pattern in ProfileTileBuilder.buildTiles.
    /// Returns rows only for lists the caller can see (RLS enforced server-side).
    func getListTileSummaries(listIds: [UUID]) async throws -> [ListTileSummary] {
        guard !listIds.isEmpty else { return [] }
        let rows: [ListTileSummary] = try await supabase
            .rpc("get_list_tile_summaries", params: ["p_list_ids": listIds.map { $0.uuidString }])
            .execute()
            .value
        return rows
    }

    /// Batch-fetches Spot rows for a set of place_ids in one round-trip.
    /// Used by ProfileTileBuilder to hydrate tile cover photos after the
    /// summary RPC returns the most_recent_spot_id per list.
    func getSpotsByPlaceIds(_ placeIds: [String]) async throws -> [Spot] {
        guard !placeIds.isEmpty else { return [] }
        let unique = Array(Set(placeIds))

        struct SpotResponse: Codable {
            let place_id: String
            let name: String
            let address: String?
            let city: String?
            let latitude: Double?
            let longitude: Double?
            let types: [String]?
            let photo_url: String?
            let photo_reference: String?
        }

        let response: [SpotResponse] = try await supabase
            .from("spots")
            .select("place_id, name, address, city, latitude, longitude, types, photo_url, photo_reference")
            .in("place_id", values: unique)
            .execute()
            .value

        return response.map { row in
            Spot(
                placeId: row.place_id,
                name: row.name,
                address: row.address,
                city: row.city,
                latitude: row.latitude,
                longitude: row.longitude,
                types: row.types,
                photoUrl: row.photo_url,
                photoReference: row.photo_reference,
                createdAt: nil,
                updatedAt: nil
            )
        }
    }

    /// Returns spot IDs (place_id) in the given list. Used for computing unique count across lists.
    func getSpotIdsInList(listId: UUID) async throws -> [String] {
        struct SpotIdRow: Codable {
            let spot_id: String
        }
        let rows: [SpotIdRow] = try await supabase
            .from("spot_list_items")
            .select("spot_id")
            .eq("list_id", value: listId.uuidString)
            .execute()
            .value
        return rows.map(\.spot_id)
    }

    /// Returns the city name the current user has saved the most spots in, or nil if no city data exists yet.
    /// Falls back to parsing city from the address field for spots saved before city extraction was added.
    func getMostExploredCity() async throws -> String? {
        try await ensureDefaultListsForCurrentUser()
        let userId = try await getCurrentUserId()
        return try await mostExploredCity(userId: userId)
    }

    /// Read-only variant for an arbitrary user. Does not create default lists.
    func getMostExploredCity(userId: UUID) async throws -> String? {
        return try await mostExploredCity(userId: userId)
    }

    private func mostExploredCity(userId: UUID) async throws -> String? {
        // Fast path: server-side aggregation across the user's saved spots.
        // Returns nil when no spot has city populated — falls through to the
        // legacy address-parsing path for users with only pre-backfill data.
        let rpcResult: String? = try await supabase
            .rpc("get_most_explored_city", params: ["p_user_id": userId.uuidString])
            .execute()
            .value
        if let city = rpcResult, !city.isEmpty {
            return city
        }

        return try await legacyMostExploredCityFromAddresses(userId: userId)
    }

    /// Pre-backfill fallback: gathers every saved spot's address and parses
    /// city from the formatted-address string. Used only when the RPC finds
    /// no city-populated rows (legacy data). Kept as-is to preserve behavior.
    private func legacyMostExploredCityFromAddresses(userId: UUID) async throws -> String? {
        let lists = try await getUserLists(userId: userId)

        // Gather all unique spot IDs across all lists
        var allSpotIds = Set<String>()
        for list in lists {
            let ids = try await getSpotIdsInList(listId: list.id)
            allSpotIds.formUnion(ids)
        }
        guard !allSpotIds.isEmpty else { return nil }

        struct CityRow: Codable {
            let place_id: String
            let city: String?
            let address: String?
        }
        let rows: [CityRow] = try await supabase
            .from("spots")
            .select("place_id, city, address")
            .in("place_id", values: Array(allSpotIds))
            .execute()
            .value

        var cityCounts: [String: Int] = [:]
        for row in rows {
            let resolvedCity: String?
            if let city = row.city, !city.isEmpty {
                resolvedCity = city
            } else {
                resolvedCity = Self.extractCityFromAddress(row.address)
            }
            if let city = resolvedCity {
                cityCounts[city, default: 0] += 1
            }
        }
        return cityCounts.max(by: { $0.value < $1.value })?.key
    }

    /// Parses a city name from a Google Places formatted address string.
    /// Google Places addresses are typically: "Street, City, State ZIP, Country"
    /// e.g. "27 Prince St, New York, NY 10012, USA" → "New York"
    private static func extractCityFromAddress(_ address: String?) -> String? {
        guard let address = address, !address.isEmpty else { return nil }
        let parts = address.components(separatedBy: ", ")
        guard parts.count >= 2 else { return nil }

        let knownCountries: Set<String> = [
            "USA", "United States", "UK", "United Kingdom",
            "Canada", "Australia", "France", "Germany",
            "Italy", "Spain", "Japan", "China", "India",
            "Mexico", "Brazil", "Netherlands", "Sweden",
            "Norway", "Denmark", "Portugal", "Switzerland"
        ]

        // Walk parts after the street, find the first that looks like a city name
        for part in parts.dropFirst() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else { continue }
            // Skip parts starting with a digit (e.g. zip codes, suite numbers)
            guard !(trimmed.first?.isNumber ?? true) else { continue }
            // Skip "State ZIP" patterns like "NY 10012" or "CA 94103"
            let isStateZip = trimmed.range(of: #"^[A-Z]{2}\s+\d+"#, options: .regularExpression) != nil
            guard !isStateZip else { continue }
            // Skip known country names
            guard !knownCountries.contains(trimmed) else { continue }
            // Skip bare 2-letter codes (country/state abbreviations on their own)
            if trimmed.count == 2, trimmed == trimmed.uppercased() { continue }

            return trimmed
        }
        return nil
    }

    /// Unique count of spots in the current user's Starred and Favorites lists (spot in both counts once).
    func getUniqueSpotCountInStarredAndFavorites() async throws -> Int {
        try await ensureDefaultListsForCurrentUser()
        let starredList = try await getListByType(.starred)
        let favoritesList = try await getListByType(.favorites)
        let starred: [String] = if let list = starredList { try await getSpotIdsInList(listId: list.id) } else { [] }
        let favorites: [String] = if let list = favoritesList { try await getSpotIdsInList(listId: list.id) } else { [] }
        return Set(starred + favorites).count
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
            ProfileSnapshotCache.shared.markStale()
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
        ProfileSnapshotCache.shared.markStale()
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
    
    /// Fetches and uploads image for a spot that doesn't have a cached photo URL.
    /// Updates the database with the new photo URL and returns whether it succeeded.
    /// Used by both the lazy-load path and the manual backfill.
    @discardableResult
    private func fetchAndUpdateSpotImage(placeId: String, photoReference: String) async -> Bool {
        guard let photoUrl = await ImageStorageService.shared.uploadSpotImage(
            photoReference: photoReference,
            placeId: placeId
        ) else {
            print("⚠️ LocationSavingService: Failed to fetch image for \(placeId)")
            return false
        }

        do {
            try await supabase
                .from("spots")
                .update(["photo_url": photoUrl])
                .eq("place_id", value: placeId)
                .execute()
            print("✅ LocationSavingService: Successfully updated image for \(placeId)")
            failedImageFetchPlaceIds.remove(placeId)
            return true
        } catch {
            print("❌ LocationSavingService: Error updating spot with photo URL: \(error.localizedDescription)")
            return false
        }
    }

    /// Backfills photo_url for all of the current user's saved spots that are missing an image.
    /// For spots with a stored photo_reference, uses it directly.
    /// For spots with no photo_reference (saved before photo logic existed), fetches fresh
    /// place details from Google Places API to obtain a photo_reference first.
    /// Processes in batches of 3 to limit memory pressure.
    /// - Returns: (succeeded, failed, noPhotoAvailable) counts.
    func backfillMissingImages() async -> (succeeded: Int, failed: Int, skipped: Int) {
        let allSpots: [SpotWithMetadata]
        do {
            allSpots = try await getAllSpots()
        } catch {
            print("❌ LocationSavingService: backfillMissingImages failed to fetch spots: \(error)")
            return (0, 0, 0)
        }

        let needsBackfill = allSpots.map(\.spot).filter { $0.photoUrl == nil || failedImageFetchPlaceIds.contains($0.placeId) }

        guard !needsBackfill.isEmpty else {
            print("✅ LocationSavingService: No spots need image backfill")
            return (0, 0, 0)
        }

        print("🔄 LocationSavingService: Backfilling images for \(needsBackfill.count) spots")

        var succeeded = 0
        var failed = 0
        var noPhotoAvailable = 0
        let batchSize = 3

        for batchStart in stride(from: 0, to: needsBackfill.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, needsBackfill.count)
            let batch = Array(needsBackfill[batchStart..<batchEnd])

            // Each task returns: true = success, false = failed, nil = no photo available
            let results: [Bool?] = await withTaskGroup(of: Bool?.self) { group in
                for spot in batch {
                    group.addTask {
                        // Resolve photo reference: use stored one, or fetch fresh from Google
                        let photoRef: String?
                        if let stored = spot.photoReference {
                            photoRef = stored
                        } else {
                            let freshSpot = try? await PlacesAPIService.shared.fetchPlaceDetails(placeId: spot.placeId)
                            photoRef = freshSpot?.photoReference
                        }

                        guard let ref = photoRef else {
                            print("⚠️ LocationSavingService: No photo available for \(spot.name) (\(spot.placeId))")
                            return nil
                        }

                        let ok = await self.fetchAndUpdateSpotImage(placeId: spot.placeId, photoReference: ref)
                        return ok
                    }
                }
                var collected: [Bool?] = []
                for await result in group { collected.append(result) }
                return collected
            }

            succeeded += results.compactMap { $0 }.filter { $0 }.count
            failed += results.compactMap { $0 }.filter { !$0 }.count
            noPhotoAvailable += results.filter { $0 == nil }.count
        }

        print("✅ LocationSavingService: Backfill complete — succeeded: \(succeeded), failed: \(failed), no photo: \(noPhotoAvailable)")
        return (succeeded, failed, noPhotoAvailable)
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

