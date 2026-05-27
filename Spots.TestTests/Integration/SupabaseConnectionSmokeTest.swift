//
//  SupabaseConnectionSmokeTest.swift
//  Spots.TestTests
//
//  Proof-of-life test for the integration harness. Verifies four things end to
//  end against the dedicated test Supabase project:
//
//    1. The secrets file is present and well-formed.
//    2. The test target can construct a SupabaseClient pointed at the test URL.
//    3. The test project accepts a sign-up + sign-in round trip on the anon key.
//    4. The service-role client can delete the user it just created
//       (exercised in `tearDown`).
//
//  If this test passes, the harness is wired correctly and PR-B can build real
//  SQL-behavior tests on top of `SupabaseIntegrationTestCase`.
//

import XCTest

final class SupabaseConnectionSmokeTest: SupabaseIntegrationTestCase {

    func test_signUpAndSignIn_returnsValidSession() async throws {
        let session = try await signInAsFreshUser(emailPrefix: "smoke")

        XCTAssertFalse(session.accessToken.isEmpty, "access token should be non-empty")
        XCTAssertEqual(session.user.id, currentTestUserId, "session user id should match the user we just created")
        XCTAssertNotNil(session.user.email, "session user should carry an email")
    }
}
