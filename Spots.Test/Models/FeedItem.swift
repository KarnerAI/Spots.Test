//
//  FeedItem.swift
//  Spots.Test
//
//  Single feed entry returned by the `get_following_feed` Postgres RPC.
//  Two activity kinds (spot save / list created) carried in a uniform shape
//  with a discriminated payload.
//

import Foundation

enum FeedItemKind: String, Codable {
    case spotSave = "spot_save"
    case listCreated = "list_created"
}

enum FeedItemPayload: Equatable, Hashable {
    case spotSave(SpotSavePayload)
    case listCreated(ListCreatedPayload)

    struct SpotSavePayload: Equatable, Hashable {
        let listId: UUID
        let listType: ListType?
        let listName: String?
        let spotId: String

        /// Display label for the destination list ("Favorites", or the custom list's name).
        var listDisplayName: String {
            if let listType { return listType.displayName }
            return listName ?? "a list"
        }
    }

    struct ListCreatedPayload: Equatable, Hashable {
        let listId: UUID
        let listName: String?

        var listDisplayName: String { listName ?? "a new list" }
    }
}

struct FeedItem: Identifiable, Equatable, Hashable {
    /// Stable composite id from the RPC ("save:<uuid>" / "list:<uuid>").
    /// Used as the join key for likes/comments in Phase 2.
    let id: String
    let actorId: UUID
    let kind: FeedItemKind
    let createdAt: Date
    let payload: FeedItemPayload
}

// MARK: - Decoding from Supabase RPC response

extension FeedItem: Decodable {
    enum CodingKeys: String, CodingKey {
        case id
        case actorId = "actor_id"
        case kind
        case createdAt = "created_at"
        case payload
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        actorId = try c.decode(UUID.self, forKey: .actorId)
        kind = try c.decode(FeedItemKind.self, forKey: .kind)

        // created_at: Supabase ships ISO8601, possibly with fractional seconds.
        let rawDate = try c.decode(String.self, forKey: .createdAt)
        guard let parsed = SharedFormatters.date(from: rawDate) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt, in: c,
                debugDescription: "Unparseable feed item timestamp: \(rawDate)"
            )
        }
        createdAt = parsed

        // payload: discriminated by `kind`.
        let payloadDecoder = try c.superDecoder(forKey: .payload)
        switch kind {
        case .spotSave:
            let raw = try SpotSaveRaw(from: payloadDecoder)
            payload = .spotSave(.init(
                listId: raw.list_id,
                listType: raw.list_type,
                listName: raw.list_name,
                spotId: raw.spot_id
            ))
        case .listCreated:
            let raw = try ListCreatedRaw(from: payloadDecoder)
            payload = .listCreated(.init(
                listId: raw.list_id,
                listName: raw.list_name
            ))
        }
    }

    private struct SpotSaveRaw: Decodable {
        let list_id: UUID
        let list_type: ListType?
        let list_name: String?
        let spot_id: String
    }

    private struct ListCreatedRaw: Decodable {
        let list_id: UUID
        let list_name: String?
    }
}
