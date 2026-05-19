//
//  SearchViewModel.swift
//  Spots.Test
//
//  Backs the pre-typing state of SearchView: a persistent recent list, a
//  fresh nearby-spots fetch, and a single-select category filter that
//  narrows Nearby via a separate API call (not client-side filtering, so
//  dense urban areas reliably return 10 cafes instead of 3). Owns its own
//  nearby fetch via PlacesAPIService rather than reading MapViewModel —
//  Search is presented as a modal cover and the map's VM isn't in the
//  environment, so independent state keeps this view self-contained.
//

import Foundation
import CoreLocation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    // Pre-typing data
    @Published private(set) var nearbySpots: [NearbySpot] = []
    @Published private(set) var isLoadingNearby: Bool = false
    @Published private(set) var nearbyError: String?
    @Published private(set) var recents: [RecentSpotRef] = []

    /// Cache of per-category fetch results, keyed by SpotCategory. Cleared
    /// whenever a fresh All-fetch lands (proxy for "user location moved or
    /// time passed"), so toggling chips within a session is instant after
    /// the first fetch but stale data never persists across reopens.
    @Published private(set) var filteredCache: [SpotCategory: [NearbySpot]] = [:]
    @Published private(set) var loadingCategory: SpotCategory? = nil
    @Published private(set) var filteredError: String? = nil

    /// Backing storage for the active filter. Use `setFilter(_:)` from the
    /// view layer so the per-chip fetch fires alongside the UI change.
    @Published private(set) var activeFilter: SpotCategory? = nil

    private let store: RecentSearchStore
    private let placesAPI: PlacesAPIService
    private var allFetchTask: Task<Void, Never>?
    private var filterFetchTask: Task<Void, Never>?
    private var lastFetchLocation: CLLocation?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Tuning

    /// Page size for both All and category-restricted nearby fetches. 10 is
    /// enough to fill the visible list without scrolling deep on first
    /// open, and keeps Google Places billing predictable at a few cents
    /// per Search session worst-case.
    private static let nearbyPageSize: Int = 10

    /// Wider radius for category-restricted fetches than for the All fetch.
    /// Reasoning: when the user explicitly asks for "Coffee", they've
    /// already accepted "willing to walk a bit further," so 2.5km gives
    /// dense urban areas plenty of supply while still being walkable.
    private static let allRadius: Double = 1500
    private static let categoryRadius: Double = 2500

    init(
        store: RecentSearchStore = .shared,
        placesAPI: PlacesAPIService = .shared
    ) {
        self.store = store
        self.placesAPI = placesAPI
        self.recents = store.recents
        // Mirror the store so SwiftUI re-renders whenever a recent is added
        // elsewhere (e.g. when a tapped autocomplete result records itself).
        store.$recents
            .receive(on: RunLoop.main)
            .sink { [weak self] next in self?.recents = next }
            .store(in: &cancellables)
    }

    // MARK: - Derived state

    /// The list the view should render. All view → nearbySpots; category
    /// view → cache lookup (or empty while the fetch is in flight).
    var filteredNearby: [NearbySpot] {
        guard let filter = activeFilter else { return nearbySpots }
        return filteredCache[filter] ?? []
    }

    /// Section header text: "Nearby now" when unfiltered, "Nearby coffee" etc.
    var nearbyHeader: String {
        guard let filter = activeFilter else { return "Nearby now" }
        return "Nearby \(filter.displayName.lowercased())"
    }

    /// True while either the All or the currently-active category fetch
    /// is in flight AND we have nothing to show. Drives the spinner.
    var isShowingLoadingState: Bool {
        if let filter = activeFilter {
            return loadingCategory == filter && (filteredCache[filter]?.isEmpty ?? true)
        }
        return isLoadingNearby && nearbySpots.isEmpty
    }

    /// Combined error string for the currently visible list. Lets the view
    /// render one error UI regardless of which fetch failed.
    var visibleError: String? {
        activeFilter == nil ? nearbyError : filteredError
    }

    // MARK: - Filter

    /// Sets the active filter and triggers a category fetch when needed.
    /// Re-tapping the active chip clears the filter without firing a call.
    func setFilter(_ category: SpotCategory?) {
        activeFilter = category
        filteredError = nil
        guard let category else { return }
        // Cache hit → nothing to do. Stale cache lives for the lifetime of
        // a Search session (cleared when All re-fetches).
        if filteredCache[category] != nil { return }
        loadFiltered(category: category)
    }

    // MARK: - Fetch

    /// Fetches a small page of nearby spots around the supplied location.
    /// Replaces nearbySpots on success and invalidates the per-category
    /// cache (locations change → previously fetched cafes may be far away).
    func loadNearby(from location: CLLocation?) {
        guard let location else {
            nearbySpots = []
            nearbyError = nil
            filteredCache = [:]
            return
        }
        allFetchTask?.cancel()
        lastFetchLocation = location
        allFetchTask = Task { [placesAPI] in
            isLoadingNearby = true
            nearbyError = nil
            do {
                let result = try await placesAPI.searchNearby(
                    location: location,
                    radius: Self.allRadius,
                    pageToken: nil,
                    maxResults: Self.nearbyPageSize,
                    includedPrimaryTypes: nil
                )
                if Task.isCancelled { return }
                nearbySpots = sortedByDistance(result.spots, from: location)
                // Fresh All fetch → drop stale per-category cache so the
                // next chip tap fetches against the new location.
                filteredCache = [:]
                // If a chip is already active when location resolves, refire
                // its fetch so the user doesn't see an empty filtered list.
                if let active = activeFilter {
                    loadFiltered(category: active)
                }
            } catch {
                if Task.isCancelled { return }
                nearbyError = error.localizedDescription
            }
            isLoadingNearby = false
        }
    }

    /// Fetches nearby spots restricted to a specific category. Caches the
    /// result so toggling the chip back is instant. Uses the wider
    /// categoryRadius so dense urban areas reliably hit the page-size cap.
    private func loadFiltered(category: SpotCategory) {
        guard let location = lastFetchLocation else { return }
        filterFetchTask?.cancel()
        filterFetchTask = Task { [placesAPI] in
            loadingCategory = category
            filteredError = nil
            do {
                let result = try await placesAPI.searchNearby(
                    location: location,
                    radius: Self.categoryRadius,
                    pageToken: nil,
                    maxResults: Self.nearbyPageSize,
                    includedPrimaryTypes: category.primaryTypes
                )
                if Task.isCancelled { return }
                filteredCache[category] = sortedByDistance(result.spots, from: location)
            } catch {
                if Task.isCancelled { return }
                filteredError = error.localizedDescription
            }
            // Only clear the loading indicator if we're still on this
            // category — chip-toggle race conditions could land us on
            // another one mid-flight.
            if loadingCategory == category {
                loadingCategory = nil
            }
        }
    }

    private func sortedByDistance(_ spots: [NearbySpot], from location: CLLocation) -> [NearbySpot] {
        spots
            .map { $0.withDistance(from: location) }
            .sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
    }

    // MARK: - Recents

    /// Records a tapped spot in the recent searches list. Called from the
    /// view layer for both nearby-row taps and autocomplete-result taps.
    func recordRecent(placeId: String, name: String, address: String) {
        store.record(placeId: placeId, name: name, address: address)
    }

    /// Drops a stale recent — used when the upstream spot is gone, and as
    /// the action for the per-row swipe-to-delete affordance on the Recent
    /// section of the Search screen.
    func removeRecent(placeId: String) {
        store.remove(placeId: placeId)
    }

    /// Wipes the entire recent searches list. Backs the "Clear" button in
    /// the Recent section header. View layer is expected to gate this
    /// behind a confirmation dialog — there is no undo.
    func clearRecents() {
        store.clear()
    }

    // MARK: - Test hooks

    /// Seeds `nearbySpots` directly for unit tests so they don't have to
    /// stand up a fake PlacesAPIService. Internal so it stays out of the
    /// public surface; reachable from `@testable import`.
    func setNearbyForTesting(_ spots: [NearbySpot]) {
        self.nearbySpots = spots
    }

    /// Seeds the per-category cache for tests of filteredNearby behavior.
    func setFilteredForTesting(_ spots: [NearbySpot], for category: SpotCategory) {
        self.filteredCache[category] = spots
    }
}
