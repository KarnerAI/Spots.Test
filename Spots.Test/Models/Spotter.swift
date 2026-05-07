//
//  Spotter.swift
//  Spots.Test
//
//  One row in the "Spotted By" sheet: a user who has saved a given place to a
//  public list. Returned by the get_spot_spotters RPC.
//

import Foundation

struct Spotter: Identifiable, Equatable, Hashable, Decodable {
    let userId: UUID
    let username: String
    let firstName: String?
    let lastName: String?
    let avatarUrl: String?
    let savedAt: Date

    var id: UUID { userId }

    var displayName: String {
        let first = firstName?.trimmingCharacters(in: .whitespaces) ?? ""
        let last = lastName?.trimmingCharacters(in: .whitespaces) ?? ""
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? username : full
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case firstName = "first_name"
        case lastName = "last_name"
        case avatarUrl = "avatar_url"
        case savedAt = "saved_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(UUID.self, forKey: .userId)
        username = try c.decode(String.self, forKey: .username)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)

        let raw = try c.decode(String.self, forKey: .savedAt)
        guard let parsed = SharedFormatters.date(from: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .savedAt, in: c,
                debugDescription: "Unparseable spotter saved_at: \(raw)"
            )
        }
        savedAt = parsed
    }
}
