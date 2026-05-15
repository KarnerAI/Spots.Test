//
//  Follow.swift
//  Spots.Test
//
//  Models for the social follow graph. Mirrors the `follows` table and
//  derives a viewer-centric `FollowRelationship` for UI rendering.
//

import Foundation

enum FollowStatus: String, Codable {
    case pending
    case accepted
}

struct Follow: Codable, Hashable {
    let followerId: UUID
    let followeeId: UUID
    let status: FollowStatus
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case followerId = "follower_id"
        case followeeId = "followee_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Viewer-centric description of the relationship between the current user and a target user.
/// Drives the Follow / Requested / Following button states.
enum FollowRelationship: Equatable {
    case none          // viewer is not following the target
    case requested     // viewer has a pending follow request awaiting target's approval
    case following     // viewer follows target (accepted)
    case followsYou    // target follows viewer, viewer does not follow target
    case mutual        // both follow each other (accepted both directions)
    case isSelf        // target is the viewer

    /// Whether the viewer is currently following or has requested to follow.
    var isOutboundActive: Bool {
        switch self {
        case .requested, .following, .mutual: return true
        case .none, .followsYou, .isSelf: return false
        }
    }

    /// Source-of-truth gate for "can the viewer see the target's spots, lists,
    /// and footprint?" Public profiles are always visible; private profiles
    /// require an accepted follow edge (or self). Mirrored server-side by the
    /// RLS policy on `spot_list_items` and the `viewer_can_see_user_activity`
    /// helper — keeping the rule in one place client-side reduces drift between
    /// what the UI reveals and what the server actually permits.
    static func canSeePrivateContent(profileIsPrivate: Bool, relationship: FollowRelationship) -> Bool {
        if !profileIsPrivate { return true }
        switch relationship {
        case .following, .mutual, .isSelf: return true
        case .none, .requested, .followsYou: return false
        }
    }
}
