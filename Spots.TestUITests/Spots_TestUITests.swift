//
//  Spots_TestUITests.swift
//  Spots.TestUITests
//
//  Created by Hussain Alam on 12/29/25.
//

import XCTest

final class Spots_TestUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // MARK: - T10 — Conversion happy-path (Want-to-Go → Favorites)
    //
    // Acceptance criterion from the T10 plan:
    //   "Save a spot to Want-to-Go via ListPickerSheet, reopen the picker,
    //    check Favorites, verify Want-to-Go visually unchecks and is
    //    removed, verify a 'visited' activity appears in Newsfeed."
    //
    // STATUS: SKIPPED until UI-test infrastructure lands.
    //
    // What this test needs to run end-to-end:
    //
    //   1. A signed-in test user. The app launches into auth today; the
    //      test target has no Supabase test-user seeding or auto-login
    //      flow. Needs either a launch-argument bypass or a UI-test
    //      Supabase project with a known credential.
    //
    //   2. Seeded test data. The flow assumes the user has a default set
    //      of lists (Favorites / Liked / Want-to-Go), which the app
    //      provisions on signup via `guard_create_default_lists_rpc`. A
    //      fresh test user will get those automatically, but the spot to
    //      save needs to exist in the spots table or be reachable through
    //      the search flow.
    //
    //   3. Accessibility identifiers on key UI surfaces — none currently
    //      exist on ListPickerSheet checkboxes, SaveSpotButton, or the
    //      Newsfeed visited card. Adding `.accessibilityIdentifier("...")`
    //      modifiers is the minimum change needed to drive this test
    //      reliably from XCUITest (label-based matching is brittle).
    //
    //   4. A way to wait for and assert the visited Newsfeed activity.
    //      The feed lands via `get_following_feed` and the test user
    //      would need to be following themselves OR have another user
    //      perform the conversion. Either way, network latency means
    //      `expectation(for:evaluatedWith:)` polling — not just sync taps.
    //
    // ---- The test's intended structure (pseudocode) ----
    //
    //   let app = XCUIApplication()
    //   app.launchArguments = ["--uitests-signin", "<test-user-email>"]
    //   app.launch()
    //
    //   // Search for a spot, tap to open detail, tap bookmark.
    //   navigate-to-spot-detail()
    //   app.buttons["bookmark"].tap()
    //
    //   // In ListPickerSheet: check Want-to-Go, save.
    //   app.switches["picker.wantToGo"].tap()
    //   app.buttons["picker.save"].tap()
    //
    //   // Reopen picker — Want-to-Go should be shown checked.
    //   app.buttons["bookmark"].tap()
    //   XCTAssertEqual(app.switches["picker.wantToGo"].value as? String, "1")
    //
    //   // Check Favorites; assert Want-to-Go visually unchecks (T10-D1
    //   // routing flips spotListKindMap to .favorites and re-renders).
    //   app.switches["picker.favorites"].tap()
    //   // After the tap settles, picker state should reflect the move.
    //   XCTAssertEqual(app.switches["picker.favorites"].value as? String, "1")
    //   // Note: the WTG visual uncheck only manifests AFTER save — coerce
    //   // happens at commit time. So assert post-save, not mid-tap.
    //   app.buttons["picker.save"].tap()
    //
    //   // Navigate to Profile → Favorites; spot should be there.
    //   navigate-to-profile-favorites()
    //   XCTAssertTrue(app.staticTexts[<spotName>].exists)
    //
    //   // Navigate to Profile → Want to Go; spot should NOT be there.
    //   navigate-to-profile-wantToGo()
    //   XCTAssertFalse(app.staticTexts[<spotName>].exists)
    //
    //   // Navigate to Newsfeed; visited activity for the spot should appear.
    //   navigate-to-newsfeed()
    //   let visitedCard = app.staticTexts.containing(
    //       NSPredicate(format: "label CONTAINS[c] 'visited'")
    //   ).firstMatch
    //   let appeared = visitedCard.waitForExistence(timeout: 10)
    //   XCTAssertTrue(appeared, "Expected a 'visited' activity in the Newsfeed")
    //
    // ----------------------------------------------------------------
    @MainActor
    func testConversion_happyPath_uiFlow() throws {
        throw XCTSkip("""
            T10 conversion happy-path UI test — skipped pending UI-test \
            infrastructure (test-user auth, accessibility identifiers on \
            picker/bookmark/feed surfaces, deterministic seed data). See \
            the test body for the full intended flow.
            """)
    }
}
