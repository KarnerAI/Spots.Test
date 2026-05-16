//
//  SearchViewModel.swift
//  Spots.Test
//
//  Backs the pre-typing state of SearchView: a persistent recent list, a
//  fresh nearby-spots fetch, and a single-select category filter that
//  narrows Nearby in place. Owns its own nearby fetch via PlacesAPIService
//  rather than reading MapViewModel — Search is presented as a modal cover
//  and the map's VM isn't in the environment, so independent state keeps
//  this view self-contained and predictable.
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
    @Published var activeFilter: SpotCategory? = nil
    @Published private(set) var recents: [RecentSpotRef] = []

    private let store: RecentSearchStore
    private let placesAPI: PlacesAPIService
    private var fetchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

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

    /// Computed view over nearbySpots that respects activeFilter. Cheap to
    /// recompute on every body — filter list is small (≤ 20 spots).
    var filteredNearby: [NearbySpot] {
        guard let filter = activeFilter else { return nearbySpots }
        return nearbySpots.filter { filter.matches($0.category) }
    }

    /// Section header text: "Nearby now" when unfiltered, "Nearby coffee" etc. otherwise.
    var nearbyHeader: String {
        guard let filter = activeFilter else { return "Nearby now" }
        return "Nearby \(filter.displayName.lowercased())"
    }

    /// Fetches a small page of nearby spots around the supplied location.
    /// No-ops if a fetch is already in flight. Sorted ascending by distance
    /// so the first row is closest to the user.
    func loadNearby(from location: CLLocation?) {
        guard let location else {
            nearbySpots = []
            nearbyError = nil
            return
        }
        fetchTask?.cancel()
        fetchTask = Task { [placesAPI] in
            isLoadingNearby = true
            nearbyError = nil
            do {
                let result = try await placesAPI.searchNearby(
                    location: location,
                    radius: 1500,
                    pageToken: nil,
                    maxResults: 20
                )
                if Task.isCancelled { return }
                let hydrated = result.spots
                    .map { $0.withDistance(from: location) }
                    .sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
                nearbySpots = hydrated
            } catch {
                if Task.isCancelled { return }
                nearbyError = error.localizedDescription
            }
            isLoadingNearby = false
        }
    }

    /// Records a tapped spot in the recent searches list. Called from the
    /// view layer for both nearby-row taps and autocomplete-result taps.
    func recordRecent(placeId: String, name: String, address: String) {
        store.record(placeId: placeId, name: name, address: address)
    }

    /// Drops a stale recent — used when the upstream spot is gone.
    func removeRecent(placeId: String) {
        store.remove(placeId: placeId)
    }

    // MARK: - Test hook

    /// Seeds `nearbySpots` directly for unit tests so they don't have to
    /// stand up a fake PlacesAPIService. Internal so it stays out of the
    /// public surface; reachable from `@testable import`.
    func setNearbyForTesting(_ spots: [NearbySpot]) {
        self.nearbySpots = spots
    }
}
