//
//  PlaceAutocompleteResult.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation
import CoreLocation

struct PlaceAutocompleteResult: Identifiable, Codable, Equatable, Hashable {
    let id: String // place_id from Google
    let placeId: String
    let name: String
    let address: String
    /// administrative_area_level_1 ("Île-de-France"). Misnamed historical field.
    let city: String?
    /// Google Places `locality` ("Paris"). Prefer this for user-visible labels.
    let locality: String?
    let types: [String]?
    var coordinate: CLLocationCoordinate2D? // Optional coordinate for distance calculation
    var photoUrl: String?        // Supabase cached photo URL (if available)
    var photoReference: String?  // Google Places photo reference (for fallback)

    init(
        placeId: String,
        name: String,
        address: String,
        city: String? = nil,
        locality: String? = nil,
        types: [String]? = nil,
        coordinate: CLLocationCoordinate2D? = nil,
        photoUrl: String? = nil,
        photoReference: String? = nil
    ) {
        self.id = placeId
        self.placeId = placeId
        self.name = name
        self.address = address
        self.city = city
        self.locality = locality
        self.types = types
        self.coordinate = coordinate
        self.photoUrl = photoUrl
        self.photoReference = photoReference
    }

    /// User-facing city label. Mirrors `Spot.displayCity` — prefers
    /// `locality`, falls back to the misnamed `city` (region) for older
    /// rows that don't have locality populated yet.
    var displayCity: String? {
        if let trimmed = locality?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty { return trimmed }
        if let trimmed = city?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty { return trimmed }
        return nil
    }

    // MARK: - Codable (custom for CLLocationCoordinate2D)

    enum CodingKeys: String, CodingKey {
        case id, placeId, name, address, city, locality, types
        case coordinateLatitude, coordinateLongitude
        case photoUrl, photoReference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        placeId = try container.decode(String.self, forKey: .placeId)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        locality = try container.decodeIfPresent(String.self, forKey: .locality)
        types = try container.decodeIfPresent([String].self, forKey: .types)
        photoUrl = try container.decodeIfPresent(String.self, forKey: .photoUrl)
        photoReference = try container.decodeIfPresent(String.self, forKey: .photoReference)

        if let lat = try container.decodeIfPresent(Double.self, forKey: .coordinateLatitude),
           let lng = try container.decodeIfPresent(Double.self, forKey: .coordinateLongitude) {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            coordinate = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(placeId, forKey: .placeId)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encodeIfPresent(locality, forKey: .locality)
        try container.encodeIfPresent(types, forKey: .types)
        try container.encodeIfPresent(photoUrl, forKey: .photoUrl)
        try container.encodeIfPresent(photoReference, forKey: .photoReference)
        try container.encodeIfPresent(coordinate?.latitude, forKey: .coordinateLatitude)
        try container.encodeIfPresent(coordinate?.longitude, forKey: .coordinateLongitude)
    }

    // Create a copy with updated coordinate
    func withCoordinate(_ coordinate: CLLocationCoordinate2D?) -> PlaceAutocompleteResult {
        var result = self
        result.coordinate = coordinate
        return result
    }

    // MARK: - Equatable
    static func == (lhs: PlaceAutocompleteResult, rhs: PlaceAutocompleteResult) -> Bool {
        lhs.placeId == rhs.placeId
            && lhs.name == rhs.name
            && lhs.address == rhs.address
            && lhs.city == rhs.city
            && lhs.locality == rhs.locality
            && lhs.types == rhs.types
            && lhs.photoUrl == rhs.photoUrl
            && lhs.photoReference == rhs.photoReference
            && lhs.coordinate?.latitude == rhs.coordinate?.latitude
            && lhs.coordinate?.longitude == rhs.coordinate?.longitude
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(placeId)
    }
}

// Response wrapper for old Google Places API (fallback)
struct PlacesAutocompleteResponse: Codable {
    let predictions: [OldPlacePrediction]
    let status: String

    enum CodingKeys: String, CodingKey {
        case predictions
        case status
    }
}

struct OldPlacePrediction: Codable {
    let placeId: String
    let description: String
    let structuredFormatting: StructuredFormatting?

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case description
        case structuredFormatting = "structured_formatting"
    }
}

struct StructuredFormatting: Codable {
    let mainText: String
    let secondaryText: String?

    enum CodingKeys: String, CodingKey {
        case mainText = "main_text"
        case secondaryText = "secondary_text"
    }
}
