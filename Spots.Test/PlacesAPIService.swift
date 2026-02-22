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
    private let autocompleteCacheTTL: TimeInterval = 180 // 3 minutes

    /// Builds a cache key for the autocomplete request, rounding coordinates to 3 decimals
    private func autocompleteCacheKey(query: String, location: CLLocation?) -> String {
        guard let loc = location else { return query.lowercased().trimmingCharacters(in: .whitespaces) }
        let lat = (loc.coordinate.latitude * 1000).rounded() / 1000
        let lng = (loc.coordinate.longitude * 1000).rounded() / 1000
        return "\(query.lowercased().trimmingCharacters(in: .whitespaces))_\(lat)_\(lng)"
    }

    private init() {}

    /// Performs autocomplete search for places using a single 10km radius request with response caching.
    /// - Parameters:
    ///   - query: The search query text
    ///   - location: Optional user location for location bias
    ///   - completion: Completion handler with results or error
    func autocomplete(
        query: String,
        location: CLLocation? = nil,
        completion: @escaping (Result<[PlaceAutocompleteResult], Error>) -> Void
    ) {
        // Check cache first
        let cacheKey = autocompleteCacheKey(query: query, location: location)
        if let cached = autocompleteCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < autocompleteCacheTTL {
            print("Places API: Cache hit for '\(query)' (\(cached.results.count) results)")
            completion(.success(cached.results))
            return
        }

        // Single request with 10km radius
        performAutocompleteRequest(query: query, location: location, radius: 10000.0) { [weak self] result in
            switch result {
            case .success(let results):
                print("Places API: Request returned \(results.count) results")
                if let location = location {
                    self?.sortResultsByDistance(results, userLocation: location) { sortedResults in
                        let limited = Array(sortedResults.prefix(10))
                        // Store in cache
                        self?.autocompleteCache[cacheKey] = (results: limited, timestamp: Date())
                        completion(.success(limited))
                    }
                } else {
                    let limited = Array(results.prefix(10))
                    self?.autocompleteCache[cacheKey] = (results: limited, timestamp: Date())
                    completion(.success(limited))
                }
            case .failure(let error):
                completion(.failure(error))
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
        
        // Note: Field mask is optional for autocomplete - try without it first
        // If needed, uncomment and adjust format:
        // request.setValue("suggestions.placePrediction.placeId,suggestions.placePrediction.text", forHTTPHeaderField: "X-Goog-FieldMask")
        
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
                        types: nil
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
        
        // Request specific fields to optimize response
        let fieldMask = [
            "places.id",
            "places.displayName",
            "places.formattedAddress",
            "places.shortFormattedAddress",
            "places.addressComponents",
            "places.location",
            "places.types",
            "places.rating",
            "places.photos"
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
        
        print("📸 PlacesAPIService: Converted \(spots.count) spots. Spots with photos: \(spots.filter { $0.photoReference != nil }.count)")
        
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
    
    /// Fetches place details by placeId from Google Places API
    /// Used for getting details of tapped POI markers
    /// - Parameter placeId: The Google Place ID
    /// - Returns: NearbySpot with full details, or nil if not found
    func fetchPlaceDetails(placeId: String) async throws -> NearbySpot? {
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
        
        // Request specific fields
        let fieldMask = [
            "id",
            "displayName",
            "formattedAddress",
            "shortFormattedAddress",
            "location",
            "types",
            "rating",
            "photos"
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
        
        return placeResponse.toNearbySpot()
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
    
    enum CodingKeys: String, CodingKey {
        case placeId = "placeId"
        case text
        case structuredFormat
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
                queue.async {
                    resultsWithCoordinates.append(result.withCoordinate(cached))
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

        group.notify(queue: .main) {
            let resultsWithoutCoordinates = results.filter { result in
                !resultsToFetch.contains { $0.placeId == result.placeId }
            }
            completion(resultsWithCoordinates + resultsWithoutCoordinates)
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
        // Filter to spots that need uploading
        var spotsToUpload: [(spot: NearbySpot, photoReference: String)] = []
        for spot in spots {
            guard let photoReference = spot.photoReference else { continue }
            if await checkPhotoExists(placeId: spot.placeId) {
                print("✅ PlacesAPIService: Photo already cached for \(spot.name)")
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
                updated_at: ISO8601DateFormatter().string(from: Date())
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
        do {
            let supabase = SupabaseManager.shared.client
            
            struct SpotPhotoCheck: Codable {
                let photo_url: String?
            }
            
            let response: [SpotPhotoCheck] = try await supabase
                .from("spots")
                .select("photo_url")
                .eq("place_id", value: placeId)
                .limit(1)
                .execute()
                .value
            
            if let url = response.first?.photo_url, !url.isEmpty {
                return url
            }
            return nil
        } catch {
            return nil
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
                let latitude: Double?
                let longitude: Double?
                let types: [String]?
                let photo_url: String?
                let photo_reference: String?
            }
            
            let response: [CachedSpotRow] = try await supabase
                .from("spots")
                .select("place_id, name, address, latitude, longitude, types, photo_url, photo_reference")
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
                city: nil, // Not available from cached spot row
                category: category,
                rating: nil,
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
            updated_at: ISO8601DateFormatter().string(from: Date())
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


