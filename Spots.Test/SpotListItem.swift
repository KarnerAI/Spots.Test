//
//  SpotListItem.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation

struct SpotListItem: Codable, Identifiable {
    let id: UUID
    let spotId: String
    let listId: UUID
    let savedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case spotId = "spot_id"
        case listId = "list_id"
        case savedAt = "saved_at"
    }
}

// Combined model for UI (spot + metadata)
struct SpotWithMetadata: Identifiable {
    let spot: Spot
    let savedAt: Date
    let listTypes: Set<ListType>  // All lists this spot belongs to
    
    var id: String { spot.id }
}

