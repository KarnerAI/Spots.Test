//
//  FeedActivityTriggerTests.swift
//  Spots.TestTests
//
//  MANDATORY regressions per the PR-B eng review (§09 of
//  0. Strategy/spots-newsfeed-activity-model.html). Two pieces of
//  behavior that MUST hold or the whole PR is unsafe to ship:
//
//    (a) Deferred cleanup trigger no-op during the move RPC pattern.
//        The move RPC does DELETE+INSERT in one transaction; an
//        immediate-fire trigger would see save-count=0 mid-transaction
//        and incorrectly delete the feed_activities row. The
//        CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED design
//        defers cleanup to COMMIT, by which time the INSERT has landed.
//
//    (b) Scenario E v3 end-to-end. A WTG -> Favorites/Liked conversion
//        must produce TWO feed_activities rows for the same (user, spot)
//        — one kind=spot_save (the original wants-to-go card) and one
//        kind=conversion (the new "favorited" card). Both must surface
//        in a follower's get_following_feed.
//
//  If you "fix" the deferred trigger to immediate/row-level, (a) will
//  fail. If you change the UNIQUE constraint on feed_activities back to
//  (user_id, spot_id), (b) will fail.
//

import Foundation
import XCTest
@testable import Spots_Test

final class FeedActivityTriggerTests: FeedActivityIntegrationTestCase {

    // MARK: - (a) Mandatory: deferred trigger no-op during move RPC

    func test_deferredTriggerStaysSilentDuringMoveRpc() async throws {
        let primary = try await signInPrimaryUser(prefix: "primary-trigger")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let wtgId = lists[.wantToGo], let favoritesId = lists[.favorites] else {
            return XCTFail("missing default lists for primary user")
        }

        let placeId = "test:trigger-deferred:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId, name: "Trigger Test Spot")

        // Seed: record first save into WTG. This writes one feed_activities
        // (kind=spot_save) row and one spot_list_items row.
        struct RecordParams: Encodable {
            let p_spot_id: String
            let p_list_ids: [String]
            let p_source: String
        }
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId,
            p_list_ids: [wtgId.uuidString],
            p_source: "manual"
        )).execute()

        let beforeMove = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(beforeMove.count, 1, "seed: exactly one spot_save row")
        XCTAssertEqual(beforeMove.first?.kind, "spot_save")

        // The move: DELETE the WTG row + INSERT the Favorites row in ONE
        // transaction. If the cleanup trigger fired immediately on the
        // DELETE, save-count for (primary, spot) would be 0 at that
        // moment and the spot_save row would be deleted. DEFERRABLE
        // INITIALLY DEFERRED is the load-bearing fix.
        struct MoveParams: Encodable {
            let p_spot_id: String
            let p_from_list_id: String?
            let p_to_list_id: String?
            let p_source: String
        }
        try await anonClient.rpc("move_spot_between_lists", params: MoveParams(
            p_spot_id: placeId,
            p_from_list_id: wtgId.uuidString,
            p_to_list_id: favoritesId.uuidString,
            p_source: "manual"
        )).execute()

        let afterMove = try await getFeedActivities(forUserId: primary.id)

        // Expectation: the original spot_save row survived (deferred trigger
        // saw post-COMMIT state with the Favorites INSERT already in place,
        // so save-count > 0 and no cleanup fired). Additionally, the
        // conversion trigger on list_moves fired its own row.
        let spotSaveRows = afterMove.filter { $0.kind == "spot_save" }
        let conversionRows = afterMove.filter { $0.kind == "conversion" }

        XCTAssertEqual(spotSaveRows.count, 1,
            "deferred cleanup must NOT have deleted the original spot_save row during the move tx")
        XCTAssertEqual(spotSaveRows.first?.id, beforeMove.first?.id,
            "the surviving spot_save row must be the original one, same UUID")
        XCTAssertEqual(conversionRows.count, 1,
            "the conversion trigger on list_moves should have fired exactly one new row")
        XCTAssertEqual(conversionRows.first?.list_ids, [favoritesId],
            "conversion row's list_ids should be the destination favorites list")
    }

    // MARK: - (b) Mandatory: Scenario E v3 end-to-end

    func test_scenarioE_v3_wtgToFavoritesConversion_writesBothCardsAndBothSurfaceInFollowerFeed() async throws {
        let primary = try await signInPrimaryUser(prefix: "primary-scenE")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let wtgId = lists[.wantToGo], let favoritesId = lists[.favorites] else {
            return XCTFail("missing default lists for primary user")
        }

        let placeId = "test:scenario-e:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId, name: "Sagrada Família")

        // Day 1: WTG save -> spot_save card fires.
        struct RecordParams: Encodable {
            let p_spot_id: String
            let p_list_ids: [String]
            let p_source: String
        }
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId,
            p_list_ids: [wtgId.uuidString],
            p_source: "manual"
        )).execute()

        // Day 2: convert WTG -> Favorites via move RPC -> conversion card fires.
        struct MoveParams: Encodable {
            let p_spot_id: String
            let p_from_list_id: String?
            let p_to_list_id: String?
            let p_source: String
        }
        try await anonClient.rpc("move_spot_between_lists", params: MoveParams(
            p_spot_id: placeId,
            p_from_list_id: wtgId.uuidString,
            p_to_list_id: favoritesId.uuidString,
            p_source: "manual"
        )).execute()

        // Direct table check: two rows for (primary, spot), one of each kind.
        let rows = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(rows.count, 2, "Scenario E v3 produces both spot_save and conversion rows")
        XCTAssertEqual(Set(rows.map { $0.kind }), ["spot_save", "conversion"])

        // Now: Pat (a follower) calls get_following_feed and sees BOTH cards.
        let pat = try await createAdditionalUser(prefix: "follower-scenE")
        try await makeFollowAccepted(follower: pat.id, followee: primary.id)
        try await signInAnon(as: pat)

        let feedItems = try await getFollowingFeedItems()
        let itemsForActor = feedItems.filter { $0.actorId == primary.id }
        XCTAssertEqual(itemsForActor.count, 2,
            "Pat must see both the original WTG card and the new conversion card")
        let kindsSurfaced = Set(itemsForActor.map { $0.kind })
        XCTAssertEqual(kindsSurfaced, [.spotSave, .conversion],
            "the two surfaced kinds must be spot_save + conversion")
    }
}
