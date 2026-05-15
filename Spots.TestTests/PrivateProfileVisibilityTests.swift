//
//  PrivateProfileVisibilityTests.swift
//  Spots.TestTests
//
//  Truth-table coverage for `FollowRelationship.canSeePrivateContent(...)` —
//  the single source of truth for "can the viewer see this user's spots,
//  lists, and footprint?" Mirrored server-side by RLS, so any client UI
//  bug here is a divergence from server behavior.
//
//  Scope note: the eng-review test plan also called for unit tests of
//  `ProfileService.updateIsPrivate` and `FollowService` cache invalidation.
//  Both require either a `ProfileServiceProtocol` mock layer (does not exist
//  yet — would need a new abstraction) or bumping FollowService's `private`
//  cache fields to `internal` for `@testable` access. Both decisions are out
//  of scope for this PR; flagged as follow-ups in the plan's TODOs. The
//  canSeeContent rule is the most consequential of the three (it gates real
//  content visibility, while the other two are convenience layers) and is
//  fully covered here.
//

import Testing
import Foundation
@testable import Spots_Test

struct PrivateProfileVisibilityTests {

    // MARK: - Public profiles: always visible regardless of relationship

    @Test
    func publicProfile_anyRelationship_isVisible() {
        for rel in allRelationships {
            #expect(
                FollowRelationship.canSeePrivateContent(profileIsPrivate: false, relationship: rel) == true,
                "Public profile must be visible for relationship \(rel)"
            )
        }
    }

    // MARK: - Private profiles: only accepted-follow states see content

    @Test
    func privateProfile_following_isVisible() {
        #expect(
            FollowRelationship.canSeePrivateContent(profileIsPrivate: true, relationship: .following) == true
        )
    }

    @Test
    func privateProfile_mutual_isVisible() {
        #expect(
            FollowRelationship.canSeePrivateContent(profileIsPrivate: true, relationship: .mutual) == true
        )
    }

    @Test
    func privateProfile_isSelf_isVisible() {
        #expect(
            FollowRelationship.canSeePrivateContent(profileIsPrivate: true, relationship: .isSelf) == true
        )
    }

    // MARK: - Private profiles: non-accepted states are blocked

    @Test
    func privateProfile_none_isBlocked() {
        #expect(
            FollowRelationship.canSeePrivateContent(profileIsPrivate: true, relationship: .none) == false
        )
    }

    @Test
    func privateProfile_requested_isBlocked() {
        // Pending request is the easiest one to get wrong — "they sent a
        // request, surely they can peek?" No: until the target accepts,
        // they're indistinguishable from a stranger for content purposes.
        #expect(
            FollowRelationship.canSeePrivateContent(profileIsPrivate: true, relationship: .requested) == false
        )
    }

    @Test
    func privateProfile_followsYou_isBlocked() {
        // The target follows the viewer, but the viewer doesn't follow back.
        // Asymmetric follow does not grant content access — only the viewer's
        // outbound accepted edge does.
        #expect(
            FollowRelationship.canSeePrivateContent(profileIsPrivate: true, relationship: .followsYou) == false
        )
    }

    // MARK: - Helper

    private var allRelationships: [FollowRelationship] {
        [.none, .requested, .following, .followsYou, .mutual, .isSelf]
    }
}
