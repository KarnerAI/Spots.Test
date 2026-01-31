//
//  Spot.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation

struct Spot: Codable, Identifiable {
    let placeId: String
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let types: [String]?
    let photoUrl: String?
    let photoReference: String?
    let createdAt: Date?
    let updatedAt: Date?
    
    var id: String { placeId }
    
    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case name
        case address
        case latitude
        case longitude
        case types
        case photoUrl = "photo_url"
        case photoReference = "photo_reference"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

