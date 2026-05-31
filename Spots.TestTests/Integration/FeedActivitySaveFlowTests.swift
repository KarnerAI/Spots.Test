//
//  FeedActivitySaveFlowTests.swift
//  Spots.TestTests
//
//  Coverage of the §02 scenario walkthroughs (A, B, C, D, F, G) plus the
//  three eng-review-locked edge cases: record_first_save idempotency, D15
//  (first MANUAL save fires the card even after imports populated other
//  lists), and Q2 (full un-save then re-save fires a fresh card).
//
//  Scenario E (WTG -> Favorites/Liked conversion) lives in
//  FeedActivityTriggerTests.swift since it's one of the two MANDATORY
//  regressions per §09.
//

import Foundation
import XCTest
@testable import Spots_Test

private struct RecordParams: Encodable {
    let p_spot_id: String
    let p_list_ids: [String]
    let p_source: String
}

private struct MoveParams: Encodable {
    let p_spot_id: String
    let p_from_list_id: String?
    let p_to_list_id: String?
    let p_source: String
}

final class FeedActivitySaveFlowTests: FeedActivityIntegrationTestCase {

    // MARK: - Scenario A: WTG save fires "wants to go" card

    func test_scenarioA_wtgSave_writesSpotSaveRowWithWantToGoVerb() async throws {
        let primary = try await signInPrimaryUser(prefix: "scenA")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let wtgId = lists[.wantToGo] else { return XCTFail("missing want_to_go list") }

        let placeId = "test:scenA:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)

        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId, p_list_ids: [wtgId.uuidString], p_source: "manual"
        )).execute()

        let rows = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, "spot_save")
        XCTAssertEqual(rows.first?.list_ids, [wtgId])
        XCTAssertEqual(rows.first?.source, "manual")

        // Follower view: surfaces with kind=.spotSave and a WTG list in payload.
        let follower = try await createAdditionalUser(prefix: "scenA-follower")
        try await makeFollowAccepted(follower: follower.id, followee: primary.id)
        try await signInAnon(as: follower)

        let items = try await getFollowingFeedItems()
        let mine = items.filter { $0.actorId == primary.id }
        XCTAssertEqual(mine.count, 1)
        if case let .spotSave(payload) = mine.first?.payload {
            XCTAssertEqual(payload.lists.count, 1)
            XCTAssertEqual(payload.lists.first?.kind, .wantToGo)
        } else {
            XCTFail("expected .spotSave payload, got \(String(describing: mine.first?.payload))")
        }
    }

    // MARK: - Scenario B: Favorites save fires "favorited" card

    func test_scenarioB_favoritesSave_writesSpotSaveRowWithFavoritesVerb() async throws {
        let primary = try await signInPrimaryUser(prefix: "scenB")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let favId = lists[.favorites] else { return XCTFail("missing favorites list") }

        let placeId = "test:scenB:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)

        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId, p_list_ids: [favId.uuidString], p_source: "manual"
        )).execute()

        let rows = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, "spot_save")
        XCTAssertEqual(rows.first?.list_ids, [favId])
    }

    // MARK: - Scenario C: multi-list save commit consolidates into ONE row

    func test_scenarioC_multiListSaveCommit_writesOneConsolidatedRow() async throws {
        let primary = try await signInPrimaryUser(prefix: "scenC")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let favId = lists[.favorites] else { return XCTFail("missing favorites list") }

        // Create a custom list with visibility='followers' so the follower
        // can see it (Scenario C's "if Mexico City is public/followers" branch).
        struct CustomListRow: Encodable {
            let user_id: String
            let kind: String
            let name: String
            let visibility: String
        }
        struct CreatedRow: Decodable { let id: UUID }
        let created: [CreatedRow] = try await serviceClient
            .from("user_lists")
            .insert(CustomListRow(
                user_id: primary.id.uuidString,
                kind: "custom",
                name: "Mexico City 2026",
                visibility: "followers"
            ))
            .select("id")
            .execute()
            .value
        guard let customId = created.first?.id else { return XCTFail("custom list insert returned nothing") }

        let placeId = "test:scenC:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId, name: "Sagrada Família")

        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId,
            p_list_ids: [favId.uuidString, customId.uuidString],
            p_source: "manual"
        )).execute()

        let rows = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(rows.count, 1, "Scenario C consolidates into ONE feed_activities row")
        XCTAssertEqual(Set(rows.first?.list_ids ?? []), Set([favId, customId]))
    }

    // MARK: - Scenario D: silent re-add to additional list

    func test_scenarioD_addingAdditionalListAfterFirstSave_doesNotFireSecondCard() async throws {
        let primary = try await signInPrimaryUser(prefix: "scenD")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let wtgId = lists[.wantToGo] else { return XCTFail("missing want_to_go list") }

        // Create the custom list Mexico City exists for the second save.
        struct CustomListRow: Encodable {
            let user_id: String, kind: String, name: String, visibility: String
        }
        struct CreatedRow: Decodable { let id: UUID }
        let created: [CreatedRow] = try await serviceClient
            .from("user_lists")
            .insert(CustomListRow(user_id: primary.id.uuidString, kind: "custom", name: "Mexico City", visibility: "followers"))
            .select("id").execute().value
        guard let customId = created.first?.id else { return XCTFail("custom list insert failed") }

        let placeId = "test:scenD:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)

        // Yesterday: first save to WTG.
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId, p_list_ids: [wtgId.uuidString], p_source: "manual"
        )).execute()

        // Today: re-save with WTG + Mexico City (WTG already there).
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId,
            p_list_ids: [wtgId.uuidString, customId.uuidString],
            p_source: "manual"
        )).execute()

        let rows = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(rows.count, 1,
            "still exactly one spot_save row — UNIQUE(user, spot, kind) deduped the second call")
    }

    // MARK: - Scenario F: Favorites -> Liked move stays silent

    func test_scenarioF_favoritesToLikedMove_doesNotFireConversionCard() async throws {
        let primary = try await signInPrimaryUser(prefix: "scenF")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let favId = lists[.favorites], let likedId = lists[.liked] else {
            return XCTFail("missing favorites/liked lists")
        }

        let placeId = "test:scenF:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)

        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId, p_list_ids: [favId.uuidString], p_source: "manual"
        )).execute()
        try await anonClient.rpc("move_spot_between_lists", params: MoveParams(
            p_spot_id: placeId,
            p_from_list_id: favId.uuidString,
            p_to_list_id: likedId.uuidString,
            p_source: "manual"
        )).execute()

        let rows = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(rows.count, 1,
            "Favorites -> Liked is not a v3 conversion (D20); no conversion row written")
        XCTAssertEqual(rows.first?.kind, "spot_save")
    }

    // MARK: - Scenario G: import batch writes NO feed activity

    func test_scenarioG_importSourceCall_writesNoFeedActivityRow() async throws {
        let primary = try await signInPrimaryUser(prefix: "scenG")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let wtgId = lists[.wantToGo] else { return XCTFail("missing wtg list") }

        let placeId = "test:scenG:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)

        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId,
            p_list_ids: [wtgId.uuidString],
            p_source: "import_google_maps"
        )).execute()

        let rows = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(rows.count, 0,
            "import sources never fire feed activity (D15 / Scenario G)")
    }

    // MARK: - record_first_save idempotency

    func test_recordFirstSave_idempotent_secondCallIsNoOp() async throws {
        let primary = try await signInPrimaryUser(prefix: "idempotent")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let favId = lists[.favorites] else { return XCTFail("missing favorites list") }

        let placeId = "test:idempotent:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)

        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId, p_list_ids: [favId.uuidString], p_source: "manual"
        )).execute()
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId, p_list_ids: [favId.uuidString], p_source: "manual"
        )).execute()

        let rows = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(rows.count, 1,
            "second call is a no-op via the UNIQUE(user, spot, kind) constraint")
    }

    // MARK: - D15: import-then-manual still fires card

    func test_D15_importPopulatesListsFirst_thenFirstManualSaveFiresCard() async throws {
        let primary = try await signInPrimaryUser(prefix: "d15")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let favId = lists[.favorites] else { return XCTFail("missing favorites list") }

        // Custom imported list (followers visibility so it'd be visible if
        // it fired — but it shouldn't because import source skips the write).
        struct CustomListRow: Encodable { let user_id: String, kind: String, name: String, visibility: String }
        struct CreatedRow: Decodable { let id: UUID }
        let created: [CreatedRow] = try await serviceClient
            .from("user_lists")
            .insert(CustomListRow(user_id: primary.id.uuidString, kind: "custom", name: "Tokyo Imports", visibility: "followers"))
            .select("id").execute().value
        guard let customId = created.first?.id else { return XCTFail("custom list insert failed") }

        let placeId = "test:d15:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)

        // Step 1: import populates the custom list. No feed_activities written.
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId,
            p_list_ids: [customId.uuidString],
            p_source: "import_google_maps"
        )).execute()

        let afterImport = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(afterImport.count, 0, "import alone writes nothing")

        // Step 2: manual save to Favorites. The dedupe key is "any MANUAL
        // feed_activities" — so this MUST fire even though the spot is
        // already in another list via import.
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId,
            p_list_ids: [favId.uuidString],
            p_source: "manual"
        )).execute()

        let afterManual = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(afterManual.count, 1,
            "first MANUAL save fires the card even after imports (D15)")
        XCTAssertEqual(afterManual.first?.kind, "spot_save")
        XCTAssertEqual(afterManual.first?.list_ids, [favId])
    }

    // MARK: - Q2: full un-save then re-save fires a FRESH card

    func test_Q2_fullUnsaveThenResave_firesFreshCard() async throws {
        let primary = try await signInPrimaryUser(prefix: "q2")
        let lists = try await getDefaultListIds(forUserId: primary.id)
        guard let wtgId = lists[.wantToGo] else { return XCTFail("missing wtg list") }

        let placeId = "test:q2:\(UUID().uuidString)"
        try await ensureSpotExists(placeId: placeId)

        // Save → 1 row.
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId, p_list_ids: [wtgId.uuidString], p_source: "manual"
        )).execute()
        let original = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(original.count, 1)
        let originalId = original.first?.id

        // Un-save the spot entirely (delete its only spot_list_items row).
        // The deferred cleanup trigger fires at COMMIT — save-count is 0,
        // so feed_activities row is deleted.
        try await anonClient
            .from("spot_list_items")
            .delete()
            .eq("spot_id", value: placeId)
            .eq("list_id", value: wtgId.uuidString)
            .execute()

        let afterUnsave = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(afterUnsave.count, 0,
            "deferred cleanup must have removed the feed_activities row after full un-save")

        // Re-save → fresh row with a new UUID.
        try await anonClient.rpc("record_first_save", params: RecordParams(
            p_spot_id: placeId, p_list_ids: [wtgId.uuidString], p_source: "manual"
        )).execute()

        let afterResave = try await getFeedActivities(forUserId: primary.id)
        XCTAssertEqual(afterResave.count, 1)
        XCTAssertNotEqual(afterResave.first?.id, originalId,
            "fresh re-save must create a new feed_activities row (different UUID)")
    }
}
