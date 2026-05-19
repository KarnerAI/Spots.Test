//
//  RecentSearchStoreTests.swift
//  Spots.TestTests
//
//  Covers the contract the SearchView relies on: dedup-on-record,
//  capacity ceiling, and graceful recovery from corrupted persistence.
//

import Testing
import Foundation
@testable import Spots_Test

@MainActor
struct RecentSearchStoreTests {

    // Each test gets its own UserDefaults suite so persisted state from
    // one test never leaks into another.
    private static func makeStore(suite: String = UUID().uuidString) -> (RecentSearchStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (RecentSearchStore(defaults: defaults), defaults)
    }

    @Test func recordPushesNewestToTop() {
        let (store, _) = Self.makeStore()
        store.record(placeId: "a", name: "Alpha", address: "1 Way")
        store.record(placeId: "b", name: "Bravo", address: "2 Way")

        #expect(store.recents.map(\.placeId) == ["b", "a"])
    }

    @Test func recordDedupsAndMovesToTop() {
        let (store, _) = Self.makeStore()
        store.record(placeId: "a", name: "Alpha", address: "1 Way")
        store.record(placeId: "b", name: "Bravo", address: "2 Way")
        store.record(placeId: "a", name: "Alpha", address: "1 Way") // dup

        #expect(store.recents.count == 2)
        #expect(store.recents.map(\.placeId) == ["a", "b"])
    }

    @Test func recordEnforcesCapacityCap() {
        let (store, _) = Self.makeStore()
        for i in 0..<15 {
            store.record(placeId: "p\(i)", name: "Spot \(i)", address: "Addr")
        }

        // Cap is 5 (down from 10 in earlier builds — see RecentSearchStore
        // comment on `cap` for the UX rationale).
        #expect(store.recents.count == 5)
        // Newest first → p14 at top, p10 at bottom (p0…p9 dropped).
        #expect(store.recents.first?.placeId == "p14")
        #expect(store.recents.last?.placeId == "p10")
    }

    @Test func loadTrimsOverCapPersistedData() {
        // Simulates the cap=10 → cap=5 migration: a previous build wrote
        // 10 entries to UserDefaults, and the current build with cap=5
        // must surface only 5 on read instead of letting the over-cap
        // state linger until the user's next tap.
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let oversized: [RecentSpotRef] = (0..<10).map { i in
            RecentSpotRef(placeId: "p\(i)", name: "Spot \(i)", address: "Addr", savedAt: Date())
        }
        defaults.set(try! JSONEncoder().encode(oversized), forKey: "spots.searchRecents.v1")

        let store = RecentSearchStore(defaults: defaults)
        #expect(store.recents.count == 5)
        // Preserves the original ordering of the first 5 entries — load
        // must trim from the tail, not the head, because callers expect
        // newest-first semantics.
        #expect(store.recents.map(\.placeId) == ["p0", "p1", "p2", "p3", "p4"])
    }

    @Test func persistAndReloadRoundTrip() {
        let suite = UUID().uuidString
        let (store, defaults) = Self.makeStore(suite: suite)
        store.record(placeId: "a", name: "Alpha", address: "1 Way")
        store.record(placeId: "b", name: "Bravo", address: "2 Way")

        // Fresh store reading the same UserDefaults should see what we wrote.
        let reloaded = RecentSearchStore(defaults: defaults)
        #expect(reloaded.recents.map(\.placeId) == ["b", "a"])
    }

    @Test func decodeFailureResetsToEmptyAndDoesNotCrash() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        // Stuff in deliberately malformed JSON to simulate a schema-drift
        // scenario where a future build wrote a shape we can't decode.
        defaults.set(Data("not json".utf8), forKey: "spots.searchRecents.v1")

        let store = RecentSearchStore(defaults: defaults)
        #expect(store.recents.isEmpty)
        // And the corrupted blob should have been swept on read.
        #expect(defaults.data(forKey: "spots.searchRecents.v1") == nil)
    }

    @Test func removeDropsMatchingEntry() {
        let (store, _) = Self.makeStore()
        store.record(placeId: "a", name: "Alpha", address: "1 Way")
        store.record(placeId: "b", name: "Bravo", address: "2 Way")

        store.remove(placeId: "a")
        #expect(store.recents.map(\.placeId) == ["b"])
    }

    @Test func clearEmptiesAndPersists() {
        let suite = UUID().uuidString
        let (store, defaults) = Self.makeStore(suite: suite)
        store.record(placeId: "a", name: "Alpha", address: "1 Way")
        store.record(placeId: "b", name: "Bravo", address: "2 Way")
        #expect(store.recents.count == 2)

        store.clear()
        #expect(store.recents.isEmpty)

        // Fresh store reading the same defaults should see the cleared
        // state — the wipe has to land on disk, not just in memory.
        let reloaded = RecentSearchStore(defaults: defaults)
        #expect(reloaded.recents.isEmpty)
    }

    @Test func clearOnEmptyIsNoop() {
        let (store, _) = Self.makeStore()
        #expect(store.recents.isEmpty)

        // Should not throw, should not flip any state, should not write
        // garbage. Trivial but guards against a future "clear if empty
        // throws" regression.
        store.clear()
        #expect(store.recents.isEmpty)
    }
}
