//
//  NearbySpot.swift
//  Spots.Test
//
//  Data model for nearby spots from Google Places Nearby Search API
//

import Foundation
import CoreLocation

struct NearbySpot: Identifiable, Equatable {
    let placeId: String
    let name: String
    let address: String
    let city: String?
    let category: String
    let rating: Double?
    let photoReference: String?
    var photoUrl: String?
    let latitude: Double
    let longitude: Double
    
    var id: String { placeId }
    
    // Distance is computed based on user location
    var distanceMeters: Double?
    
    /// Formatted distance string (e.g., "0.1 mi" or "250 ft")
    var formattedDistance: String {
        guard let meters = distanceMeters else { return "" }
        return DistanceCalculator.formattedDistance(meters)
    }
    
    /// Returns the best available photo URL (prefers Supabase cached URL)
    /// Returns nil if only Google API is available (requires custom loader with headers)
    func photoURL(maxWidth: Int = 400) -> URL? {
        // Prefer Supabase Storage URL if available (faster, cached, no API cost)
        if let photoUrl = photoUrl, !photoUrl.isEmpty {
            print("🖼️ NearbySpot: Using Supabase cached URL for \(name): \(photoUrl)")
            return URL(string: photoUrl)
        }
        
        // Return nil for Google API - we'll use GooglePlacesImageView instead
        // (Google Places API requires headers, not query params)
        return nil
    }
    
    /// Returns photo reference for use with GooglePlacesImageView
    func photoReferenceForGoogleAPI() -> String? {
        guard let photoReference = photoReference, !photoReference.isEmpty else {
            return nil
        }
        return photoReference
    }
    
    /// CLLocation for distance calculations
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
    
    /// Updates distance based on user location
    func withDistance(from userLocation: CLLocation) -> NearbySpot {
        var spot = self
        spot.distanceMeters = userLocation.distance(from: location)
        return spot
    }
    
    /// Converts to PlaceAutocompleteResult for use with ListPickerView
    func toPlaceAutocompleteResult() -> PlaceAutocompleteResult {
        PlaceAutocompleteResult(
            placeId: placeId,
            name: name,
            address: address,
            city: city,
            types: nil,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            photoUrl: photoUrl,
            photoReference: photoReference
        )
    }
    
    // MARK: - Category Mapping
    
    /// Maps Google Places types array to a user-friendly category string
    static func mapCategory(from types: [String]) -> String {
        // Priority order for category display
        if types.contains("restaurant") { return "Restaurant" }
        if types.contains("cafe") { return "Cafe" }
        if types.contains("bar") { return "Bar" }
        if types.contains("bakery") { return "Bakery" }
        if types.contains("food") { return "Food" }
        if types.contains("coffee_shop") || types.contains("coffee") { return "Coffee" }
        if types.contains("store") || types.contains("shopping_mall") { return "Store" }
        if types.contains("museum") { return "Museum" }
        if types.contains("park") { return "Park" }
        if types.contains("gym") || types.contains("fitness_center") { return "Gym" }
        if types.contains("spa") || types.contains("beauty_salon") { return "Spa" }
        if types.contains("hotel") || types.contains("lodging") { return "Hotel" }
        if types.contains("tourist_attraction") { return "Attraction" }
        return "Point of Interest"
    }
}

// MARK: - Google Places Nearby Search Response Models

struct NearbySearchResponse: Codable {
    let places: [NearbyPlaceResult]?
    let nextPageToken: String?
    
    enum CodingKeys: String, CodingKey {
        case places
        case nextPageToken
    }
}

struct NearbyPlaceResult: Codable {
    let id: String
    let displayName: DisplayName?
    let formattedAddress: String?
    let shortFormattedAddress: String?
    let location: PlaceLocation?
    let types: [String]?
    let rating: Double?
    let photos: [PlacePhoto]?
    let addressComponents: [AddressComponent]?
    
    struct DisplayName: Codable {
        let text: String
        let languageCode: String?
    }
    
    struct PlaceLocation: Codable {
        let latitude: Double
        let longitude: Double
    }
    
    struct PlacePhoto: Codable {
        let name: String
        let widthPx: Int?
        let heightPx: Int?
        let authorAttributions: [AuthorAttribution]?
        
        struct AuthorAttribution: Codable {
            let displayName: String?
            let uri: String?
            let photoUri: String?
        }
    }
    
    struct AddressComponent: Codable {
        let types: [String]?  // Make optional
        let longText: String?
        let shortText: String?
    }
    
    /// Converts API response to NearbySpot model
    func toNearbySpot() -> NearbySpot? {
        guard let location = location else { return nil }
        
        let name = displayName?.text ?? "Unknown"
        
        // Build street address from components (street_number + route)
        let address: String = {
            guard let components = addressComponents else {
                // Fallback to short formatted address
                return shortFormattedAddress ?? formattedAddress ?? ""
            }
            
            let streetNumber = components.first { $0.types?.contains("street_number") ?? false }?.longText
            let route = components.first { $0.types?.contains("route") ?? false }?.longText
            
            if let number = streetNumber, let street = route {
                return "\(number) \(street)"
            } else if let street = route {
                return street
            } else {
                // Fallback if components don't have street info
                return shortFormattedAddress ?? formattedAddress ?? ""
            }
        }()
        
        let category = NearbySpot.mapCategory(from: types ?? [])

        // Extract city (locality) from addressComponents
        let city = addressComponents?.first { $0.types?.contains("locality") ?? false }?.longText

        // Extract photo reference from the first photo
        // The photo name format is: "places/{placeId}/photos/{photoReference}"
        // Store the full path for the new Places API, or just the photo ID for fallback
        let photoReference = photos?.first?.name // Store full path: "places/{placeId}/photos/{photoId}"

        if photoReference == nil {
            print("⚠️ NearbySpot: No photos found for \(name) (placeId: \(id))")
        } else {
            print("✅ NearbySpot: Found photo for \(name): \(photoReference!)")
        }

        return NearbySpot(
            placeId: id,
            name: name,
            address: address,
            city: city,
            category: category,
            rating: rating,
            photoReference: photoReference,
            photoUrl: nil, // Will be populated after upload to Supabase
            latitude: location.latitude,
            longitude: location.longitude
        )
    }
}

// MARK: - Place Details Response (for single place lookup)

struct PlaceDetailsResponse: Codable {
    let id: String
    let displayName: DisplayName?
    let formattedAddress: String?
    let shortFormattedAddress: String?
    let location: PlaceLocation?
    let types: [String]?
    let rating: Double?
    let photos: [PlacePhoto]?
    
    struct DisplayName: Codable {
        let text: String
        let languageCode: String?
    }
    
    struct PlaceLocation: Codable {
        let latitude: Double
        let longitude: Double
    }
    
    struct PlacePhoto: Codable {
        let name: String
        let widthPx: Int?
        let heightPx: Int?
    }
    
    /// Converts API response to NearbySpot model
    func toNearbySpot() -> NearbySpot? {
        guard let location = location else { return nil }
        
        let name = displayName?.text ?? "Unknown"
        let address = shortFormattedAddress ?? formattedAddress ?? ""
        let category = NearbySpot.mapCategory(from: types ?? [])
        let photoReference = photos?.first?.name
        
        return NearbySpot(
            placeId: id,
            name: name,
            address: address,
            city: nil, // PlaceDetailsResponse has no addressComponents
            category: category,
            rating: rating,
            photoReference: photoReference,
            photoUrl: nil,
            latitude: location.latitude,
            longitude: location.longitude
        )
    }
}
