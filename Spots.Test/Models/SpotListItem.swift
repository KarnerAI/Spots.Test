//
//  SpotListItem.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation

/// Mirrors the DB enum `public.spot_list_item_source_enum`. Captures the
/// provenance of a spot save (decision E8). `manual` is the default for
/// user-driven saves; `import_*` values are set by each import flow so
/// analytics can answer "which import sources actually convert?"
enum SpotSaveSource: String, Codable, CaseIterable {
    case manual = "manual"
    case importInstagram = "import_instagram"
    case importGoogleMaps = "import_google_maps"
    case importAppleNotes = "import_apple_notes"
    case importSubstack = "import_substack"
    case importVoice = "import_voice"
    case importText = "import_text"
    case importYelp = "import_yelp"
    case importBeli = "import_beli"
}

struct SpotListItem: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let spotId: String
    let listId: UUID
    let savedAt: Date
    let source: SpotSaveSource

    enum CodingKeys: String, CodingKey {
        case id
        case spotId = "spot_id"
        case listId = "list_id"
        case savedAt = "saved_at"
        case source
    }

    /// Custom decoder so rows from before the Phase 1 migration (no `source`
    /// column) decode as `.manual`, matching the column's DB default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.spotId = try c.decode(String.self, forKey: .spotId)
        self.listId = try c.decode(UUID.self, forKey: .listId)
        self.savedAt = try c.decode(Date.self, forKey: .savedAt)
        self.source = try c.decodeIfPresent(SpotSaveSource.self, forKey: .source) ?? .manual
    }

    init(id: UUID, spotId: String, listId: UUID, savedAt: Date, source: SpotSaveSource = .manual) {
        self.id = id
        self.spotId = spotId
        self.listId = listId
        self.savedAt = savedAt
        self.source = source
    }
}

// Combined model for UI (spot + metadata)
struct SpotWithMetadata: Identifiable, Equatable, Hashable {
    let spot: Spot
    let savedAt: Date
    /// System-kind lists this spot belongs to (favorites / liked / wantToGo).
    /// Custom / trip / date_plan kinds are intentionally excluded — this set
    /// drives marker icons and tier badges, which only use system kinds.
    let listKinds: Set<ListKind>

    var id: String { spot.id }
}

// MARK: - Conversion to NearbySpot

extension SpotWithMetadata {
    /// Converts to NearbySpot for use with SpotCardView (floating card on map).
    func toNearbySpot() -> NearbySpot {
        NearbySpot(
            placeId: spot.placeId,
            name: spot.name,
            address: spot.address ?? "",
            city: spot.city,
            locality: spot.locality,
            category: NearbySpot.mapCategory(from: spot.types ?? []),
            rating: nil,
            photoReference: spot.photoReference,
            photoUrl: spot.photoUrl,
            latitude: spot.latitude ?? 0,
            longitude: spot.longitude ?? 0
        )
    }
}
