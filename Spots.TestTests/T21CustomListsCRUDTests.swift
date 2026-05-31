//
//  T21CustomListsCRUDTests.swift
//  Spots.TestTests
//
//  Ticket T21 / Decision D-T21.3: 12 test cases covering the Custom Lists
//  CRUD behavior added in T21.4 (service layer) and the optimistic-update
//  flow in LocationSavingViewModel.
//
//  Coverage map (matches the eng-review test plan in
//  ~/.claude/plans/users-shaon-library-cloudstorage-google-misty-eagle.md):
//
//    VM OPTIMISTIC UPDATES                                  TEST
//    ─────────────────────────────────────                  ───────────────────
//    createList appends on success                          testCreate_appendsOnSuccess
//    createList does NOT append on failure                  testCreate_doesNotAppendOnFailure
//    renameList replaces row in-place                       testRename_replacesInPlace
//    deleteList removes optimistically + rolls back on err  testDelete_optimisticRemoveAndRollback
//    deleteList succeeds + stays removed                    testDelete_happyPathRemoves
//    restoreList re-inserts on success                      testRestore_reinsertsOnSuccess
//    setListVisibility replaces in place                    testSetVisibility_replacesInPlace
//    setListCoverEmoji passes nil to clear                  testSetCoverEmoji_passesNilToClear
//
//    CODABLE                                                TEST
//    ─────────────────────────────────────                  ───────────────────
//    3-state visibility round-trip                          testVisibility_threeStateRoundTrip
//    UserList.deletedAt round-trip                          testUserList_deletedAtRoundTrip
//    DeletedListSummary with days_remaining                 testDeletedListSummary_decodes
//    Visibility descriptions match UI copy                  testVisibility_displayCopy
//
//  ─────────────────────────────────────────────────────────────────────────
//  INTEGRATION TESTS (deferred — see TODOS.md "P2 — List Detail hero header"
//  and Eng Review test plan): the following live-DB cases require a Supabase
//  test instance + service-role key that isn't wired into the test target:
//    - RLS blocks non-owner / default-list deletion (returns 403)
//    - restore_list rejects past 30-day window
//    - active_user_lists view actually hides tombstoned rows
//    - get_list_tile_summaries RPC returns the COALESCE auto-cover correctly
//      across each of the 7 spot-state transitions
//  These will land as XCUITest-driven flows once a seeded test schema exists.
//

import Testing
import Foundation
@testable import Spots_Test

@MainActor
struct T21CustomListsCRUDTests {

    // MARK: - Shared fixtures

    static let userId = UUID()

    static func sampleCustomList(
        id: UUID = UUID(),
        name: String = "Mexico City 2026",
        visibility: ListVisibility = .private,
        coverEmoji: String? = "🌮"
    ) -> UserList {
        UserList(
            id: id,
            userId: userId,
            kind: .custom,
            name: name,
            visibility: visibility,
            coverEmoji: coverEmoji
        )
    }

    // MARK: - Decoder helper (for Codable round-trip tests)

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // ════════════════════════════════════════════════════════════════════
    // MARK: - 1. VM optimistic updates
    // ════════════════════════════════════════════════════════════════════

    @Test func testCreate_appendsOnSuccess() async throws {
        let mock = MockLocationSavingService()
        let created = Self.sampleCustomList(name: "Mexico City 2026")
        mock.createListResult = created

        let vm = LocationSavingViewModel(service: mock)
        #expect(vm.userLists.isEmpty)

        let result = try await vm.createList(name: "Mexico City 2026", visibility: .private, coverEmoji: "🌮")

        #expect(result.id == created.id)
        #expect(vm.userLists.count == 1)
        #expect(vm.userLists.first?.id == created.id)
        #expect(mock.createListCalls.count == 1)
        #expect(mock.createListCalls.first?.name == "Mexico City 2026")
        #expect(mock.createListCalls.first?.coverEmoji == "🌮")
    }

    @Test func testCreate_doesNotAppendOnFailure() async {
        let mock = MockLocationSavingService()
        mock.createListShouldThrow = CustomListError.nameTooLong(maxLength: 50)

        let vm = LocationSavingViewModel(service: mock)
        #expect(vm.userLists.isEmpty)

        do {
            _ = try await vm.createList(name: "x", visibility: .private, coverEmoji: nil)
            Issue.record("Expected createList to throw")
        } catch {
            // Expected — verify no optimistic append.
            #expect(vm.userLists.isEmpty)
            if case CustomListError.nameTooLong(let max) = error {
                #expect(max == 50)
            } else {
                Issue.record("Expected CustomListError.nameTooLong, got \(error)")
            }
        }
    }

    @Test func testRename_replacesInPlace() async throws {
        let mock = MockLocationSavingService()
        let original = Self.sampleCustomList(name: "Old Name")
        let renamed = UserList(
            id: original.id,
            userId: original.userId,
            kind: .custom,
            name: "New Name",
            visibility: original.visibility,
            coverEmoji: original.coverEmoji
        )
        mock.renameListResult = renamed

        let vm = LocationSavingViewModel(service: mock)
        vm.userLists = [original]

        _ = try await vm.renameList(id: original.id, newName: "New Name")

        #expect(vm.userLists.count == 1)
        #expect(vm.userLists.first?.name == "New Name")
        #expect(vm.userLists.first?.id == original.id)
        #expect(mock.renameListCalls.count == 1)
        #expect(mock.renameListCalls.first?.newName == "New Name")
    }

    @Test func testDelete_optimisticRemoveAndRollback() async {
        let mock = MockLocationSavingService()
        let target = Self.sampleCustomList(name: "Risky")
        let other = Self.sampleCustomList(name: "Other")
        // Simulate the server rejecting the delete (e.g. RLS blocks default-list delete).
        mock.deleteListShouldThrow = NSError(domain: "PostgrestError", code: 42501)

        let vm = LocationSavingViewModel(service: mock)
        vm.userLists = [target, other]

        do {
            _ = try await vm.deleteList(id: target.id)
            Issue.record("Expected deleteList to throw")
        } catch {
            // Rollback assertion: the target must be back in userLists at its
            // original index after the failure.
            #expect(vm.userLists.count == 2)
            #expect(vm.userLists.contains(where: { $0.id == target.id }))
            #expect(vm.userLists.first?.id == target.id)
        }
    }

    @Test func testDelete_happyPathRemoves() async throws {
        let mock = MockLocationSavingService()
        let target = Self.sampleCustomList(name: "Going away")
        let other = Self.sampleCustomList(name: "Staying")
        mock.deleteListResult = UserList(
            id: target.id, userId: target.userId, kind: .custom,
            name: target.name, visibility: target.visibility,
            coverEmoji: target.coverEmoji,
            deletedAt: Date()
        )

        let vm = LocationSavingViewModel(service: mock)
        vm.userLists = [target, other]

        let tombstoned = try await vm.deleteList(id: target.id)

        #expect(tombstoned.deletedAt != nil)
        #expect(vm.userLists.count == 1)
        #expect(vm.userLists.first?.id == other.id)
        #expect(!vm.userLists.contains(where: { $0.id == target.id }))
    }

    @Test func testRestore_reinsertsOnSuccess() async throws {
        let mock = MockLocationSavingService()
        let restoredId = UUID()
        mock.restoreListResult = UserList(id: restoredId, userId: Self.userId, kind: .custom, name: "Restored")

        let vm = LocationSavingViewModel(service: mock)
        #expect(vm.userLists.isEmpty)

        _ = try await vm.restoreList(id: restoredId)

        #expect(vm.userLists.count == 1)
        #expect(vm.userLists.first?.id == restoredId)
        #expect(mock.restoreListCalls.first == restoredId)
    }

    @Test func testSetVisibility_replacesInPlace() async throws {
        let mock = MockLocationSavingService()
        let original = Self.sampleCustomList(visibility: .private)
        let updated = UserList(
            id: original.id, userId: original.userId, kind: .custom,
            name: original.name, visibility: .followers, coverEmoji: original.coverEmoji
        )
        mock.setListVisibilityResult = updated

        let vm = LocationSavingViewModel(service: mock)
        vm.userLists = [original]

        _ = try await vm.setListVisibility(id: original.id, visibility: .followers)

        #expect(vm.userLists.count == 1)
        #expect(vm.userLists.first?.visibility == .followers)
        #expect(mock.setListVisibilityCalls.first?.visibility == .followers)
    }

    @Test func testSetCoverEmoji_passesNilToClear() async throws {
        let mock = MockLocationSavingService()
        let original = Self.sampleCustomList(coverEmoji: "🌮")
        mock.setListCoverEmojiResult = UserList(
            id: original.id, userId: original.userId, kind: .custom,
            name: original.name, visibility: original.visibility,
            coverEmoji: nil
        )

        let vm = LocationSavingViewModel(service: mock)
        vm.userLists = [original]

        _ = try await vm.setListCoverEmoji(id: original.id, emoji: nil)

        #expect(vm.userLists.first?.coverEmoji == nil)
        #expect(mock.setListCoverEmojiCalls.count == 1)
        // The nil must propagate to the service layer so the SQL UPDATE
        // actually clears the column instead of skipping it.
        #expect(mock.setListCoverEmojiCalls.first?.emoji == nil)
    }

    // ════════════════════════════════════════════════════════════════════
    // MARK: - 2. Codable round-trips
    // ════════════════════════════════════════════════════════════════════

    @Test func testVisibility_threeStateRoundTrip() throws {
        for value in ListVisibility.allCases {
            let data = try Self.encoder.encode(value)
            let decoded = try Self.decoder.decode(ListVisibility.self, from: data)
            #expect(decoded == value, "Visibility \(value.rawValue) didn't round-trip")
        }
        // Sanity: enum has exactly 3 cases.
        #expect(ListVisibility.allCases.count == 3)
        #expect(Set(ListVisibility.allCases.map(\.rawValue)) == ["private", "shared", "public"])
    }

    @Test func testUserList_deletedAtRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1716676800) // 2026-05-25T20:00:00Z
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "kind": "custom",
          "name": "Tombstoned",
          "visibility": "private",
          "deleted_at": "2026-05-25T20:00:00Z"
        }
        """.data(using: .utf8)!

        let list = try Self.decoder.decode(UserList.self, from: json)

        #expect(list.deletedAt != nil)
        #expect(list.deletedAt == now)
        #expect(list.name == "Tombstoned")
    }

    @Test func testDeletedListSummary_decodes() throws {
        // Mirrors what list_deleted_lists RPC returns.
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "name": "Mexico City 2026",
          "kind": "custom",
          "cover_emoji": "🌮",
          "cover_image_url": null,
          "deleted_at": "2026-05-25T20:00:00Z",
          "days_remaining": 28
        }
        """.data(using: .utf8)!

        let summary = try Self.decoder.decode(DeletedListSummary.self, from: json)

        #expect(summary.id == UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        #expect(summary.name == "Mexico City 2026")
        #expect(summary.kind == "custom")
        #expect(summary.coverEmoji == "🌮")
        #expect(summary.coverImageUrl == nil)
        #expect(summary.daysRemaining == 28)
    }

    @Test func testVisibility_displayCopy() {
        // Guards against an accidental wording drift between Figma copy and
        // the live UI. If marketing/PM changes the user-facing copy, this
        // test should be updated alongside the change.
        #expect(ListVisibility.private.displayName == "Private")
        #expect(ListVisibility.followers.displayName == "Shared")
        #expect(ListVisibility.public.displayName == "Public")

        #expect(ListVisibility.private.description == "Only you can view and edit.")
        #expect(ListVisibility.followers.description.contains("invite"))
        #expect(ListVisibility.public.description.contains("Anyone"))
    }
}
