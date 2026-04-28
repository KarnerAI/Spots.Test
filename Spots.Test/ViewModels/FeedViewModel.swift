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
        }
        actorsById.merge(actors) { _, new in new }
        spotsById.merge(spots) { _, new in new }
    }

    private func friendlyMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        // Most network errors are noisy; present a short surface message and keep the raw in logs.
        print("FeedViewModel error: \(error)")
        return "Couldn't load feed. \(raw)"
    }
}
