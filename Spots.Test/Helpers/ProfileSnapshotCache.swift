//
//  ProfileSnapshotCache.swift
//  Spots.Test
//
//  Offline-first profile data cache (memory + disk JSON).
//  Stores a consolidated snapshot of the profile screen's async data
//  so subsequent visits render instantly without network round-trips.
//  Refreshed only after explicit user actions (edit profile, save/remove spot).
//

import Foundation

// MARK: - Cached Models

struct CachedListTile: Codable {
    let title: String
    let count: Int
    let coverImageUrl: String?
    let coverPhotoReference: String?
    let userList: UserList?
    let isAllSpots: Bool
}

struct ProfileSnapshot: Codable {
    let userId: String
    let spotsCount: Int
    let mostExploredCity: String?
    let listTiles: [CachedListTile]
    let savedAt: Date
}

// MARK: - Cache

final class ProfileSnapshotCache {
    static let shared = ProfileSnapshotCache()

    private var memorySnapshot: ProfileSnapshot?
    private let diskURL: URL
    private let diskQueue = DispatchQueue(label: "com.spots.profileSnapshotCache", qos: .utility)

    /// True when data has changed (spot saved/removed) since the snapshot was written.
    /// ProfileView should do a background refresh on next appear.
    private(set) var isStale: Bool = false

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskURL = caches.appendingPathComponent("ProfileSnapshot.json")
        loadFromDisk()
    }

    /// Returns the cached snapshot if it belongs to the given user, or nil on miss.
    func snapshot(for userId: UUID) -> ProfileSnapshot? {
        guard let s = memorySnapshot, s.userId == userId.uuidString else { return nil }
        return s
    }

    func save(_ snapshot: ProfileSnapshot) {
        memorySnapshot = snapshot
        isStale = false
        let url = diskURL
        diskQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Mark current snapshot as stale so ProfileView does a background refresh on
    /// next appear while still showing cached data instantly.
    func markStale() {
        isStale = true
    }

    /// Clear cache entirely (e.g. on sign-out).
    func clear() {
        memorySnapshot = nil
        isStale = false
        let url = diskURL
        diskQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: diskURL.path),
              let data = try? Data(contentsOf: diskURL),
              let snapshot = try? JSONDecoder().decode(ProfileSnapshot.self, from: data) else {
            return
        }
        memorySnapshot = snapshot
    }
}
