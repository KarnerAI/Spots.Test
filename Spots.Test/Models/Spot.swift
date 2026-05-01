//
//  Spot.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation

struct Spot: Codable, Identifiable, Equatable, Hashable {
    let placeId: String
    let name: String
    let address: String?
    let city: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    let types: [String]?
    let photoUrl: String?
    let photoReference: String?
    let rating: Double?
    let createdAt: Date?
    let updatedAt: Date?

    init(
        placeId: String,
        name: String,
        address: String? = nil,
        city: String? = nil,
        country: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        types: [String]? = nil,
        photoUrl: String? = nil,
        photoReference: String? = nil,
        rating: Double? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.placeId = placeId
        self.name = name
        self.address = address
        self.city = city
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.types = types
        self.photoUrl = photoUrl
        self.photoReference = photoReference
        self.rating = rating
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var id: String { placeId }

    /// Returns a copy of this spot with non-nil fields from `other` filled in
    /// where this spot's value is missing. Used to merge live Google Places
    /// enrichment into the cached row without overwriting good data.
    func merging(missingFieldsFrom other: Spot) -> Spot {
        Spot(
            placeId: placeId,
            name: name.isEmpty ? other.name : name,
            address: address ?? other.address,
            city: city ?? other.city,
            country: country ?? other.country,
            latitude: latitude ?? other.latitude,
            longitude: longitude ?? other.longitude,
            types: (types?.isEmpty == false) ? types : other.types,
            photoUrl: photoUrl ?? other.photoUrl,
            photoReference: photoReference ?? other.photoReference,
            rating: rating ?? other.rating,
            createdAt: createdAt ?? other.createdAt,
            updatedAt: updatedAt ?? other.updatedAt
        )
    }

    /// True when the cached row is missing any of the fields the new
    /// hero feed card relies on. Drives lazy Google Places enrichment.
    var needsEnrichment: Bool {
        let hasPhoto = (photoUrl?.isEmpty == false) || (photoReference?.isEmpty == false)
        let hasCity = (city?.isEmpty == false)
        let hasCountry = (country?.isEmpty == false)
        let hasTypes = (types?.isEmpty == false)
        let hasRating = (rating != nil)
        return !(hasPhoto && hasCity && hasCountry && hasTypes && hasRating)
    }

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case name
        case address
        case city
        case country
        case latitude
        case longitude
        case types
        case photoUrl = "photo_url"
        case photoReference = "photo_reference"
        case rating
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
