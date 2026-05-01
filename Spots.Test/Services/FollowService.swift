//
//  FollowService.swift
//  Spots.Test
//
//  Reads/writes the `follows` table. Server normalizes status (pending vs.
//  accepted) based on the target's `is_private` flag, so the client just
//  inserts; the BEFORE INSERT trigger decides which state lands in the row.
//

import Foundation
import Supabase

class FollowService {
    static let shared = FollowService()

    private let supabase = SupabaseManager.shared.client

    /// (viewerId, targetId) → (relationship, timestamp). 60s TTL matches ProfileService.
    private var relationshipCache: [Key: (relationship: FollowRelationship, timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 60

    private struct Key: Hashable {
        let viewerId: UUID
        let targetId: UUID
    }

    private init() {}

    // MARK: - Mutations

    /// Insert a follow edge. Returns the resolved status (accepted/pending) decided server-side.
    @discardableResult
    func follow(userId: UUID) async throws -> FollowStatus {
        let viewerId = try await getCurrentUserId()
        guard viewerId != userId else { throw FollowServiceError.cannotFollowSelf }

        struct InsertRow: Encodable {
            let follower_id: String
            let followee_id: String
            // status is normalized server-side; we send "pending" as a hint, server overwrites if needed.
            let status: String
        }

        let row = InsertRow(
            follower_id: viewerId.uuidString,
            followee_id: userId.uuidString,
            status: FollowStatus.pending.rawValue
        )

        let inserted: [Follow] = try await supabase
            .from("follows")
            .insert(row, returning: .representation)
            .select()
            .execute()
            .value

        let status = inserted.first?.status ?? .pending
        invalidateCache(viewerId: viewerId, targetId: userId)
        return status
    }

    func unfollow(userId: UUID) async throws {
        let viewerId = try await getCurrentUserId()
        try await supabase
            .from("follows")
            .delete()
            .eq("follower_id", value: viewerId.uuidString)
            .eq("followee_id", value: userId.uuidString)
            .execute()
        invalidateCache(viewerId: viewerId, targetId: userId)
    }

    /// Drop a follower: delete the row where `userId` follows the current user. The
    /// inverse direction of `unfollow`. Used by the Followers list X button.
    /// RLS must allow the followee (auth.uid()) to delete rows where followee_id = auth.uid().
    func removeFollower(userId: UUID) async throws {
        let viewerId = try await getCurrentUserId()
        try await supabase
            .from("follows")
            .delete()
            .eq("follower_id", value: userId.uuidString)
            .eq("followee_id", value: viewerId.uuidString)
            .execute()
        invalidateCache(viewerId: viewerId, targetId: userId)
    }

    /// Approve a pending follow request from `userId` (the requesting follower).
    func acceptRequest(from userId: UUID) async throws {
        let viewerId = try await getCurrentUserId()
        struct UpdateRow: Encodable { let status: String }
        try await supabase
            .from("follows")
            .update(UpdateRow(status: FollowStatus.accepted.rawValue))
            .eq("follower_id", value: userId.uuidString)
            .eq("followee_id", value: viewerId.uuidString)
            .execute()
        invalidateCache(viewerId: userId, targetId: viewerId)
    }

    /// Reject a pending follow request — deletes the follow row entirely.
    func rejectRequest(from userId: UUID) async throws {
        let viewerId = try await getCurrentUserId()
        try await supabase
            .from("follows")
            .delete()
            .eq("follower_id", value: userId.uuidString)
            .eq("followee_id", value: viewerId.uuidString)
            .execute()
        invalidateCache(viewerId: userId, targetId: viewerId)
    }

    // MARK: - Reads

    /// Viewer-centric relationship between the current user and `userId`.
    func relationship(with userId: UUID, forceRefresh: Bool = false) async throws -> FollowRelationship {
        let viewerId = try await getCurrentUserId()
        if viewerId == userId { return .isSelf }

        let key = Key(viewerId: viewerId, targetId: userId)
        if !forceRefresh,
           let entry = relationshipCache[key],
           Date().timeIntervalSince(entry.timestamp) < cacheTTL {
            return entry.relationship
        }

        // Pull both directions in one round-trip — viewer↔target.
        let edges: [Follow] = try await supabase
            .from("follows")
            .select()
            .or("and(follower_id.eq.\(viewerId.uuidString),followee_id.eq.\(userId.uuidString)),and(follower_id.eq.\(userId.uuidString),followee_id.eq.\(viewerId.uuidString))")
            .execute()
            .value

        let outbound = edges.first { $0.followerId == viewerId && $0.followeeId == userId }
        let inbound = edges.first { $0.followerId == userId && $0.followeeId == viewerId }

        let relationship: FollowRelationship
        switch (outbound?.status, inbound?.status) {
        case (.accepted, .accepted): relationship = .mutual
        case (.accepted, _):         relationship = .following
        case (.pending, _):          relationship = .requested
        case (nil, .accepted):       relationship = .followsYou
        case (nil, .pending):        relationship = .none      // their request to us is irrelevant for the button
        case (nil, nil):             relationship = .none
        }

        relationshipCache[key] = (relationship, Date())
        return relationship
    }

    /// Pending follow requests addressed to the current user, with the requester's profile.
    /// `limit` caps how many rows are fetched server-side; pass a small value when you only
    /// need a preview (e.g. one row to render the "sherlock.holmes + N others" summary).
    func pendingRequests(limit: Int = 100) async throws -> [PendingRequest] {
        let viewerId = try await getCurrentUserId()

        let rows: [Follow] = try await supabase
            .from("follows")
            .select()
            .eq("followee_id", value: viewerId.uuidString)
            .eq("status", value: FollowStatus.pending.rawValue)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        guard !rows.isEmpty else { return [] }

        let profiles = try await ProfileService.shared.fetchProfiles(ids: rows.map(\.followerId))
        let profilesById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        return rows.compactMap { follow -> PendingRequest? in
            guard let profile = profilesById[follow.followerId] else { return nil }
            return PendingRequest(profile: profile, requestedAt: follow.createdAt ?? Date())
        }
    }

    /// Number of pending requests inbound to the current user. Used for the toolbar badge.
    func pendingRequestCount() async throws -> Int {
        let viewerId = try await getCurrentUserId()
        struct Row: Decodable { let follower_id: String }
        let rows: [Row] = try await supabase
            .from("follows")
            .select("follower_id")
            .eq("followee_id", value: viewerId.uuidString)
            .eq("status", value: FollowStatus.pending.rawValue)
            .execute()
            .value
        return rows.count
    }

    // MARK: - Lists

    /// One page of a follow-graph list. `nextCursor` is the `created_at` of the last
    /// row; pass it to the next call's `before` parameter to fetch the next page.
    /// `nextCursor` is nil when the page is empty (no further pages exist).
    struct FollowListPage: Equatable {
        var profiles: [UserProfile]
        var nextCursor: Date?
    }

    /// Accepted followers of `userId` (people who follow them), newest-first.
    /// `query` filters server-side by username/first_name/last_name (ILIKE substring).
    /// `before` is a cursor on `follows.created_at`; pass the last page's `nextCursor`
    /// to fetch the next page. `limit` caps page size.
    func followers(
        userId: UUID,
        query: String? = nil,
        limit: Int = 50,
        before: Date? = nil
    ) async throws -> FollowListPage {
        try await fetchFollowList(
            userId: userId,
            direction: .followers,
            query: query,
            limit: limit,
            before: before
        )
    }

    /// Users `userId` follows (accepted), newest-first.
    /// See `followers(...)` for parameter semantics.
    func following(
        userId: UUID,
        query: String? = nil,
        limit: Int = 50,
        before: Date? = nil
    ) async throws -> FollowListPage {
        try await fetchFollowList(
            userId: userId,
            direction: .following,
            query: query,
            limit: limit,
            before: before
        )
    }

    private enum FollowDirection {
        case followers   // rows where followee_id == userId; resolve follower_id
        case following   // rows where follower_id == userId; resolve followee_id
    }

    private func fetchFollowList(
        userId: UUID,
        direction: FollowDirection,
        query: String?,
        limit: Int,
        before: Date?
    ) async throws -> FollowListPage {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuery = !(trimmed?.isEmpty ?? true)

        // When searching, narrow the profile id space first so we can intersect
        // server-side. No client-side filtering — works regardless of total count.
        // Cap at 200 to stay under PostgREST's URL length ceiling (~8KB) when this
        // list flows into the follows.in() filter. 200 UUIDs ≈ 7.4KB. Above that,
        // a search like "a" matching thousands of profiles would silently 414.
        var matchingIds: [String]? = nil
        if hasQuery, let q = trimmed {
            struct IdRow: Decodable { let id: UUID }
            let pattern = "%\(q)%"
            let profileRows: [IdRow] = try await supabase
                .from("profiles")
                .select("id")
                .or("username.ilike.\(pattern),first_name.ilike.\(pattern),last_name.ilike.\(pattern)")
                .order("username", ascending: true)
                .limit(200)
                .execute()
                .value
            if profileRows.isEmpty { return FollowListPage(profiles: [], nextCursor: nil) }
            matchingIds = profileRows.map { $0.id.uuidString }
        }

        let pivotColumn: String
        switch direction {
        case .followers: pivotColumn = "followee_id"
        case .following: pivotColumn = "follower_id"
        }
        let resolveColumn: String
        switch direction {
        case .followers: resolveColumn = "follower_id"
        case .following: resolveColumn = "followee_id"
        }

        var followQuery = supabase
            .from("follows")
            .select()
            .eq(pivotColumn, value: userId.uuidString)
            .eq("status", value: FollowStatus.accepted.rawValue)

        if let matchingIds {
            followQuery = followQuery.in(resolveColumn, values: matchingIds)
        }
        if let before {
            followQuery = followQuery.lt("created_at", value: Self.cursorFormatter.string(from: before))
        }

        let rows: [Follow] = try await followQuery
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        guard !rows.isEmpty else { return FollowListPage(profiles: [], nextCursor: nil) }

        let resolveIds: [UUID] = rows.map {
            switch direction {
            case .followers: return $0.followerId
            case .following: return $0.followeeId
            }
        }

        let profiles = try await ProfileService.shared.fetchProfiles(ids: resolveIds)
        let profilesById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let ordered = resolveIds.compactMap { profilesById[$0] }
        return FollowListPage(profiles: ordered, nextCursor: rows.last?.createdAt)
    }

    /// ISO8601 with fractional seconds — Supabase's PostgREST expects this shape for
    /// timestamptz columns when filtering via query string.
    private static let cursorFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Counts

    /// Both counts in one RPC round-trip; cached together with 60s TTL.
    /// Backed by `get_follow_counts` (SECURITY DEFINER) which uses COUNT(*)
    /// against the (follower_id, status) and (followee_id, status) composite
    /// indexes. Cheaper than the previous per-side SELECT-and-count-rows
    /// pattern both in network bytes and DB work.
    func counts(userId: UUID, forceRefresh: Bool = false) async throws -> (followers: Int, following: Int) {
        if !forceRefresh,
           let cached = countsCache[userId],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return (cached.followers, cached.following)
        }
        struct CountsRow: Codable { let followers: Int; let following: Int }
        let rows: [CountsRow] = try await supabase
            .rpc("get_follow_counts", params: ["p_user_id": userId.uuidString])
            .execute()
            .value
        let f = rows.first?.followers ?? 0
        let g = rows.first?.following ?? 0
        countsCache[userId] = (f, g, Date())
        return (f, g)
    }

    private var countsCache: [UUID: (followers: Int, following: Int, timestamp: Date)] = [:]

    // MARK: - Cache

    func invalidateCache(viewerId: UUID? = nil, targetId: UUID? = nil) {
        guard let viewerId, let targetId else {
            relationshipCache.removeAll()
            countsCache.removeAll()
            return
        }
        relationshipCache[Key(viewerId: viewerId, targetId: targetId)] = nil
        relationshipCache[Key(viewerId: targetId, targetId: viewerId)] = nil
        countsCache[viewerId] = nil
        countsCache[targetId] = nil
    }

    // MARK: - Helpers

    private func getCurrentUserId() async throws -> UUID {
        try await supabase.auth.session.user.id
    }
}

// MARK: - Supporting types

struct PendingRequest: Identifiable, Equatable {
    let profile: UserProfile
    let requestedAt: Date

    var id: UUID { profile.id }
}

enum FollowServiceError: LocalizedError {
    case cannotFollowSelf

    var errorDescription: String? {
        switch self {
        case .cannotFollowSelf: return "You can't follow yourself."
        }
    }
}
