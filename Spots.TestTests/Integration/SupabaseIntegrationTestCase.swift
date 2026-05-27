//
//  SupabaseIntegrationTestCase.swift
//  Spots.TestTests
//
//  Base class for tests that hit a real Supabase project (the dedicated test
//  project — never prod). Subclasses get:
//
//    - `anonClient`:    a SupabaseClient signed in as a fresh per-test user.
//    - `serviceClient`: a SupabaseClient authenticated with the service-role key,
//                       used for admin operations (create/delete auth users, wipe
//                       tables between tests). Never use this in app code.
//
//  Tests that need the harness inherit from this class. Tests that don't (the
//  existing unit tests in this target) keep inheriting from XCTestCase directly.
//

import Foundation
import Supabase
import XCTest
@testable import Spots_Test

class SupabaseIntegrationTestCase: XCTestCase {

    // MARK: - Configuration loaded per-test

    private(set) var secrets: IntegrationTestConfig.Secrets!
    private(set) var supabaseURL: URL!

    // MARK: - Clients

    /// Client authenticated with the anon key. Use for app-code-equivalent calls.
    /// Sign-in happens via `signInAsFreshUser()` in subclass setUp when needed.
    private(set) var anonClient: SupabaseClient!

    /// Client authenticated with the service-role key. Use for admin operations
    /// (delete auth users, truncate tables). NEVER use in app code.
    private(set) var serviceClient: SupabaseClient!

    /// Email of the test user created via `signInAsFreshUser()`. nil until called.
    private(set) var currentTestUserId: UUID?

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        try super.setUpWithError()
        secrets = try IntegrationTestConfig.loadOrSkip()
        guard let url = URL(string: secrets.supabaseURL) else {
            throw XCTSkip("Invalid supabase_url in secrets.json: \(secrets.supabaseURL ?? "nil")")
        }
        supabaseURL = url

        anonClient = SupabaseClient(supabaseURL: url, supabaseKey: secrets.supabaseAnonKey)
        serviceClient = SupabaseClient(supabaseURL: url, supabaseKey: secrets.supabaseServiceRoleKey)
    }

    override func tearDown() async throws {
        // Best-effort cleanup of any user this test created. Each test runs against
        // a brand-new auth user so orphaned rows in test data tables are scoped to
        // that user_id and become unreachable; truncation helpers for app tables
        // land in PR-B alongside the activity-model schema.
        if let userId = currentTestUserId {
            try? await serviceClient.auth.admin.deleteUser(id: userId.uuidString)
            currentTestUserId = nil
        }
        try await super.tearDown()
    }

    // MARK: - Helpers (used by subclasses)

    /// Creates a fresh auth user with a unique email, signs `anonClient` in as
    /// that user, and returns the resulting session. The user is deleted in
    /// `tearDown`. Requires the test project to have "Auto-confirm new users"
    /// enabled (see Docs/INTEGRATION_TEST_HARNESS.md).
    @discardableResult
    func signInAsFreshUser(
        emailPrefix: String = "harness",
        password: String = "TestPasswordWithEnoughEntropy_2026!"
    ) async throws -> Session {
        let email = "\(emailPrefix)+\(UUID().uuidString)@spots-test.invalid"
        let response = try await anonClient.auth.signUp(email: email, password: password)
        currentTestUserId = response.user.id

        // Some Supabase configs return a session immediately (auto-confirm on);
        // others require an explicit sign-in step. Cover both.
        if let session = response.session {
            return session
        }
        return try await anonClient.auth.signIn(email: email, password: password)
    }
}
