//
//  FeedItem.swift
//  Spots.Test
//
//  Single feed entry returned by the `get_following_feed` Postgres RPC.
//  Three activity kinds (spot save / conversion / list created) carried in
//  a uniform shape with a discriminated payload.
//
//  spot_save and conversion share the same SpotSavePayload shape — both
//  emit a `lists` JSONB array (one element for conversion, 1..N for
//  spot_save). The renderer picks the verb based on FeedItemKind.
//

import Foundation

enum FeedItemKind: String, Codable {
    case spotSave    = "spot_save"
    case conversion  = "conversion"
    case listCreated = "list_created"
}

enum FeedItemPayload: Equatable, Hashable {
    case spotSave(SpotSavePayload)
    case conversion(SpotSavePayload)
    case listCreated(ListCreatedPayload)

    /// One list mentioned in a spot_save or conversion card. Order in the
    /// `lists` array is the order the feed RPC's per-viewer privacy CTE
    /// returned (matches the user's original save order).
    struct ListRef: Equatable, Hashable {
        let id: UUID
        let kind: ListKind?
        let name: String?

        /// Display label. System kinds use their canonical label; custom
        /// kinds fall back to the user-supplied name.
        var displayName: String {
            if let kind, kind.isSystemKind { return kind.displayName }
            return name ?? "a list"
        }
    }

    struct SpotSavePayload: Equatable, Hashable {
        /// All destination lists the viewer is allowed to see. The feed
        /// RPC's per-viewer privacy CTE filters this to only the lists
        /// visible to the current viewer (private lists owned by others
        /// don't appear here). Always non-empty — if all lists were
        /// filtered out, the row is suppressed entirely upstream.
        let lists: [ListRef]
        let spotId: String
        let otherSaversCount: Int
        let otherSavers: [OtherSaver]
    }

    struct OtherSaver: Equatable, Hashable {
        let userId: UUID
        let username: String?
        let avatarUrl: String?
    }

    struct ListCreatedPayload: Equatable, Hashable {
        let listId: UUID
        let listName: String?

        var listDisplayName: String { listName ?? "a new list" }
    }
}

struct FeedItem: Identifiable, Equatable, Hashable {
    /// Stable composite id from the RPC ("save:<uuid>" / "conv:<uuid>" /
    /// "list:<uuid>"). Used as the join key for likes/comments in Phase 2.
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
            payload = .spotSave(try Self.decodeSpotSavePayload(from: payloadDecoder))
        case .conversion:
            payload = .conversion(try Self.decodeSpotSavePayload(from: payloadDecoder))
        case .listCreated:
            let raw = try ListCreatedRaw(from: payloadDecoder)
            payload = .listCreated(.init(
                listId: raw.list_id,
                listName: raw.list_name
            ))
        }
    }

    private static func decodeSpotSavePayload(
        from decoder: Decoder
    ) throws -> FeedItemPayload.SpotSavePayload {
        let raw = try SpotSaveRaw(from: decoder)
        return .init(
            lists: raw.lists.map {
                FeedItemPayload.ListRef(id: $0.id, kind: $0.kind, name: $0.name)
            },
            spotId: raw.spot_id,
            otherSaversCount: raw.other_savers_count ?? 0,
            otherSavers: (raw.other_savers ?? []).map {
                FeedItemPayload.OtherSaver(
                    userId: $0.user_id,
                    username: $0.username,
                    avatarUrl: $0.avatar_url
                )
            }
        )
    }

    private struct SpotSaveRaw: Decodable {
        let lists: [ListRefRaw]
        let spot_id: String
        let other_savers_count: Int?
        let other_savers: [OtherSaverRaw]?
    }

    private struct ListRefRaw: Decodable {
        let id: UUID
        let kind: ListKind?
        let name: String?
    }

    private struct OtherSaverRaw: Decodable {
        let user_id: UUID
        let username: String?
        let avatar_url: String?
    }

    private struct ListCreatedRaw: Decodable {
        let list_id: UUID
        let list_name: String?
    }
}
