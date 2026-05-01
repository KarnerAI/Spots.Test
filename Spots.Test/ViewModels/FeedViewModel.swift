//
//  FeedViewModel.swift
//  Spots.Test
//
//  Drives NewsFeedView. Owns the paginated feed list, the actor/spot lookup
//  side-tables, and the pending-follow-request badge count.
//

import Foundation
import SwiftUI

@MainActor
class FeedViewModel: ObservableObject {
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var actorsById: [UUID: UserProfile] = [:]
    @Published private(set) var spotsById: [String: Spot] = [:]
    @Published private(set) var pendingRequestCount: Int = 0

    @Published var isLoadingInitial = false
    @Published var isRefreshing = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?

    private let feedService = FeedService.shared
    private let followService = FollowService.shared

    private let pageSize = 20
    private var hasMore = true
    private var lastLoadedAt: Date?
    private let staleInterval: TimeInterval = 60

    /// Place ids whose Places-details fetch is in flight or already merged this
    /// session. Prevents loadMore from re-issuing details for spots that an
    /// earlier page already enriched (or is mid-enriching).
    private var enrichedPlaceIds: Set<String> = []

    var canLoadMore: Bool { hasMore && !isLoadingMore && !isLoadingInitial }

    // MARK: - Initial load (entering the tab)

    /// Loads the first page if we don't have anything cached or our cache is stale.
    /// Cheap to call from `.onAppear`.
    func loadInitial(forceRefresh: Bool = false) async {
        if !forceRefresh,
           let last = lastLoadedAt,
           Date().timeIntervalSince(last) < staleInterval,
           !items.isEmpty {
            return
        }
        isLoadingInitial = true
        errorMessage = nil
        await loadFirstPage()
        isLoadingInitial = false
    }

    // MARK: - Pull to refresh

    func refresh() async {
        isRefreshing = true
        errorMessage = nil
        await loadFirstPage()
        isRefreshing = false
    }

    // MARK: - Pagination

    func loadMore() async {
        guard canLoadMore, let cursor = items.last?.createdAt else { return }
        isLoadingMore = true
        do {
            let next = try await feedService.fetchFeed(cursor: cursor, limit: pageSize)
            try await hydrate(next, append: true)
            hasMore = next.count >= pageSize
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
        isLoadingMore = false
    }

    // MARK: - Pending follow requests (toolbar badge)

    func refreshPendingRequestCount() async {
        do {
            pendingRequestCount = try await followService.pendingRequestCount()
        } catch {
            // Non-fatal — badge just won't update. Avoid surfacing as a hard error.
            print("FeedViewModel: pendingRequestCount failed: \(error)")
        }
    }

    // MARK: - Private

    private func loadFirstPage() async {
        do {
            let page = try await feedService.fetchFeed(cursor: nil, limit: pageSize)
            try await hydrate(page, append: false)
            hasMore = page.count >= pageSize
            lastLoadedAt = Date()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func hydrate(_ newItems: [FeedItem], append: Bool) async throws {
        // Fetch actors + spots for this page in parallel before mutating @Published state.
        async let actorsTask = feedService.loadActors(for: newItems)
        async let spotsTask = feedService.loadSpots(for: newItems)
        let (actors, spots) = try await (actorsTask, spotsTask)

        if append {
            items.append(contentsOf: newItems)
        } else {
            items = newItems
            // Fresh page — allow failed/stale enrichments to retry on this load.
            enrichedPlaceIds.removeAll(keepingCapacity: true)
        }
        actorsById.merge(actors) { _, new in new }
        spotsById.merge(spots) { _, new in new }

        // Lazy enrichment: any spot with missing display data (photo, city, types,
        // rating) gets a Google Places lookup so the new hero card always has the
        // fields it needs. Detached so the loading spinner clears as soon as the
        // basic feed is published; cards will fill in via @Published as fetches
        // complete.
        Task { [weak self] in
            await self?.enrichMissingSpotFields(for: newItems)
        }
    }

    /// For every referenced spot whose cached row is sparse, fetch Google
    /// Places details with bounded concurrency, merge into `spotsById`, and
    /// fire-and-forget an `upsertSpot` so the next session reads complete
    /// data straight from Supabase without re-hitting Google.
    ///
    /// Concurrency is capped at `enrichmentConcurrencyLimit` so a feed page
    /// referencing many sparse spots doesn't burst the Google Places quota.
    private func enrichMissingSpotFields(for items: [FeedItem]) async {
        let referencedPlaceIds: [String] = items.compactMap {
            if case .spotSave(let p) = $0.payload { return p.spotId }
            return nil
        }
        let needsEnrichment = Array(Set(referencedPlaceIds.filter { placeId in
            guard !enrichedPlaceIds.contains(placeId) else { return false }
            guard let spot = spotsById[placeId] else { return true }
            return spot.needsEnrichment
        }))
        guard !needsEnrichment.isEmpty else { return }

        // Mark in flight up-front so a concurrent page doesn't re-issue the
        // same Places lookups before this group resolves.
        enrichedPlaceIds.formUnion(needsEnrichment)

        await withTaskGroup(of: (String, Spot?).self) { group in
            var iterator = needsEnrichment.makeIterator()
            var inFlight = 0

            // Prime the pump up to the concurrency limit.
            while inFlight < Self.enrichmentConcurrencyLimit, let placeId = iterator.next() {
                group.addTask { await Self.fetchEnrichment(placeId: placeId) }
                inFlight += 1
            }

            while let (placeId, fetched) = await group.next() {
                inFlight -= 1
                if let fetched {
                    let merged: Spot
                    if let existing = spotsById[placeId] {
                        merged = existing.merging(missingFieldsFrom: fetched)
                    } else {
                        merged = fetched
                    }
                    spotsById[placeId] = merged
                    persistEnrichment(merged)
                }

                // Refill the slot.
                if let nextPlaceId = iterator.next() {
                    group.addTask { await Self.fetchEnrichment(placeId: nextPlaceId) }
                    inFlight += 1
                }
            }
        }
    }

    private static let enrichmentConcurrencyLimit = 4

    private static func fetchEnrichment(placeId: String) async -> (String, Spot?) {
        do {
            let nearby = try await PlacesAPIService.shared.fetchPlaceDetails(placeId: placeId)
            return (placeId, nearby?.toSpot())
        } catch {
            print("FeedViewModel.enrich: \(placeId) failed: \(error)")
            return (placeId, nil)
        }
    }

    /// Fire-and-forget DB writeback so the spots row catches up. We don't wait
    /// on this — the UI already has the merged value via @Published, and a
    /// failed write only means we'll re-enrich the same row next session.
    private func persistEnrichment(_ spot: Spot) {
        Task.detached(priority: .background) {
            do {
                try await LocationSavingService.shared.upsertSpot(
                    placeId: spot.placeId,
                    name: spot.name,
                    address: spot.address,
                    city: spot.city,
                    country: spot.country,
                    latitude: spot.latitude,
                    longitude: spot.longitude,
                    types: spot.types,
                    photoUrl: spot.photoUrl,
                    photoReference: spot.photoReference,
                    rating: spot.rating
                )
            } catch {
                print("FeedViewModel.persistEnrichment: \(spot.placeId) failed: \(error)")
            }
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        // Most network errors are noisy; present a short surface message and keep the raw in logs.
        print("FeedViewModel error: \(error)")
        return "Couldn't load feed. \(raw)"
    }
}
