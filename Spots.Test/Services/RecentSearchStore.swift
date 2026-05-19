//
//  RecentSearchStore.swift
//  Spots.Test
//
//  UserDefaults-backed store for the Search screen's "Recent" section.
//  Capped at 10 entries, deduped by placeId, newest-first. Decode failures
//  silently reset to empty so a malformed defaults blob never crashes the
//  app. Server-side sync across devices is intentionally out of scope — see
//  the search-screen design plan's "NOT in scope" list.
//

import Foundation
import Combine

struct RecentSpotRef: Codable, Identifiable, Equatable {
    let placeId: String
    let name: String
    let address: String
    let savedAt: Date

    var id: String { placeId }
}

@MainActor
final class RecentSearchStore: ObservableObject {
    static let shared = RecentSearchStore()

    private static let storageKey = "spots.searchRecents.v1"
    // 5 fits cleanly above the iOS keyboard in the Search screen's pre-typing
    // state without scrolling. A bigger cap (10+) created a wall of history
    // that drowned out the Nearby section underneath.
    private static let cap = 5

    @Published private(set) var recents: [RecentSpotRef]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recents = Self.load(from: defaults)
    }

    /// Pushes a spot to the top of the recents list. If it's already present,
    /// the existing entry is removed and the new one takes the top slot — so
    /// tapping the same spot twice surfaces it once, most recent.
    func record(placeId: String, name: String, address: String) {
        var next = recents.filter { $0.placeId != placeId }
        next.insert(
            RecentSpotRef(placeId: placeId, name: name, address: address, savedAt: Date()),
            at: 0
        )
        if next.count > Self.cap { next = Array(next.prefix(Self.cap)) }
        recents = next
        persist()
    }

    /// Removes a single entry — used when a tapped recent turns out to point
    /// at a spot that no longer exists upstream.
    func remove(placeId: String) {
        let next = recents.filter { $0.placeId != placeId }
        guard next.count != recents.count else { return }
        recents = next
        persist()
    }

    func clear() {
        recents = []
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(recents)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            #if DEBUG
            print("⚠️ RecentSearchStore: encode failed: \(error)")
            #endif
        }
    }

    private static func load(from defaults: UserDefaults) -> [RecentSpotRef] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([RecentSpotRef].self, from: data)
            // Trim down to the current cap on load. Earlier builds shipped
            // with cap=10, so users upgrading carry up to 10 persisted
            // entries — without this trim they'd see 10 rows on first
            // launch and only collapse to 5 after their next tap. Trimming
            // here means the new cap takes effect immediately.
            return Array(decoded.prefix(cap))
        } catch {
            #if DEBUG
            print("⚠️ RecentSearchStore: decode failed, resetting: \(error)")
            #endif
            defaults.removeObject(forKey: storageKey)
            return []
        }
    }
}
