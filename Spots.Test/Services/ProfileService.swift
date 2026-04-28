//
//  ProfileService.swift
//  Spots.Test
//
//  Handles reading and writing the `profiles` table and uploading profile avatars.
//

import Foundation
import UIKit
import Supabase

// MARK: - Model

struct UserProfile: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var username: String
    var firstName: String?
    var lastName: String?
    var email: String?
    var avatarUrl: String?
    var coverPhotoUrl: String?
    var isPrivate: Bool

    /// First + last name when both present, else whichever is non-empty, else username.
    var displayName: String {
        let first = firstName?.trimmingCharacters(in: .whitespaces) ?? ""
        let last = lastName?.trimmingCharacters(in: .whitespaces) ?? ""
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? username : full
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case avatarUrl = "avatar_url"
        case coverPhotoUrl = "cover_photo_url"
        case isPrivate = "is_private"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        coverPhotoUrl = try c.decodeIfPresent(String.self, forKey: .coverPhotoUrl)
        // is_private was added in the social schema migration; tolerate older rows.
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
    }
}

enum ProfileServiceError: LocalizedError {
    case failedToConvertImage
    var errorDescription: String? { "Failed to convert image to JPEG." }
}

// MARK: - Service

class ProfileService {
    static let shared = ProfileService()

    private let supabase = SupabaseManager.shared.client
    private let avatarsBucket = "avatars"
    private var supabaseBaseURL: String { Config.supabaseURL }
    private var profileCache: [UUID: (profile: UserProfile, timestamp: Date)] = [:]
    private let profileCacheTTL: TimeInterval = 60

    private init() {}

    // MARK: - Fetch

    /// Load the profile row for the given user. Returns nil if no row exists yet.
    func fetchProfile(userId: UUID) async throws -> UserProfile? {
        if let entry = profileCache[userId], Date().timeIntervalSince(entry.timestamp) < profileCacheTTL {
            return entry.profile
        }
        let rows: [UserProfile] = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        if let profile = rows.first {
            profileCache[userId] = (profile, Date())
        }
        return rows.first
    }

    /// Ensure a profile row exists. If missing, inserts one from the provided fallback values.
    func ensureProfileExists(
        userId: UUID,
        username: String,
        firstName: String,
        lastName: String,
        email: String
    ) async throws {
        guard try await fetchProfile(userId: userId) == nil else { return }

        struct InsertRow: Encodable {
            let id: String
            let username: String
            let first_name: String
            let last_name: String
            let email: String
        }

        let row = InsertRow(
            id: userId.uuidString,
            username: username,
            first_name: firstName,
            last_name: lastName,
            email: email
        )
        try await supabase
            .from("profiles")
            .insert(row)
            .execute()
    }

    // MARK: - Username uniqueness

    /// Returns true if `username` is already taken by someone other than `excludingUserId`.
    func isUsernameTaken(username: String, excludingUserId: UUID) async throws -> Bool {
        struct IdRow: Codable { let id: UUID }
        let rows: [IdRow] = try await supabase
            .from("profiles")
            .select("id")
            .eq("username", value: username)
            .neq("id", value: excludingUserId.uuidString)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    /// Returns true if `username` is already taken by any user (used during signup before a userId exists).
    func isUsernameTaken(username: String) async throws -> Bool {
        struct IdRow: Codable { let id: UUID }
        let rows: [IdRow] = try await supabase
            .from("profiles")
            .select("id")
            .eq("username", value: username)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    // MARK: - Search

    /// Search profiles by username or first name (case-insensitive prefix match).
    /// Excludes the current user. Returns at most `limit` rows ordered by username.
    func searchUsers(query: String, limit: Int = 25) async throws -> [UserProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let pattern = "%\(trimmed)%"
        let currentUserId = try await SupabaseManager.shared.client.auth.session.user.id.uuidString

        let rows: [UserProfile] = try await supabase
            .from("profiles")
            .select()
            .or("username.ilike.\(pattern),first_name.ilike.\(pattern),last_name.ilike.\(pattern)")
            .neq("id", value: currentUserId)
            .order("username", ascending: true)
            .limit(limit)
            .execute()
            .value
        return rows
    }

    /// Fetch profiles for a set of user ids in a single query.
    /// Used to resolve actor info for feed items and pending follow requests.
    func fetchProfiles(ids: [UUID]) async throws -> [UserProfile] {
        guard !ids.isEmpty else { return [] }
        let uniqueIds = Array(Set(ids)).map { $0.uuidString }
        let rows: [UserProfile] = try await supabase
            .from("profiles")
            .select()
            .in("id", values: uniqueIds)
            .execute()
            .value
        for profile in rows {
            profileCache[profile.id] = (profile, Date())
        }
        return rows
    }

    // MARK: - Update

    /// Update first name, last name, username and optionally avatar_url for the given user.
    func updateProfile(
        userId: UUID,
        firstName: String,
        lastName: String,
        username: String,
        avatarUrl: String?
    ) async throws {
        struct UpdateRow: Encodable {
            let first_name: String
            let last_name: String
            let username: String
            let avatar_url: String?
            let updated_at: String

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(first_name, forKey: .first_name)
                try c.encode(last_name, forKey: .last_name)
                try c.encode(username, forKey: .username)
                try c.encode(updated_at, forKey: .updated_at)
                if let url = avatar_url {
                    try c.encode(url, forKey: .avatar_url)
                } else {
                    try c.encodeNil(forKey: .avatar_url)
                }
            }

            enum CodingKeys: String, CodingKey {
                case first_name, last_name, username, avatar_url, updated_at
            }
        }

        let now = ISO8601DateFormatter.fractionalSeconds.string(from: Date())

        let row = UpdateRow(
            first_name: firstName,
            last_name: lastName,
            username: username,
            avatar_url: avatarUrl,
            updated_at: now
        )
        try await supabase
            .from("profiles")
            .update(row)
            .eq("id", value: userId.uuidString)
            .execute()
    }

    // MARK: - Cover photo

    /// Persist the user's chosen Unsplash cover photo URL to the `profiles` table.
    func updateCoverPhoto(userId: UUID, url: String) async throws {
        struct UpdateRow: Encodable {
            let cover_photo_url: String
            let updated_at: String
        }
        let row = UpdateRow(cover_photo_url: url, updated_at: ISO8601DateFormatter.fractionalSeconds.string(from: Date()))
        try await supabase
            .from("profiles")
            .update(row)
            .eq("id", value: userId.uuidString)
            .execute()
    }

    // MARK: - Avatar upload

    /// Compress and upload a UIImage to the `avatars` bucket at `{userId}/avatar.jpg`.
    /// Returns the public URL on success. Throws on conversion or upload failure.
    func uploadAvatar(userId: UUID, image: UIImage) async throws -> String {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            print("ProfileService: Failed to convert image to JPEG")
            throw ProfileServiceError.failedToConvertImage
        }
        let path = "\(userId.uuidString)/avatar.jpg"
        do {
            _ = try await supabase.storage
                .from(avatarsBucket)
                .upload(
                    path,
                    data: jpeg,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            // Append cache-bust so SwiftUI AsyncImage reloads after update
            let url = "\(supabaseBaseURL)/storage/v1/object/public/\(avatarsBucket)/\(path)?t=\(Int(Date().timeIntervalSince1970))"
            print("ProfileService: Uploaded avatar to \(url)")
            return url
        } catch {
            print("ProfileService: Avatar upload failed: \(error)")
            throw error
        }
    }

    // MARK: - Auth metadata sync

    /// Also write updated names/username into auth user_metadata so ProfileView continues
    /// to display correctly without a separate profiles fetch.
    func syncAuthMetadata(
        firstName: String,
        lastName: String,
        username: String,
        avatarUrl: String?,
        coverPhotoUrl: String? = nil
    ) async {
        do {
            var data: [String: AnyJSON] = [
                "first_name": .string(firstName),
                "last_name": .string(lastName),
                "username": .string(username),
            ]
            if let url = avatarUrl {
                data["avatar_url"] = .string(url)
            }
            if let url = coverPhotoUrl {
                data["cover_photo_url"] = .string(url)
            }
            _ = try await supabase.auth.update(user: UserAttributes(data: data))
        } catch {
            print("ProfileService: Auth metadata sync failed (non-fatal): \(error)")
        }
    }
}
