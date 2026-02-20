//
//  PlaceAutocompleteResult.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation
import CoreLocation

struct PlaceAutocompleteResult: Identifiable {
    let id: String // place_id from Google
    let placeId: String
    let name: String
    let address: String
    let types: [String]?
    var coordinate: CLLocationCoordinate2D? // Optional coordinate for distance calculation
    var photoUrl: String?        // Supabase cached photo URL (if available)
    var photoReference: String?  // Google Places photo reference (for fallback)
    
    init(placeId: String, name: String, address: String, types: [String]? = nil, coordinate: CLLocationCoordinate2D? = nil, photoUrl: String? = nil, photoReference: String? = nil) {
        self.id = placeId
        self.placeId = placeId
        self.name = name
        self.address = address
        self.types = types
        self.coordinate = coordinate
        self.photoUrl = photoUrl
        self.photoReference = photoReference
    }
    
    // Create a copy with updated coordinate
    func withCoordinate(_ coordinate: CLLocationCoordinate2D?) -> PlaceAutocompleteResult {
        var result = self
        result.coordinate = coordinate
        return result
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

