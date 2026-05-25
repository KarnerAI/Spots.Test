//
//  UserListCodingTests.swift
//  Spots.TestTests
//
//  Ticket T2 / Decision E9: covers the Codable round-trip on the new
//  UserList shape (post Phase-1 schema). The migration's correctness
//  has to survive both:
//    (a) decoding fresh server rows that include every new column, and
//    (b) decoding legacy rows where the new optional fields are absent
//        (rare for new clients, but inevitable for older clients reading
//        a server response that omits nullable fields).
//
//  Failure modes covered:
//    - Unknown `kind` enum value (forward-compat, server adds a new kind
//      before clients update): must throw a typed DecodingError, never crash.
//    - Missing `visibility` field: should default to .private rather than
//      throwing — visibility is NOT NULL server-side but a defensive client
//      default protects against partial RPC payloads.
//

import Foundation
import Testing
@testable import Spots_Test

struct UserListCodingTests {

    // MARK: - Happy path

    @Test func decodesFullRowWithAllPhase1Fields() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "kind": "trip",
          "name": "Lisbon 2026",
          "visibility": "public",
          "share_slug": "abc123xyz9",
          "invite_token": "tok_42abc",
          "start_date": "2026-06-01T00:00:00Z",
          "end_date": "2026-06-14T00:00:00Z",
          "cover_image_url": "https://example.com/cover.jpg",
          "cover_emoji": "🇵🇹",
          "created_at": "2026-05-23T12:00:00Z",
          "updated_at": "2026-05-23T12:00:00Z"
        }
        """.data(using: .utf8)!

        let list = try Self.decoder.decode(UserList.self, from: json)

        #expect(list.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(list.userId == UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        #expect(list.kind == .trip)
        #expect(list.name == "Lisbon 2026")
        #expect(list.visibility == .public)
        #expect(list.shareSlug == "abc123xyz9")
        #expect(list.inviteToken == "tok_42abc")
        #expect(list.startDate != nil)
        #expect(list.endDate != nil)
        #expect(list.coverImageUrl == "https://example.com/cover.jpg")
        #expect(list.coverEmoji == "🇵🇹")
        #expect(list.displayName == "Lisbon 2026")  // custom kind -> name wins
    }

    @Test func encodeDecodeRoundTrip() throws {
        let original = UserList(
            id: UUID(),
            userId: UUID(),
            kind: .favorites,
            name: nil,
            visibility: .private,
            shareSlug: nil,
            inviteToken: nil,
            startDate: nil,
            endDate: nil,
            coverImageUrl: nil,
            coverEmoji: nil,
            createdAt: nil,
            updatedAt: nil
        )

        let data = try Self.encoder.encode(original)
        let decoded = try Self.decoder.decode(UserList.self, from: data)

        #expect(decoded == original)
        #expect(decoded.displayName == "Favorites")  // system kind -> canonical label
    }

    // MARK: - Failure mode 1: legacy/partial rows

    @Test func decodesRowWithMissingOptionalFields() throws {
        // Server returns the row before any user has set cover/dates/sharing —
        // every new optional is absent from the JSON. Required fields only.
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "user_id": "44444444-4444-4444-4444-444444444444",
          "kind": "custom",
          "name": "Brooklyn Bagels"
        }
        """.data(using: .utf8)!

        let list = try Self.decoder.decode(UserList.self, from: json)

        #expect(list.kind == .custom)
        #expect(list.name == "Brooklyn Bagels")
        #expect(list.visibility == .private)  // defaulted
        #expect(list.shareSlug == nil)
        #expect(list.inviteToken == nil)
        #expect(list.startDate == nil)
        #expect(list.endDate == nil)
        #expect(list.coverImageUrl == nil)
        #expect(list.coverEmoji == nil)
        #expect(list.createdAt == nil)
        #expect(list.updatedAt == nil)
        #expect(list.displayName == "Brooklyn Bagels")
    }

    @Test func decodesSystemKindWithNullName() throws {
        // Default lists are inserted with name = NULL; displayName falls back
        // to the kind's canonical label.
        let json = """
        {
          "id": "55555555-5555-5555-5555-555555555555",
          "user_id": "66666666-6666-6666-6666-666666666666",
          "kind": "want_to_go",
          "name": null,
          "visibility": "private"
        }
        """.data(using: .utf8)!

        let list = try Self.decoder.decode(UserList.self, from: json)
        #expect(list.kind == .wantToGo)
        #expect(list.name == nil)
        #expect(list.displayName == "Want to Go")
    }

    // MARK: - Failure mode 2: forward-compat — unknown kind

    @Test func unknownKindThrowsDecodingErrorNotCrash() {
        // Server adds a new kind enum value before clients update. Decode
        // must throw a typed error, never crash, so we can surface a
        // "please update the app" message instead of taking down the screen.
        let json = """
        {
          "id": "77777777-7777-7777-7777-777777777777",
          "user_id": "88888888-8888-8888-8888-888888888888",
          "kind": "unknown_future_kind",
          "name": "Future list",
          "visibility": "private"
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try Self.decoder.decode(UserList.self, from: json)
        }
    }

    // MARK: - Helpers

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
