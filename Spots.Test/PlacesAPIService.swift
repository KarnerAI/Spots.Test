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
    
    private init() {}
    
    /// Performs autocomplete search for places
    /// - Parameters:
    ///   - query: The search query text
    ///   - location: Optional user location for location bias
    ///   - completion: Completion handler with results or error
    func autocomplete(
        query: String,
        location: CLLocation? = nil,
        completion: @escaping (Result<[PlaceAutocompleteResult], Error>) -> Void
    ) {
        // First, make a request with a focused radius (5km) for closest results
        // Using smaller radius to force more local, relevant results
        performAutocompleteRequest(query: query, location: location, radius: 5000.0) { [weak self] firstResult in
            switch firstResult {
            case .success(let firstResults):
                print("Places API: First request returned \(firstResults.count) results")
                
                // If we got 10 or more results, sort by distance and return
                if firstResults.count >= 10 {
                    self?.sortResultsByDistance(firstResults, userLocation: location) { sortedResults in
                        completion(.success(Array(sortedResults.prefix(10))))
                    }
                    return
                }
                
                // If we got fewer than 10 and have location, make a second request with larger radius
                // Always make second request if we have fewer than 10, even if we got exactly 5
                if firstResults.count < 10, let location = location {
                    print("Places API: First request returned \(firstResults.count) results, making second request with 15km radius")
                    self?.performAutocompleteRequest(query: query, location: location, radius: 15000.0) { secondResult in
                        switch secondResult {
                        case .success(let secondResults):
                            print("Places API: Second request returned \(secondResults.count) results")
                            
                            // Merge results, removing duplicates
                            var allResults = firstResults
                            let firstPlaceIds = Set(firstResults.map { $0.placeId })
                            
                            for result in secondResults {
                                if !firstPlaceIds.contains(result.placeId) {
                                    allResults.append(result)
                                }
                            }
                            
                            print("Places API: Total unique results after merge: \(allResults.count)")
                            
                            // If we still have fewer than 10, try a third request with even larger radius
                            if allResults.count < 10 {
                                print("Places API: Still fewer than 10 results, making third request with 25km radius")
                                self?.performAutocompleteRequest(query: query, location: location, radius: 25000.0) { thirdResult in
                                    switch thirdResult {
                                    case .success(let thirdResults):
                                        let allPlaceIds = Set(allResults.map { $0.placeId })
                                        for result in thirdResults {
                                            if !allPlaceIds.contains(result.placeId) {
                                                allResults.append(result)
                                            }
                                        }
                                        print("Places API: Final total after third request: \(allResults.count)")
                                        // Sort by distance and limit to 10
                                        self?.sortResultsByDistance(allResults, userLocation: location) { sortedResults in
                                            completion(.success(Array(sortedResults.prefix(10))))
                                        }
                                    case .failure:
                                        // Sort what we have and return
                                        self?.sortResultsByDistance(allResults, userLocation: location) { sortedResults in
                                            completion(.success(Array(sortedResults.prefix(10))))
                                        }
                                    }
                                }
                            } else {
                                // Sort by distance and limit to 10
                                self?.sortResultsByDistance(allResults, userLocation: location) { sortedResults in
                                    completion(.success(Array(sortedResults.prefix(10))))
                                }
                            }
                        case .failure:
                            // If second request fails, sort and return what we have from first request
                            print("Places API: Second request failed, sorting first results")
                            self?.sortResultsByDistance(firstResults, userLocation: location) { sortedResults in
                                completion(.success(sortedResults))
                            }
                        }
                    }
                } else {
                    // No location or already have enough, sort and return first results
                    if let location = location {
                        self?.sortResultsByDistance(firstResults, userLocation: location) { sortedResults in
                            completion(.success(sortedResults))
                        }
                    } else {
                        completion(.success(firstResults))
                    }
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
        
        // Upload images to Supabase Storage (asynchronously, don't block return)
        // Images will be checked for existence and uploaded only if needed
        Task {
            await uploadSpotImages(spots: spots)
        }
        
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
    /// Sorts results by distance from user location
    /// Fetches place coordinates if needed, then sorts by distance
    private func sortResultsByDistance(
        _ results: [PlaceAutocompleteResult],
        userLocation: CLLocation?,
        completion: @escaping ([PlaceAutocompleteResult]) -> Void
    ) {
        guard let userLocation = userLocation, !results.isEmpty else {
            // No location or no results, return as-is
            completion(results)
            return
        }
        
        // Fetch coordinates for all results
        fetchPlaceCoordinates(for: results) { resultsWithCoordinates in
            // Calculate distance and sort
            let sorted = resultsWithCoordinates.sorted { result1, result2 in
                let distance1 = self.distance(from: userLocation, to: result1)
                let distance2 = self.distance(from: userLocation, to: result2)
                return distance1 < distance2
            }
            
            completion(sorted)
        }
    }
    
    /// Fetches coordinates for multiple places using batch place details API
    private func fetchPlaceCoordinates(
        for results: [PlaceAutocompleteResult],
        completion: @escaping ([PlaceAutocompleteResult]) -> Void
    ) {
        // Limit to first 10 to avoid too many API calls
        let resultsToFetch = Array(results.prefix(10))
        
        // Use a dispatch group to coordinate multiple requests
        let group = DispatchGroup()
        var resultsWithCoordinates: [PlaceAutocompleteResult] = []
        let queue = DispatchQueue(label: "places.coordinates")
        
        for result in resultsToFetch {
            group.enter()
            fetchPlaceCoordinate(placeId: result.placeId) { coordinate in
                queue.async {
                    let updatedResult = result.withCoordinate(coordinate)
                    resultsWithCoordinates.append(updatedResult)
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            // Add results without coordinates at the end
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
        // Google Places API (New) uses placeId directly, not "places/" prefix
        let urlString = "https://places.googleapis.com/v1/places/\(placeId)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        
        // Add bundle identifier header for iOS app restrictions
        // This is required when API key has iOS app restrictions enabled
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
            
            // Try to parse response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let location = json["location"] as? [String: Any],
               let latitude = location["latitude"] as? Double,
               let longitude = location["longitude"] as? Double {
                completion(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            } else {
                // If parsing fails, return nil (we'll sort without coordinates)
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
        
        let placeLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return userLocation.distance(from: placeLocation)
    }
    
    /// Uploads spot images to Supabase Storage in the background
    /// This runs asynchronously to avoid blocking the UI
    /// Checks if image already exists before uploading to avoid duplicates
    private func uploadSpotImages(spots: [NearbySpot]) async {
        for spot in spots {
            // Only process if spot has a photo reference
            guard let photoReference = spot.photoReference else {
                continue
            }
            
            // Check if photo already exists in database
            if await checkPhotoExists(placeId: spot.placeId) {
                print("✅ PlacesAPIService: Photo already cached for \(spot.name)")
                continue
            }
            
            // Upload to Supabase Storage
            let photoUrl = await ImageStorageService.shared.uploadSpotImage(
                photoReference: photoReference,
                placeId: spot.placeId
            )
            
            if photoUrl != nil {
                print("✅ PlacesAPIService: Uploaded image for \(spot.name)")
                
                // Update database with photo URL
                await updateSpotPhotoUrl(placeId: spot.placeId, photoUrl: photoUrl, photoReference: photoReference)
            } else {
                print("⚠️ PlacesAPIService: Failed to upload image for \(spot.name)")
            }
        }
    }
    
    /// Checks if a photo URL already exists for a spot
    private func checkPhotoExists(placeId: String) async -> Bool {
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
            
            return response.first?.photo_url != nil && !(response.first?.photo_url?.isEmpty ?? true)
        } catch {
            // If error, assume photo doesn't exist and try to upload
            return false
        }
    }
    
    /// Updates spot photo URL in database
    private func updateSpotPhotoUrl(placeId: String, photoUrl: String?, photoReference: String) async {
        guard let photoUrl = photoUrl else { return }
        
        do {
            let supabase = SupabaseManager.shared.client
            try await supabase
                .from("spots")
                .update(["photo_url": photoUrl, "photo_reference": photoReference])
                .eq("place_id", value: placeId)
                .execute()
            
            print("✅ PlacesAPIService: Updated database with photo URL for \(placeId)")
        } catch {
            print("❌ PlacesAPIService: Error updating spot photo URL: \(error.localizedDescription)")
        }
    }
}


