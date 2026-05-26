//
//  FeedItem.swift
//  Spots.Test
//
//  Single feed entry returned by the `get_following_feed` Postgres RPC.
//  Three activity kinds (spot save / list created / visited) carried in a
//  uniform shape with a discriminated payload.
//

import Foundation

enum FeedItemKind: String, Codable {
    case spotSave = "spot_save"
    case listCreated = "list_created"
    /// T10: first-ever Favorites/Liked add per (user, spot). Deduped at the
    /// feed RPC layer. Replaces the spot_save card for favorites/liked
    /// adds — the RPC excludes those kinds from spot_save to avoid surfacing
    /// two near-identical cards for the same event.
    case visited = "visited"
}

enum FeedItemPayload: Equatable, Hashable {
    case spotSave(SpotSavePayload)
    case listCreated(ListCreatedPayload)
    case visited(VisitedPayload)

    struct SpotSavePayload: Equatable, Hashable {
        let listId: UUID
        /// System / custom kind of the destination list. Comes from the feed
        /// RPC's `list_kind` field (renamed from `list_type` in Phase 1).
        let listKind: ListKind?
        let listName: String?
        let spotId: String
        let otherSaversCount: Int
        let otherSavers: [OtherSaver]

        /// Display label for the destination list ("Favorites", or the custom
        /// list's name). System kinds use their canonical label; custom kinds
        /// fall back to the user-supplied name.
        var listDisplayName: String {
            if let listKind, listKind.isSystemKind { return listKind.displayName }
            return listName ?? "a list"
        }
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

    /// T10 visited payload. `listKind` will be `.favorites` or `.liked` in
    /// practice (the feed RPC filters to those kinds), but the field is
    /// nullable for forward-compat with payloads that drop the column.
    struct VisitedPayload: Equatable, Hashable {
        let listId: UUID
        let listKind: ListKind?
        let listName: String?
        let spotId: String

        /// Display label for the list the spot first landed in. Favorites or
        /// Liked use their canonical names; custom kinds (shouldn't happen
        /// here, but defensive) fall back to listName.
        var listDisplayName: String {
            if let listKind, listKind.isSystemKind { return listKind.displayName }
            return listName ?? "a list"
        }
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
                listKind: raw.list_kind,
                listName: raw.list_name,
                spotId: raw.spot_id,
                otherSaversCount: raw.other_savers_count ?? 0,
                otherSavers: (raw.other_savers ?? []).map {
                    FeedItemPayload.OtherSaver(
                        userId: $0.user_id,
                        username: $0.username,
                        avatarUrl: $0.avatar_url
                    )
                }
            ))
        case .listCreated:
            let raw = try ListCreatedRaw(from: payloadDecoder)
            payload = .listCreated(.init(
                listId: raw.list_id,
                listName: raw.list_name
            ))
        case .visited:
            let raw = try VisitedRaw(from: payloadDecoder)
            payload = .visited(.init(
                listId: raw.list_id,
                listKind: raw.list_kind,
                listName: raw.list_name,
                spotId: raw.spot_id
            ))
        }
    }

    private struct SpotSaveRaw: Decodable {
        let list_id: UUID
        /// `list_kind` field on the feed RPC payload (renamed from
        /// `list_type` in the Phase 1 / Ticket T2 migration). Nullable so a
        /// payload missing the field (legacy clients reading new-server data
        /// or vice versa) decodes as nil rather than throwing.
        let list_kind: ListKind?
        let list_name: String?
        let spot_id: String
        let other_savers_count: Int?
        let other_savers: [OtherSaverRaw]?
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

    private struct VisitedRaw: Decodable {
        let list_id: UUID
        let list_kind: ListKind?
        let list_name: String?
        let spot_id: String
    }
}
