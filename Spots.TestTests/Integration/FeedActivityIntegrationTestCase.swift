//
//  FeedActivityIntegrationTestCase.swift
//  Spots.TestTests
//
//  Shared base + helpers for the PR-B activity-model integration tests.
//  Layered on top of `SupabaseIntegrationTestCase` (auth user lifecycle)
//  so the existing smoke test stays untouched.
//
//  What this adds:
//    - Multi-user support: tests can create additional auth users (Pat, the
//      follower viewer) without disrupting the primary signInAsFreshUser
//      session. Each additional user is deleted in tearDown via the
//      service-role client; cascade FKs clean up profiles + default lists.
//    - Fixture helpers: ensure a spot exists in `spots`, fetch a user's
//      default list IDs by kind, create an accepted follow edge, and
//      query feed_activities / the get_following_feed RPC.
//

import Foundation
import Supabase
import XCTest
@testable import Spots_Test

class FeedActivityIntegrationTestCase: SupabaseIntegrationTestCase {

    // MARK: - Multi-user lifecycle

    /// Additional users created during the test (beyond the primary one
    /// from signInAsFreshUser). Deleted in tearDown via the service-role
    /// client; cascade FKs handle profiles / user_lists / spot_list_items /
    /// feed_activities cleanup.
    private(set) var additionalTestUserIds: [UUID] = []

    struct TestUser {
        let id: UUID
        let email: String
        let password: String
    }

    override func tearDown() async throws {
        for id in additionalTestUserIds {
            try? await serviceClient.auth.admin.deleteUser(id: id)
        }
        additionalTestUserIds.removeAll()
        try await super.tearDown()
    }

    // MARK: - User helpers

    /// Creates an additional auth user without disrupting the anonClient's
    /// current session. Uses an ephemeral client for the signUp call so the
    /// primary user (signed in via signInAsFreshUser) stays the active
    /// anonClient identity until the test explicitly switches with
    /// `signInAnon(as:)`.
    @discardableResult
    func createAdditionalUser(prefix: String) async throws -> TestUser {
        let email = "\(prefix)+\(UUID().uuidString)@spots-test.invalid"
        let password = "TestPasswordWithEnoughEntropy_2026!"
        let bootstrap = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: secrets.supabaseAnonKey)
        let response = try await bootstrap.auth.signUp(email: email, password: password)
        let user = TestUser(id: response.user.id, email: email, password: password)
        additionalTestUserIds.append(user.id)
        return user
    }

    /// Switches the anonClient's session to the given user (must have been
    /// created via createAdditionalUser or signInAsFreshUser). Subsequent
    /// anonClient calls run as that user.
    func signInAnon(as user: TestUser) async throws {
        try await anonClient.auth.signOut()
        try await anonClient.auth.signIn(email: user.email, password: user.password)
    }

    /// Wraps the primary signInAsFreshUser flow but also returns the
    /// generated email/password so the caller can switch back to this user
    /// later via signInAnon(as:). The base class's currentTestUserId still
    /// tracks this user for the regular tearDown cleanup path.
    @discardableResult
    func signInPrimaryUser(prefix: String = "primary") async throws -> TestUser {
        let email = "\(prefix)+\(UUID().uuidString)@spots-test.invalid"
        let password = "TestPasswordWithEnoughEntropy_2026!"
        let response = try await anonClient.auth.signUp(email: email, password: password)
        let user = TestUser(id: response.user.id, email: email, password: password)
        // currentTestUserId is set via KVC because the base class's setter is private.
        // Simpler: defer cleanup to the additional-users array.
        additionalTestUserIds.append(user.id)
        return user
    }

    // MARK: - Direct PostgREST helper (bypasses supabase-swift SDK)
    //
    // The supabase-swift PostgrestClient under the local Supabase CLI's new
    // sb_secret_* service-role key format silently no-ops on UPDATE calls
    // (verified empirically — see makeFollowAccepted). The same UPDATE
    // works via curl with explicit Authorization: Bearer headers. So for
    // setup-time mutations that need the service-role bypass, we go around
    // the SDK and hit PostgREST directly via URLSession.

    private func serviceRoleRequest(
        method: String,
        path: String,
        body: Data? = nil,
        prefer: String? = nil
    ) async throws {
        // appendingPathComponent percent-encodes `?` / `=` — build the URL
        // by string concat so the PostgREST query string survives intact.
        let urlString = supabaseURL.absoluteString.trimmingCharacters(in: ["/"])
            + "/rest/v1/\(path)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "TestHarness", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "could not build service-role URL from \(urlString)"
            ])
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(secrets.supabaseServiceRoleKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(secrets.supabaseServiceRoleKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
            throw NSError(domain: "TestHarness", code: status, userInfo: [
                NSLocalizedDescriptionKey: "service-role \(method) \(path) failed (\(status)): \(bodyStr)"
            ])
        }
    }

    // MARK: - Fixture helpers

    /// Insert a spots row via service-role so the FK from spot_list_items /
    /// feed_activities is satisfied. spots is logically global (one row per
    /// Google place_id, shared across users); tests use synthetic place_ids
    /// like "test:scenario-a-\(UUID)".
    func ensureSpotExists(placeId: String, name: String = "Test Spot") async throws {
        struct SpotRow: Encodable {
            let place_id: String
            let name: String
            let address: String
            let latitude: Double
            let longitude: Double
            let types: [String]
        }
        let row = SpotRow(
            place_id: placeId,
            name: name,
            address: "Test address",
            latitude: 0,
            longitude: 0,
            types: ["test"]
        )
        try await serviceClient
            .from("spots")
            .upsert(row, onConflict: "place_id")
            .execute()
    }

    /// Fetches the (kind -> list_id) map for a user's default lists.
    /// Skips the test with a clear message if any of the three default
    /// lists are missing (means the on_auth_user_created_create_lists
    /// trigger didn't fire — points at harness misconfiguration).
    func getDefaultListIds(forUserId userId: UUID) async throws -> [ListKind: UUID] {
        struct Row: Decodable {
            let id: UUID
            let kind: String?
        }
        let rows: [Row] = try await serviceClient
            .from("user_lists")
            .select("id, kind")
            .eq("user_id", value: userId)
            .execute()
            .value

        var map: [ListKind: UUID] = [:]
        for row in rows {
            guard let kindStr = row.kind,
                  let kind = ListKind(rawValue: kindStr),
                  kind.isSystemKind else { continue }
            map[kind] = row.id
        }
        return map
    }

    /// Creates an accepted follow edge that survives the
    /// `follows_normalize_status` BEFORE-INSERT trigger, which forces
    /// status to 'pending' for followees with `profiles.is_private=TRUE`
    /// (the default per make_accounts_private_by_default).
    ///
    /// Workaround: flip the followee to public for the duration of the
    /// INSERT (trigger sees public, writes status=accepted), then flip
    /// back to private. Goes through serviceRoleRequest because the
    /// supabase-swift SDK silently no-ops UPDATEs under the local CLI's
    /// sb_secret_* key format.
    func makeFollowAccepted(follower: UUID, followee: UUID) async throws {
        try await serviceRoleRequest(
            method: "PATCH",
            path: "profiles?id=eq.\(followee.uuidString)",
            body: #"{"is_private": false}"#.data(using: .utf8)
        )
        try await serviceRoleRequest(
            method: "POST",
            path: "follows",
            body: """
            {"follower_id":"\(follower.uuidString)","followee_id":"\(followee.uuidString)","status":"accepted"}
            """.data(using: .utf8)
        )
        try await serviceRoleRequest(
            method: "PATCH",
            path: "profiles?id=eq.\(followee.uuidString)",
            body: #"{"is_private": true}"#.data(using: .utf8)
        )
    }

    /// Service-role list visibility flip (PATCH against user_lists). Used
    /// by privacy tests that need to change a default list's visibility
    /// away from the 'followers' seed value.
    func setListVisibility(listId: UUID, to visibility: String) async throws {
        try await serviceRoleRequest(
            method: "PATCH",
            path: "user_lists?id=eq.\(listId.uuidString)",
            body: #"{"visibility": "\#(visibility)"}"#.data(using: .utf8)
        )
    }

    /// Direct read of feed_activities rows for a user (service-role, bypasses
    /// RLS). Used by tests asserting on what the trigger / RPC actually wrote
    /// — separate from get_following_feed which adds privacy filtering.
    func getFeedActivities(forUserId userId: UUID) async throws -> [FeedActivityRow] {
        let rows: [FeedActivityRow] = try await serviceClient
            .from("feed_activities")
            .select("id, user_id, spot_id, kind, list_ids, source, created_at")
            .eq("user_id", value: userId)
            .order("created_at", ascending: true)
            .execute()
            .value
        return rows
    }

    struct FeedActivityRow: Decodable, Equatable {
        let id: UUID
        let user_id: UUID
        let spot_id: String
        let kind: String
        let list_ids: [UUID]
        let source: String
        let created_at: String
    }

    /// Calls get_following_feed via the currently-signed-in anonClient.
    /// Returns the decoded FeedItem array as app code would consume it.
    func getFollowingFeedItems(limit: Int = 50) async throws -> [FeedItem] {
        struct Params: Encodable { let p_limit: Int }
        let response = try await anonClient
            .rpc("get_following_feed", params: Params(p_limit: limit))
            .execute()
        // Decode manually so we use FeedItem's custom decoder.
        let decoder = JSONDecoder()
        return try decoder.decode([FeedItem].self, from: response.data)
    }
}
