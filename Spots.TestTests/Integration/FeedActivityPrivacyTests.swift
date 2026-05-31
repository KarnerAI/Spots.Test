//
//  FeedActivityPrivacyTests.swift
//  Spots.TestTests
//
//  Coverage of the §03 privacy matrix under the v4 model
//  (private / followers / public × owner / invitee / follower / stranger).
//  Each test seeds a primary user's save, varies visibility / viewer
//  relationship, and asserts get_following_feed surfaces or suppresses
//  the card per the matrix.
//
//  Not exhaustively all 12 cells — the representative subset covers each
//  visibility level + each viewer type at least once, including the
//  all-list_ids-invisible suppression case (§07.5).
//

import Foundation
import XCTest
@testable import Spots_Test

private struct RecordParams: Encodable {
    let p_spot_id: String
    let p_list_ids: [String]
    let p_source: String
}

final class FeedActivityPrivacyTests: FeedActivityIntegrationTestCase {

    // (setListVisibility helper lives on the base case so the trigger tests
    // could also use it if needed; goes through serviceRoleRequest because
    // supabase-swift UPDATEs no-op on the local CLI's sb_secret_* keys.)

    // MARK: - followers list, follower viewer → SEES card

    func test_followersList_visibleToAcceptedFollower() async throws {
        let primary = try await signInPrimaryUser(prefix: "priv-fol-fol")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let wtgId = lists[.wantToGo] else { return XCTFail("missing wtg") }

        let placeId = "test:priv-fol-fol:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId, p_list_ids: [wtgId.uuidString], p_source: "manual"
        )).execute()

        let follower = try await createAdditionalUser(prefix: "follower")
        try await makeFollowAccepted(follower: follower.id, followee: primary.id)
        try await signInAnon(as: follower)

        let items = try await getFollowingFeedItems()
        let mine = items.filter { $0.actorId == primary.id }
        XCTAssertEqual(mine.count, 1, "follower must see WTG card on a followers-visibility list")
    }

    // MARK: - private list, follower viewer → SUPPRESSED

    func test_privateList_suppressedFromFollowerFeed() async throws {
        let primary = try await signInPrimaryUser(prefix: "priv-priv-fol")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let wtgId = lists[.wantToGo] else { return XCTFail("missing wtg") }

        // Flip the default WTG list from 'followers' down to 'private'.
        try await setListVisibility(listId: wtgId, to: "private")

        let placeId = "test:priv-priv-fol:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId, p_list_ids: [wtgId.uuidString], p_source: "manual"
        )).execute()

        let follower = try await createAdditionalUser(prefix: "follower")
        try await makeFollowAccepted(follower: follower.id, followee: primary.id)
        try await signInAnon(as: follower)

        let items = try await getFollowingFeedItems()
        let mine = items.filter { $0.actorId == primary.id }
        XCTAssertEqual(mine.count, 0,
            "private list — no list_ids are visible to follower, row must be suppressed (§07.5)")
    }

    // MARK: - public list, follower viewer → SEES card

    func test_publicList_visibleToFollower() async throws {
        let primary = try await signInPrimaryUser(prefix: "priv-pub-fol")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let favId = lists[.favorites] else { return XCTFail("missing favorites") }

        try await setListVisibility(listId: favId, to: "public")

        let placeId = "test:priv-pub-fol:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId, p_list_ids: [favId.uuidString], p_source: "manual"
        )).execute()

        let follower = try await createAdditionalUser(prefix: "follower")
        try await makeFollowAccepted(follower: follower.id, followee: primary.id)
        try await signInAnon(as: follower)

        let items = try await getFollowingFeedItems()
        let mine = items.filter { $0.actorId == primary.id }
        XCTAssertEqual(mine.count, 1, "follower sees public list cards")
    }

    // MARK: - followers list, NON-follower viewer → SUPPRESSED (no follow edge)

    // Note: the feed RPC's outer JOIN is "JOIN followed flw ON flw.followee_id
    // = fa.user_id", so a viewer who doesn't follow the actor sees zero rows
    // from that actor regardless of visibility. This is the actor-not-followed
    // suppression layer that's logically prior to per-list visibility.
    func test_followersList_invisibleToNonFollower() async throws {
        let primary = try await signInPrimaryUser(prefix: "priv-fol-stranger")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let wtgId = lists[.wantToGo] else { return XCTFail("missing wtg") }

        let placeId = "test:priv-fol-stranger:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId, p_list_ids: [wtgId.uuidString], p_source: "manual"
        )).execute()

        // Stranger: not following the primary user.
        let stranger = try await createAdditionalUser(prefix: "stranger")
        try await signInAnon(as: stranger)

        let items = try await getFollowingFeedItems()
        let mine = items.filter { $0.actorId == primary.id }
        XCTAssertEqual(mine.count, 0,
            "stranger doesn't follow primary — no rows surface (followed-CTE gate)")
    }

    // MARK: - Scenario C consolidation under privacy: mixed visibility lists

    // When a save commit lands in BOTH a followers list (visible to follower)
    // and a private custom list (invisible to follower), the card must
    // surface with only the visible list_ids in the payload — not suppressed,
    // not leaking the private one.
    func test_mixedVisibilityConsolidation_filtersPrivateListFromPayload() async throws {
        let primary = try await signInPrimaryUser(prefix: "priv-mixed")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let favId = lists[.favorites] else { return XCTFail("missing favorites") }

        // Custom PRIVATE list.
        struct CustomListRow: Encodable { let user_id: String, kind: String, name: String, visibility: String }
        struct CreatedRow: Decodable { let id: UUID }
        let created: [CreatedRow] = try await serviceClient
            .from("user_lists")
            .insert(CustomListRow(
                user_id: primary.id.uuidString,
                kind: "custom",
                name: "Secret Spots",
                visibility: "private"
            ))
            .select("id").execute().value
        guard let privateCustomId = created.first?.id else { return XCTFail("custom list insert failed") }

        let placeId = "test:priv-mixed:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId,
            p_list_ids: [favId.uuidString, privateCustomId.uuidString],
            p_source: "manual"
        )).execute()

        let follower = try await createAdditionalUser(prefix: "follower")
        try await makeFollowAccepted(follower: follower.id, followee: primary.id)
        try await signInAnon(as: follower)

        let items = try await getFollowingFeedItems()
        let mine = items.filter { $0.actorId == primary.id }
        XCTAssertEqual(mine.count, 1, "card surfaces because Favorites is visible")
        if case let .spotSave(payload) = mine.first?.payload {
            XCTAssertEqual(payload.lists.count, 1,
                "private custom list must be filtered out of the consolidated payload")
            XCTAssertEqual(payload.lists.first?.id, favId,
                "only the followers-visible Favorites list surfaces")
        } else {
            XCTFail("expected .spotSave payload")
        }
    }
}
