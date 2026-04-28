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
    func pendingRequests() async throws -> [PendingRequest] {
        let viewerId = try await getCurrentUserId()

        let rows: [Follow] = try await supabase
            .from("follows")
            .select()
            .eq("followee_id", value: viewerId.uuidString)
            .eq("status", value: FollowStatus.pending.rawValue)
            .order("created_at", ascending: false)
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

    // MARK: - Cache

    func invalidateCache(viewerId: UUID? = nil, targetId: UUID? = nil) {
        guard let viewerId, let targetId else {
            relationshipCache.removeAll()
            return
        }
        relationshipCache[Key(viewerId: viewerId, targetId: targetId)] = nil
        relationshipCache[Key(viewerId: targetId, targetId: viewerId)] = nil
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
