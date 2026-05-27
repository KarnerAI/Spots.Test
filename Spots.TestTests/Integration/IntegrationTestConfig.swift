//
//  IntegrationTestConfig.swift
//  Spots.TestTests
//
//  Loads credentials for the *test* Supabase project. The app code (Config.swift)
//  reads SupabaseURL / SupabaseAnonKey for the prod project; this file is the
//  parallel mechanism for the test target so prod and test never share state.
//
//  Setup: see Docs/INTEGRATION_TEST_HARNESS.md.
//

import Foundation
import XCTest
@testable import Spots_Test

enum IntegrationTestConfig {
    /// Path to the local secrets file. Outside the repo so it can never be committed.
    static let secretsPath: URL = {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/spots-test-harness/secrets.json")
    }()

    struct Secrets: Decodable {
        let supabaseURL: String
        let supabaseAnonKey: String
        let supabaseServiceRoleKey: String

        enum CodingKeys: String, CodingKey {
            case supabaseURL = "supabase_url"
            case supabaseAnonKey = "supabase_anon_key"
            case supabaseServiceRoleKey = "supabase_service_role_key"
        }
    }

    /// Returns the loaded secrets, or throws `XCTSkip` if the file is missing /
    /// malformed. Call this from `setUpWithError()` so the test is skipped — not
    /// failed — when the harness isn't configured on the current machine.
    static func loadOrSkip() throws -> Secrets {
        let path = secretsPath

        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                Integration test secrets not found at \(path.path).
                Run `Docs/scripts/setup-integration-test-harness.sh` or see
                Docs/INTEGRATION_TEST_HARNESS.md to create the test Supabase project
                and the secrets file.
                """)
        }

        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw XCTSkip("Could not read \(path.path): \(error.localizedDescription)")
        }

        let decoded: Secrets
        do {
            decoded = try JSONDecoder().decode(Secrets.self, from: data)
        } catch {
            throw XCTSkip("""
                \(path.path) is not valid JSON or is missing required keys.
                Expected keys: supabase_url, supabase_anon_key, supabase_service_role_key.
                Underlying error: \(error)
                """)
        }

        guard !decoded.supabaseURL.isEmpty,
              !decoded.supabaseAnonKey.isEmpty,
              !decoded.supabaseServiceRoleKey.isEmpty else {
            throw XCTSkip("\(path.path) has empty value(s) for supabase_url / supabase_anon_key / supabase_service_role_key.")
        }

        guard decoded.supabaseURL != Config.supabaseURL else {
            XCTFail("""
                Integration test secrets at \(path.path) point at the SAME Supabase URL
                as the production app (\(Config.supabaseURL)).
                The test harness MUST use a separate project — tests create + delete users
                and would otherwise destroy production data.
                """)
            throw XCTSkip("Test URL matches prod; refusing to run.")
        }

        return decoded
    }
}
