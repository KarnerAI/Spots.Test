//
//  PlacesAPIService.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation
import CoreLocation

class PlacesAPIService {
    static let shared = PlacesAPIService()
    
    // API key is loaded from Config.swift
    // See Config.swift for setup instructions
    private var apiKey: String {
        return Config.googlePlacesAPIKey
    }
    
    // Bundle identifier is required for iOS app restrictions
    // Google requires this header to verify the request is from the correct app
    private var bundleIdentifier: String {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            print("⚠️ WARNING: Bundle identifier not found. iOS app restrictions may not work correctly.")
            return ""
        }
        return bundleId
    }
    
    private let baseURL = "https://places.googleapis.com/v1/places:autocomplete"
    private let nearbySearchURL = "https://places.googleapis.com/v1/places:searchNearby"
    
    // MARK: - Autocomplete Response Cache

    /// In-memory cache for autocomplete results to avoid duplicate API calls during active typing.
    /// Key: normalized "\(query)_\(roundedLat)_\(roundedLng)", Value: (results, timestamp)
    private var autocompleteCache: [String: (results: [PlaceAutocompleteResult], timestamp: Date)] = [:]
    private let autocompleteCacheQueue = DispatchQueue(label: "places.autocompleteCache")
    private let autocompleteCacheTTL: TimeInterval = 180 // 3 minutes
    private let autocompleteCacheMaxEntries = 100
    private let persistentAutocompleteTTL: TimeInterval = 7 * 24 * 3600 // 1 week

    /// Thread-safe read from autocomplete cache.
    private func cachedAutocompleteResult(for key: String) -> (results: [PlaceAutocompleteResult], timestamp: Date)? {
        autocompleteCacheQueue.sync { autocompleteCache[key] }
    }

    /// Thread-safe write to autocomplete cache with eviction.
    private func setAutocompleteCacheEntry(key: String, results: [PlaceAutocompleteResult]) {
        autocompleteCacheQueue.sync {
            // Evict oldest if at capacity
            if autocompleteCache.count >= autocompleteCacheMaxEntries,
               let oldestKey = autocompleteCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                autocompleteCache.removeValue(forKey: oldestKey)
            }
            autocompleteCache[key] = (results: results, timestamp: Date())
        }
    }

    /// Builds a cache key for the autocomplete request, rounding coordinates to 3 decimals
    private func autocompleteCacheKey(query: String, location: CLLocation?) -> String {
        guard let loc = location else { return query.lowercased().trimmingCharacters(in: .whitespaces) }
        let lat = (loc.coordinate.latitude * 1000).rounded() / 1000
        let lng = (loc.coordinate.longitude * 1000).rounded() / 1000
        return "\(query.lowercased().trimmingCharacters(in: .whitespaces))_\(lat)_\(lng)"
    }

    // MARK: - Persistent Autocomplete Cache

    /// Row format for the autocomplete_cache Supabase table
    private struct AutocompleteCacheRow: Codable {
        let cache_key: String
        let results_json: String
        let expires_at: String
    }

    /// Fetches cached autocomplete results from Supabase if they exist and haven't expired.
    private func getPersistentAutocompleteResults(cacheKey: String) async -> [PlaceAutocompleteResult]? {
        do {
            let supabase = SupabaseManager.shared.client
            let now = ISO8601DateFormatter.fractionalSeconds.string(from: Date())

            let response: [AutocompleteCacheRow] = try await supabase
                .from("autocomplete_cache")
                .select()
                .eq("cache_key", value: cacheKey)
                .greaterThan("expires_at", value: now)
                .limit(1)
                .execute()
                .value

            guard let row = response.first,
                  let jsonData = row.results_json.data(using: .utf8) else { return nil }

            return try JSONDecoder().decode([PlaceAutocompleteResult].self, from: jsonData)
        } catch {
            print("Autocomplete persistent cache fetch error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Persists autocomplete results to Supabase with a 1-week TTL.
    private func persistAutocompleteResults(cacheKey: String, results: [PlaceAutocompleteResult]) async {
        do {
            let jsonData = try JSONEncoder().encode(results)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let expiresAt = ISO8601DateFormatter.fractionalSeconds.string(from: Date().addingTimeInterval(persistentAutocompleteTTL))
            let row = AutocompleteCacheRow(cache_key: cacheKey, results_json: jsonString, expires_at: expiresAt)

            let supabase = SupabaseManager.shared.client
            try await supabase
                .from("autocomplete_cache")
                .upsert(row)
                .execute()
        } catch {
            print("Autocomplete persistent cache persist error: \(error.localizedDescription)")
        }
    }

    private init() {}

    // MARK: - Autocomplete (async/await)

    /// Performs autocomplete search for places using a single 10km radius request with response caching.
    /// This is the primary API. The callback-based overload below delegates to this method.
    func autocomplete(
        query: String,
        location: CLLocation? = nil
    ) async throws -> [PlaceAutocompleteResult] {
        // 1. Check in-memory cache first (thread-safe)
        let cacheKey = autocompleteCacheKey(query: query, location: location)
        if let cached = cachedAutocompleteResult(for: cacheKey),
           Date().timeIntervalSince(cached.timestamp) < autocompleteCacheTTL {
            print("Places API: In-memory cache hit for '\(query)' (\(cached.results.count) results)")
            return cached.results
        }

        // 2. Check persistent (Supabase) cache
        if let persistedResults = await getPersistentAutocompleteResults(cacheKey: cacheKey) {
            print("Places API: Persistent cache hit for '\(query)' (\(persistedResults.count) results)")
            setAutocompleteCacheEntry(key: cacheKey, results: persistedResults)
            return persistedResults
        }

        // 3. No cache hit — make the API call
        let results: [PlaceAutocompleteResult] = try await withCheckedThrowingContinuation { continuation in
            performAutocompleteRequest(query: query, location: location, radius: 10000.0) { result in
                continuation.resume(with: result)
            }
        }

        print("Places API: Request returned \(results.count) results")

        // Sort by distance if location available
        let sorted: [PlaceAutocompleteResult]
        if let location = location {
            sorted = await withCheckedContinuation { continuation in
                sortResultsByDistance(results, userLocation: location) { sortedResults in
                    continuation.resume(returning: sortedResults)
                }
            }
        } else {
            sorted = results
        }

        let limited = Array(sorted.prefix(10))
        setAutocompleteCacheEntry(key: cacheKey, results: limited)
        // Persist to Supabase for future sessions
        await persistAutocompleteResults(cacheKey: cacheKey, results: limited)
        return limited
    }

    // MARK: - Autocomplete (callback wrapper)

    /// Callback-based overload for backward compatibility. Delegates to the async version.
    func autocomplete(
        query: String,
        location: CLLocation? = nil,
        completion: @escaping (Result<[PlaceAutocompleteResult], Error>) -> Void
    ) {
        // 1. Check in-memory cache first (thread-safe)
        let cacheKey = autocompleteCacheKey(query: query, location: location)
        if let cached = cachedAutocompleteResult(for: cacheKey),
           Date().timeIntervalSince(cached.timestamp) < autocompleteCacheTTL {
            print("Places API: In-memory cache hit for '\(query)' (\(cached.results.count) results)")
            completion(.success(cached.results))
            return
        }

        // 2. Check persistent (Supabase) cache, then fall through to API
        Task { [weak self] in
            if let persistedResults = await self?.getPersistentAutocompleteResults(cacheKey: cacheKey) {
                print("Places API: Persistent cache hit for '\(query)' (\(persistedResults.count) results)")
                self?.setAutocompleteCacheEntry(key: cacheKey, results: persistedResults)
                await MainActor.run { completion(.success(persistedResults)) }
                return
            }

            // 3. No cache hit — make the API call
            self?.performAutocompleteRequest(query: query, location: location, radius: 10000.0) { [weak self] result in
                switch result {
                case .success(let results):
                    print("Places API: Request returned \(results.count) results")
                    if let location = location {
                        self?.sortResultsByDistance(results, userLocation: location) { sortedResults in
                            let limited = Array(sortedResults.prefix(10))
                            self?.setAutocompleteCacheEntry(key: cacheKey, results: limited)
                            // Persist to Supabase for future sessions
                            Task { await self?.persistAutocompleteResults(cacheKey: cacheKey, results: limited) }
                            completion(.success(limited))
                        }
                    } else {
                        let limited = Array(results.prefix(10))
                        self?.setAutocompleteCacheEntry(key: cacheKey, results: limited)
                        Task { await self?.persistAutocompleteResults(cacheKey: cacheKey, results: limited) }
                        completion(.success(limited))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Internal method to perform a single autocomplete request
    private func performAutocompleteRequest(
        query: String,
        location: CLLocation?,
        radius: Double,
        completion: @escaping (Result<[PlaceAutocompleteResult], Error>) -> Void
    ) {
        guard !apiKey.isEmpty && apiKey != "YOUR_GOOGLE_PLACES_API_KEY_HERE" else {
            completion(.failure(PlacesAPIError.apiKeyNotConfigured))
            return
        }
        
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            completion(.success([]))
            return
        }
        
        // Build request body according to Google Places API (New) specification
        // Note: maxResultCount is not a valid field - the API returns a default number of results
        var requestBody: [String: Any] = [
            "input": query,
            "includedPrimaryTypes": ["establishment"]
        ]
        
        // Add location bias if available
        // Using the provided radius for location bias
        // Smaller radius (10km) for focused results, larger (20km) for more results
        if let location = location {
            requestBody["locationBias"] = [
                "circle": [
                    "center": [
                        "latitude": location.coordinate.latitude,
                        "longitude": location.coordinate.longitude
                    ],
                    "radius": radius // Use provided radius
                ]
            ]
        }
        
        guard let url = URL(string: baseURL) else {
            completion(.failure(PlacesAPIError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        
        // Add bundle identifier header for iOS app restrictions
        // This is required when API key has iOS app restrictions enabled
        let bundleId = bundleIdentifier
        if !bundleId.isEmpty {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
            print("📱 Sending API request with bundle ID: \(bundleId)")
        } else {
            print("⚠️ WARNING: Bundle identifier is empty. iOS app restrictions may not work.")
        }
        
        // Field mask: only request the fields we actually decode in the response
        // handler below (placeId, text.text, structuredFormat.{mainText,secondaryText}).
        // Without a mask, Places Autocomplete (New) returns the full payload and
        // bills the higher SKU (~3× the masked rate). Keep this in sync with the
        // decoder above.
        request.setValue(
            "suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat,suggestions.placePrediction.types",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(PlacesAPIError.requestEncodingFailed))
            return
        }
        
        // Perform request
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(PlacesAPIError.invalidResponse))
                }
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                // Log error response for debugging
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    print("Places API Error Response: \(errorString)")
                }
                
                DispatchQueue.main.async {
                    if httpResponse.statusCode == 403 {
                        completion(.failure(PlacesAPIError.apiKeyInvalid))
                    } else if httpResponse.statusCode == 400 {
                        // Try to extract more detailed error message
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = json["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            completion(.failure(PlacesAPIError.apiError(status: "400: \(message)")))
                        } else {
                            completion(.failure(PlacesAPIError.httpError(statusCode: httpResponse.statusCode)))
                        }
                    } else {
                        completion(.failure(PlacesAPIError.httpError(statusCode: httpResponse.statusCode)))
                    }
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(PlacesAPIError.noData))
                }
                return
            }
            
            // Check if data is empty
            guard !data.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(PlacesAPIError.noData))
                }
                return
            }
            
            do {
                let decoder = JSONDecoder()
                // Try to parse as new API format first (Places API New)
                let newResponse = try decoder.decode(NewPlacesAutocompleteResponse.self, from: data)
                let predictions = newResponse.suggestions.compactMap { suggestion -> PlaceAutocompleteResult? in
                    let placePrediction = suggestion.placePrediction
                    
                    // Use structuredFormat if available (preferred), otherwise parse from text
                    let name: String
                    let address: String
                    
                    if let structured = placePrediction.structuredFormat {
                        name = structured.mainText.text
                        address = structured.secondaryText?.text ?? placePrediction.text.text
                    } else {
                        // Fallback: Parse from full text
                        let fullText = placePrediction.text.text
                        let components = fullText.components(separatedBy: ", ")
                        name = components.first ?? fullText
                        address = components.count > 1 ? components.dropFirst().joined(separator: ", ") : fullText
                    }
                    
                    return PlaceAutocompleteResult(
                        placeId: placePrediction.placeId,
                        name: name,
                        address: address,
                        types: placePrediction.types
                    )
                }
                
                // Remove duplicates based on placeId (in case we get duplicates from multiple requests)
                var uniquePredictions: [PlaceAutocompleteResult] = []
                var seenPlaceIds = Set<String>()
                for prediction in predictions {
                    if !seenPlaceIds.contains(prediction.placeId) {
                        seenPlaceIds.insert(prediction.placeId)
                        uniquePredictions.append(prediction)
                    }
                }
                
                // Return all unique predictions (limiting to 10 happens in the main autocomplete function)
                DispatchQueue.main.async {
                    completion(.success(uniquePredictions))
                }
            } catch {
                // Fallback: Try old API format
                do {
                    let decoder = JSONDecoder()
                    let response = try decoder.decode(PlacesAutocompleteResponse.self, from: data)
                    
                    // Check status
                    guard response.status == "OK" || response.status == "ZERO_RESULTS" else {
                        DispatchQueue.main.async {
                            completion(.failure(PlacesAPIError.apiError(status: response.status)))
                        }
                        return
                    }
                    
                    // Convert old format to new format
                    let predictions = response.predictions.map { prediction -> PlaceAutocompleteResult in
                        let name: String
                        let address: String
                        
                        if let structured = prediction.structuredFormatting {
                            name = structured.mainText
                            address = structured.secondaryText ?? prediction.description
                        } else {
                            // Parse from description
                            let components = prediction.description.components(separatedBy: ", ")
                            name = components.first ?? prediction.description
                            address = components.count > 1 ? components.dropFirst().joined(separator: ", ") : prediction.description
                        }
                        
                        return PlaceAutocompleteResult(
                            placeId: prediction.placeId,
                            name: name,
                            address: address,
                            types: nil
                        )
                    }
                    
                    DispatchQueue.main.async {
                        completion(.success(predictions))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(PlacesAPIError.decodingFailed(error)))
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Nearby Search
    
    /// Searches for nearby places using Google Places Nearby Search (New) API
    /// - Parameters:
    ///   - location: User's current location
    ///   - radius: Search radius in meters (default: 1000m)
    ///   - pageToken: Optional token for pagination
    ///   - maxResults: Maximum number of results to return (default: 10)
    /// - Returns: Tuple of (spots, nextPageToken) for pagination support
    func searchNearby(
        location: CLLocation,
        radius: Double = 1000,
        pageToken: String? = nil,
        maxResults: Int = 10
    ) async throws -> (spots: [NearbySpot], nextPageToken: String?) {
        guard !apiKey.isEmpty && apiKey != "YOUR_GOOGLE_PLACES_API_KEY_HERE" else {
            throw PlacesAPIError.apiKeyNotConfigured
        }
        
        guard let url = URL(string: nearbySearchURL) else {
            throw PlacesAPIError.invalidURL
        }
        
        // Build request body for Nearby Search (New) API
        var requestBody: [String: Any] = [
            "maxResultCount": maxResults,
            "locationRestriction": [
                "circle": [
                    "center": [
                        "latitude": location.coordinate.latitude,
                        "longitude": location.coordinate.longitude
                    ],
                    "radius": radius
                ]
            ]
        ]
        
        // Add page token for pagination if provided
        if let pageToken = pageToken {
            requestBody["pageToken"] = pageToken
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        
        // Add bundle identifier for iOS app restrictions
        let bundleId = bundleIdentifier
        if !bundleId.isEmpty {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        
        // Request only Basic/Standard fields to stay on the cheaper billing SKU.
        // Photo references are resolved from the Supabase cache or via on-demand
        // fetchPlaceDetails calls instead of including places.photos here.
        let fieldMask = [
            "places.id",
            "places.displayName",
            "places.formattedAddress",
            "places.shortFormattedAddress",
            "places.addressComponents",
            "places.location",
            "places.types",
            "places.rating"
        ].joined(separator: ",")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlacesAPIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("Nearby Search API Error Response: \(errorString)")
            }
            
            if httpResponse.statusCode == 403 {
                throw PlacesAPIError.apiKeyInvalid
            } else if httpResponse.statusCode == 400 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw PlacesAPIError.apiError(status: "400: \(message)")
                }
            }
            throw PlacesAPIError.httpError(statusCode: httpResponse.statusCode)
        }
        
        guard !data.isEmpty else {
            throw PlacesAPIError.noData
        }
        
        let decoder = JSONDecoder()
        let nearbyResponse = try decoder.decode(NearbySearchResponse.self, from: data)
        
        // Convert API results to NearbySpot models
        var spots = nearbyResponse.places?.compactMap { $0.toNearbySpot() } ?? []
        
        #if DEBUG
        print("📸 PlacesAPIService: Converted \(spots.count) spots. Spots with photos: \(spots.filter { $0.photoReference != nil }.count)")
        #endif
        
        // Calculate distance for each spot and sort by distance
        spots = spots.map { $0.withDistance(from: location) }
        spots.sort { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
        
        // Note: Image uploads are now handled by the caller (MapViewModel)
        // so it can feed Supabase URLs back into the in-memory spots array.
        
        return (spots: spots, nextPageToken: nearbyResponse.nextPageToken)
    }
    
    /// Fetches a photo for a place using the photo name
    /// - Parameters:
    ///   - photoName: The photo name from the Places API (format: "places/{placeId}/photos/{photoReference}")
    ///   - maxWidth: Maximum width of the photo
    /// - Returns: URL for the photo
    func getPhotoURL(photoName: String, maxWidth: Int = 400) -> URL? {
        // For Places API (New), we need to use the media endpoint
        let urlString = "https://places.googleapis.com/v1/\(photoName)/media?maxWidthPx=\(maxWidth)&key=\(apiKey)"
        return URL(string: urlString)
    }
    
    /// In-memory cache for place details to avoid repeated API calls for the same POI.
    private var placeDetailsCache: [String: NearbySpot] = [:]
    private let placeDetailsCacheMaxEntries = 50

    /// Fetches place details by placeId from Google Places API
    /// Used for getting details of tapped POI markers
    /// - Parameter placeId: The Google Place ID
    /// - Returns: NearbySpot with full details, or nil if not found
    func fetchPlaceDetails(placeId: String) async throws -> NearbySpot? {
        // Only honor cache hits that have everything the feed hero needs.
        // A sparse cached row would short-circuit to a NearbySpot with nil
        // city/country/rating and feed enrichment would never get those
        // fields filled in.
        if let cached = placeDetailsCache[placeId], cached.hasFullEnrichmentFields {
            return cached
        }
        if let dbCached = await getCachedSpot(placeId: placeId), dbCached.hasFullEnrichmentFields {
            evictPlaceDetailsCacheIfNeeded()
            placeDetailsCache[placeId] = dbCached
            return dbCached
        }

        guard !apiKey.isEmpty && apiKey != "YOUR_GOOGLE_PLACES_API_KEY_HERE" else {
            throw PlacesAPIError.apiKeyNotConfigured
        }

        let urlString = "https://places.googleapis.com/v1/places/\(placeId)"
        guard let url = URL(string: urlString) else {
            throw PlacesAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        
        // Add bundle identifier for iOS app restrictions
        let bundleId = bundleIdentifier
        if !bundleId.isEmpty {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        
        // Request specific fields. addressComponents is required for the
        // city + country derivation in PlaceDetailsResponse.toNearbySpot().
        let fieldMask = [
            "id",
            "displayName",
            "formattedAddress",
            "shortFormattedAddress",
            "location",
            "types",
            "rating",
            "photos",
            "addressComponents"
        ].joined(separator: ",")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlacesAPIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("Place Details API Error Response: \(errorString)")
            }
            
            if httpResponse.statusCode == 403 {
                throw PlacesAPIError.apiKeyInvalid
            } else if httpResponse.statusCode == 404 {
                return nil // Place not found
            }
            throw PlacesAPIError.httpError(statusCode: httpResponse.statusCode)
        }
        
        guard !data.isEmpty else {
            throw PlacesAPIError.noData
        }
        
        let decoder = JSONDecoder()
        let placeResponse = try decoder.decode(PlaceDetailsResponse.self, from: data)
        let spot = placeResponse.toNearbySpot()
        evictPlaceDetailsCacheIfNeeded()
        if let spot = spot {
            placeDetailsCache[placeId] = spot
        }
        return spot
    }

    private func evictPlaceDetailsCacheIfNeeded() {
        guard placeDetailsCache.count >= placeDetailsCacheMaxEntries else { return }
        if let keyToRemove = placeDetailsCache.keys.first {
            placeDetailsCache.removeValue(forKey: keyToRemove)
        }
    }
}

// MARK: - Error Types

enum PlacesAPIError: LocalizedError {
    case apiKeyNotConfigured
    case apiKeyInvalid
    case invalidURL
    case requestEncodingFailed
    case invalidResponse
    case noData
    case decodingFailed(Error)
    case httpError(statusCode: Int)
    case apiError(status: String)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "Google Places API key is not configured. Please set your API key in PlacesAPIService.swift"
        case .apiKeyInvalid:
            return "Invalid Google Places API key. Please check your API key configuration."
        case .invalidURL:
            return "Invalid API URL"
        case .requestEncodingFailed:
            return "Failed to encode request"
        case .invalidResponse:
            return "Invalid response from server"
        case .noData:
            return "No data received from server"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .httpError(let statusCode):
            return "HTTP error with status code: \(statusCode)"
        case .apiError(let status):
            return "Places API error: \(status)"
        }
    }
}

// MARK: - New API Response Models

struct NewPlacesAutocompleteResponse: Codable {
    let suggestions: [Suggestion]
}

struct Suggestion: Codable {
    let placePrediction: PlacePrediction
    
    enum CodingKeys: String, CodingKey {
        case placePrediction = "placePrediction"
    }
}

struct PlacePrediction: Codable {
    let placeId: String
    let text: PlaceText
    let structuredFormat: StructuredFormat?
    let types: [String]?

    enum CodingKeys: String, CodingKey {
        case placeId = "placeId"
        case text
        case structuredFormat
        case types
    }
}

struct StructuredFormat: Codable {
    let mainText: PlaceText
    let secondaryText: PlaceText?
}

struct PlaceText: Codable {
    let text: String
    let matches: [TextMatch]?
}

struct TextMatch: Codable {
    let startOffset: Int?
    let endOffset: Int
}

// MARK: - Place Details and Distance Sorting

extension PlacesAPIService {
    // MARK: Coordinate Cache

    /// In-memory coordinate cache keyed by placeId. Coordinates don't change so no TTL needed.
    private static var _coordinateCache: [String: CLLocationCoordinate2D] = [:]
    private static let coordinateCacheQueue = DispatchQueue(label: "places.coordinateCache")

    private var coordinateCache: [String: CLLocationCoordinate2D] {
        get { Self.coordinateCacheQueue.sync { Self._coordinateCache } }
    }

    private func cacheCoordinate(_ coord: CLLocationCoordinate2D, for placeId: String) {
        Self.coordinateCacheQueue.sync { Self._coordinateCache[placeId] = coord }
    }

    /// Sorts results by distance from user location
    /// Fetches place coordinates if needed (checking cache first), then sorts by distance
    private func sortResultsByDistance(
        _ results: [PlaceAutocompleteResult],
        userLocation: CLLocation?,
        completion: @escaping ([PlaceAutocompleteResult]) -> Void
    ) {
        guard let userLocation = userLocation, !results.isEmpty else {
            completion(results)
            return
        }

        fetchPlaceCoordinates(for: results) { resultsWithCoordinates in
            let sorted = resultsWithCoordinates.sorted { result1, result2 in
                let distance1 = self.distance(from: userLocation, to: result1)
                let distance2 = self.distance(from: userLocation, to: result2)
                return distance1 < distance2
            }
            completion(sorted)
        }
    }

    /// Fetches coordinates for multiple places, checking cache first to skip API calls
    private func fetchPlaceCoordinates(
        for results: [PlaceAutocompleteResult],
        completion: @escaping ([PlaceAutocompleteResult]) -> Void
    ) {
        let resultsToFetch = Array(results.prefix(10))
        let group = DispatchGroup()
        var resultsWithCoordinates: [PlaceAutocompleteResult] = []
        let queue = DispatchQueue(label: "places.coordinates")

        for result in resultsToFetch {
            // Check cache first — skip API call if we already have coordinates
            if let cached = coordinateCache[result.placeId] {
                group.enter()
                queue.async {
                    resultsWithCoordinates.append(result.withCoordinate(cached))
                    group.leave()
                }
                continue
            }

            group.enter()
            fetchPlaceCoordinate(placeId: result.placeId) { [weak self] coordinate in
                queue.async {
                    if let coord = coordinate {
                        self?.cacheCoordinate(coord, for: result.placeId)
                    }
                    resultsWithCoordinates.append(result.withCoordinate(coordinate))
                    group.leave()
                }
            }
        }

        // Run final assembly on the serial queue so we read resultsWithCoordinates on the same thread that wrote it, then deliver on main.
        group.notify(queue: queue) {
            let resultsWithoutCoordinates = results.filter { result in
                !resultsToFetch.contains { $0.placeId == result.placeId }
            }
            let finalResults = resultsWithCoordinates + resultsWithoutCoordinates
            DispatchQueue.main.async {
                completion(finalResults)
            }
        }
    }

    /// Fetches coordinate for a single place using Places API (New) place details
    private func fetchPlaceCoordinate(
        placeId: String,
        completion: @escaping (CLLocationCoordinate2D?) -> Void
    ) {
        let urlString = "https://places.googleapis.com/v1/places/\(placeId)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")

        let bundleId = bundleIdentifier
        if !bundleId.isEmpty {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        request.setValue("location", forHTTPHeaderField: "X-Goog-FieldMask")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                completion(nil)
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let location = json["location"] as? [String: Any],
               let latitude = location["latitude"] as? Double,
               let longitude = location["longitude"] as? Double {
                completion(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            } else {
                completion(nil)
            }
        }.resume()
    }
    
    /// Calculates distance from user location to a place result
    private func distance(from userLocation: CLLocation, to result: PlaceAutocompleteResult) -> CLLocationDistance {
        guard let coordinate = result.coordinate else {
            // If no coordinate, put at end (very large distance)
            return Double.greatestFiniteMagnitude
        }

        return DistanceCalculator.distance(from: userLocation, to: coordinate)
    }
    
    /// Uploads spot images to Supabase Storage in the background.
    /// Checks if image already exists before uploading to avoid duplicates.
    /// - Returns: Dictionary mapping placeId -> Supabase photo URL for successfully uploaded spots.
    /// Maximum number of concurrent image uploads to limit memory usage
    private static let maxConcurrentUploads = 3

    func uploadSpotImages(spots: [NearbySpot]) async -> [String: String] {
        let placeIdsWithPhoto = spots.compactMap { $0.photoReference != nil ? $0.placeId : nil }
        guard !placeIdsWithPhoto.isEmpty else { return [:] }

        let existingUrls = await getCachedPhotoUrls(placeIds: placeIdsWithPhoto)
        var spotsToUpload: [(spot: NearbySpot, photoReference: String)] = []
        for spot in spots {
            guard let photoReference = spot.photoReference else { continue }
            if existingUrls[spot.placeId] != nil {
                #if DEBUG
                print("✅ PlacesAPIService: Photo already cached for \(spot.name)")
                #endif
                continue
            }
            spotsToUpload.append((spot, photoReference))
        }

        guard !spotsToUpload.isEmpty else { return [:] }

        // Process in batches of maxConcurrentUploads to limit memory pressure
        var uploadedUrls: [String: String] = [:]
        for batchStart in stride(from: 0, to: spotsToUpload.count, by: Self.maxConcurrentUploads) {
            let batchEnd = min(batchStart + Self.maxConcurrentUploads, spotsToUpload.count)
            let batch = spotsToUpload[batchStart..<batchEnd]

            await withTaskGroup(of: (String, String?).self) { group in
                for (spot, photoReference) in batch {
                    group.addTask {
                        let photoUrl = await ImageStorageService.shared.uploadSpotImage(
                            photoReference: photoReference,
                            placeId: spot.placeId
                        )
                        if let photoUrl = photoUrl {
                            print("✅ PlacesAPIService: Uploaded image for \(spot.name)")
                            await self.upsertSpotWithPhoto(spot: spot, photoUrl: photoUrl, photoReference: photoReference)
                        } else {
                            print("⚠️ PlacesAPIService: Failed to upload image for \(spot.name)")
                        }
                        return (spot.placeId, photoUrl)
                    }
                }

                for await (placeId, photoUrl) in group {
                    if let url = photoUrl {
                        uploadedUrls[placeId] = url
                    }
                }
            }
        }

        return uploadedUrls
    }
    
    /// Bulk-upserts all nearby spot metadata into the spots table.
    /// This builds up a local cache so future lookups (e.g. POI taps) can
    /// skip the Google API call entirely. Includes photo_reference so that
    /// the Google photo ref is persisted immediately (even before Storage upload).
    func bulkUpsertSpots(_ spots: [NearbySpot]) async {
        guard !spots.isEmpty else { return }
        
        struct SpotRow: Encodable {
            let place_id: String
            let name: String
            let address: String
            let latitude: Double
            let longitude: Double
            let photo_reference: String?
            let updated_at: String
        }
        
        let rows = spots.map { spot in
            SpotRow(
                place_id: spot.placeId,
                name: spot.name,
                address: spot.address,
                latitude: spot.latitude,
                longitude: spot.longitude,
                photo_reference: spot.photoReference,
                updated_at: ISO8601DateFormatter.fractionalSeconds.string(from: Date())
            )
        }
        
        do {
            let supabase = SupabaseManager.shared.client
            try await supabase
                .from("spots")
                .upsert(rows)
                .execute()
            
            print("✅ PlacesAPIService: Bulk-upserted \(rows.count) spots into DB cache (with photo references)")
        } catch {
            print("❌ PlacesAPIService: Error bulk-upserting spots: \(error.localizedDescription)")
        }
    }
    
    /// Checks if a photo URL already exists for a spot
    private func checkPhotoExists(placeId: String) async -> Bool {
        return await getCachedPhotoUrl(placeId: placeId) != nil
    }
    
    /// Returns the cached Supabase photo URL for a spot if it exists in the DB, nil otherwise.
    func getCachedPhotoUrl(placeId: String) async -> String? {
        let result = await getCachedPhotoUrls(placeIds: [placeId])
        return result[placeId]
    }
    
    /// Batch-fetches cached Supabase photo URLs and photo references for multiple spots in a single DB query.
    func getCachedPhotoUrls(placeIds: [String]) async -> [String: String] {
        guard !placeIds.isEmpty else { return [:] }
        do {
            let supabase = SupabaseManager.shared.client
            
            struct SpotPhotoRow: Codable {
                let place_id: String
                let photo_url: String?
            }
            
            let response: [SpotPhotoRow] = try await supabase
                .from("spots")
                .select("place_id, photo_url")
                .in("place_id", values: placeIds)
                .execute()
                .value
            
            var result: [String: String] = [:]
            for row in response {
                if let url = row.photo_url, !url.isEmpty {
                    result[row.place_id] = url
                }
            }
            return result
        } catch {
            print("❌ PlacesAPIService: Error batch-fetching cached photo URLs: \(error.localizedDescription)")
            return [:]
        }
    }
    
    /// Batch-fetches cached photo references for spots that have no Supabase photo URL yet.
    func getCachedPhotoReferences(placeIds: [String]) async -> [String: String] {
        guard !placeIds.isEmpty else { return [:] }
        do {
            let supabase = SupabaseManager.shared.client
            
            struct SpotRefRow: Codable {
                let place_id: String
                let photo_reference: String?
            }
            
            let response: [SpotRefRow] = try await supabase
                .from("spots")
                .select("place_id, photo_reference")
                .in("place_id", values: placeIds)
                .execute()
                .value
            
            var result: [String: String] = [:]
            for row in response {
                if let ref = row.photo_reference, !ref.isEmpty {
                    result[row.place_id] = ref
                }
            }
            return result
        } catch {
            print("❌ PlacesAPIService: Error batch-fetching cached photo refs: \(error.localizedDescription)")
            return [:]
        }
    }
    
    /// Returns full cached spot data from the DB, or nil if not found.
    func getCachedSpot(placeId: String) async -> NearbySpot? {
        do {
            let supabase = SupabaseManager.shared.client
            
            struct CachedSpotRow: Codable {
                let place_id: String
                let name: String
                let address: String?
                let city: String?
                let country: String?
                let latitude: Double?
                let longitude: Double?
                let types: [String]?
                let photo_url: String?
                let photo_reference: String?
                let rating: Double?
            }

            let response: [CachedSpotRow] = try await supabase
                .from("spots")
                .select("place_id, name, address, city, country, latitude, longitude, types, photo_url, photo_reference, rating")
                .eq("place_id", value: placeId)
                .limit(1)
                .execute()
                .value

            guard let row = response.first,
                  let lat = row.latitude,
                  let lng = row.longitude else {
                return nil
            }

            let category = NearbySpot.mapCategory(from: row.types ?? [])

            return NearbySpot(
                placeId: row.place_id,
                name: row.name,
                address: row.address ?? "",
                city: row.city,
                country: row.country,
                category: category,
                rating: row.rating,
                photoReference: row.photo_reference,
                photoUrl: row.photo_url,
                latitude: lat,
                longitude: lng
            )
        } catch {
            print("❌ PlacesAPIService: Error fetching cached spot: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Upserts a spot row with photo URL in database.
    /// Creates the row if it doesn't exist; updates photo fields if it does.
    private func upsertSpotWithPhoto(spot: NearbySpot, photoUrl: String, photoReference: String) async {
        struct SpotPhotoRow: Encodable {
            let place_id: String
            let name: String
            let address: String
            let city: String?
            let latitude: Double
            let longitude: Double
            let photo_url: String
            let photo_reference: String
            let updated_at: String
        }

        let row = SpotPhotoRow(
            place_id: spot.placeId,
            name: spot.name,
            address: spot.address,
            city: spot.city,
            latitude: spot.latitude,
            longitude: spot.longitude,
            photo_url: photoUrl,
            photo_reference: photoReference,
            updated_at: ISO8601DateFormatter.fractionalSeconds.string(from: Date())
        )

        do {
            let supabase = SupabaseManager.shared.client
            try await supabase
                .from("spots")
                .upsert(row)
                .execute()

            print("✅ PlacesAPIService: Upserted spot with photo URL for \(spot.placeId)")
        } catch {
            print("❌ PlacesAPIService: Error upserting spot with photo: \(error.localizedDescription)")
        }
    }
}


