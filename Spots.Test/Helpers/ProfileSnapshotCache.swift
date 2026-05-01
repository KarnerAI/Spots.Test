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
    let followersCount: Int
    let followingCount: Int
    let mostExploredCity: String?
    let listTiles: [CachedListTile]
    let savedAt: Date

    init(userId: String,
         spotsCount: Int,
         followersCount: Int = 0,
         followingCount: Int = 0,
         mostExploredCity: String?,
         listTiles: [CachedListTile],
         savedAt: Date) {
        self.userId = userId
        self.spotsCount = spotsCount
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.mostExploredCity = mostExploredCity
        self.listTiles = listTiles
        self.savedAt = savedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        spotsCount = try c.decode(Int.self, forKey: .spotsCount)
        followersCount = try c.decodeIfPresent(Int.self, forKey: .followersCount) ?? 0
        followingCount = try c.decodeIfPresent(Int.self, forKey: .followingCount) ?? 0
        mostExploredCity = try c.decodeIfPresent(String.self, forKey: .mostExploredCity)
        listTiles = try c.decode([CachedListTile].self, forKey: .listTiles)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
    }
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

    /// Cache filename. Bump the version suffix when on-disk format or any
    /// embedded display string in `CachedListTile.title` changes — the old
    /// file is then ignored and best-effort deleted, so users never see
    /// stale labels carry over across upgrades.
    /// v2: list tile titles renamed (Starred → Top Spots, Bucket List → Want to Go).
    private static let diskFilename = "ProfileSnapshot.v2.json"
    private static let legacyFilenames = ["ProfileSnapshot.json"]

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskURL = caches.appendingPathComponent(Self.diskFilename)
        purgeLegacyCacheFiles(in: caches)
        loadFromDisk()
    }

    /// Best-effort delete of pre-rename cache files. Failures are silent —
    /// stale files that linger get overwritten on the next save anyway.
    private func purgeLegacyCacheFiles(in cachesDir: URL) {
        for name in Self.legacyFilenames {
            try? FileManager.default.removeItem(at: cachesDir.appendingPathComponent(name))
        }
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
