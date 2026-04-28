//
//  FeedService.swift
//  Spots.Test
//
//  Reads the following-only feed via the `get_following_feed` Postgres RPC.
//  Also batch-loads the actor profiles + spot details that feed cards need
//  to render, so the UI doesn't have to do N+1 fetches.
//

import Foundation
import Supabase

class FeedService {
    static let shared = FeedService()

    private let supabase = SupabaseManager.shared.client

    private init() {}

    /// Fetch a page of feed items ordered most-recent first.
    /// - Parameters:
    ///   - cursor: createdAt of the last item from the previous page. Pass nil for the first page.
    ///   - limit: max items to return (clamped to 100 server-side).
    func fetchFeed(cursor: Date? = nil, limit: Int = 20) async throws -> [FeedItem] {
        struct Params: Encodable {
            let p_cursor: String?
            let p_limit: Int

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_limit, forKey: .p_limit)
                if let cursor = p_cursor {
                    try c.encode(cursor, forKey: .p_cursor)
                } else {
                    try c.encodeNil(forKey: .p_cursor)
                }
            }

            enum CodingKeys: String, CodingKey {
                case p_cursor, p_limit
            }
        }

        let params = Params(
            p_cursor: cursor.map { ISO8601DateFormatter.fractionalSeconds.string(from: $0) },
            p_limit: limit
        )

        let items: [FeedItem] = try await supabase
            .rpc("get_following_feed", params: params)
            .execute()
            .value
        return items
    }

    /// Batch-load the spot rows referenced by a page of feed items.
    /// Returns a dictionary keyed by `place_id` so cards can look up their spot in O(1).
    func loadSpots(for items: [FeedItem]) async throws -> [String: Spot] {
        let placeIds: [String] = items.compactMap { item in
            if case .spotSave(let payload) = item.payload { return payload.spotId }
            return nil
        }
        let unique = Array(Set(placeIds))
        guard !unique.isEmpty else { return [:] }

        struct SpotResponse: Decodable {
            let place_id: String
            let name: String
            let address: String?
            let city: String?
            let latitude: Double?
            let longitude: Double?
            let types: [String]?
            let photo_url: String?
            let photo_reference: String?
            let created_at: String?
            let updated_at: String?
        }

        let rows: [SpotResponse] = try await supabase
            .from("spots")
            .select("place_id, name, address, city, latitude, longitude, types, photo_url, photo_reference, created_at, updated_at")
            .in("place_id", values: unique)
            .execute()
            .value

        var map: [String: Spot] = [:]
        for r in rows {
            map[r.place_id] = Spot(
                placeId: r.place_id,
                name: r.name,
                address: r.address,
                city: r.city,
                latitude: r.latitude,
                longitude: r.longitude,
                types: r.types,
                photoUrl: r.photo_url,
                photoReference: r.photo_reference,
                createdAt: r.created_at.flatMap { SharedFormatters.date(from: $0) },
                updatedAt: r.updated_at.flatMap { SharedFormatters.date(from: $0) }
            )
        }
        return map
    }

    /// Batch-load the actor profiles for a page of feed items.
    func loadActors(for items: [FeedItem]) async throws -> [UUID: UserProfile] {
        let actorIds = items.map(\.actorId)
        let profiles = try await ProfileService.shared.fetchProfiles(ids: actorIds)
        return Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }
}
