//
//  FollowersFollowingViewModel.swift
//  Spots.Test
//
//  Drives the Followers / Following screen. Owns paginated lists for both tabs,
//  debounced server-side search, optimistic mutations (remove follower / unfollow),
//  and the Followers-tab "follow requests" preview.
//

import Foundation
import SwiftUI

enum FollowersFollowingTab: String, Hashable {
    case followers
    case following
}

@MainActor
final class FollowersFollowingViewModel: ObservableObject {
    // MARK: - Inputs
    let userId: UUID

    // MARK: - Published state

    @Published var selectedTab: FollowersFollowingTab
    @Published var searchText: String = ""

    @Published private(set) var followers: [UserProfile] = []
    @Published private(set) var following: [UserProfile] = []
    @Published private(set) var followersCanLoadMore = true
    @Published private(set) var followingCanLoadMore = true

    @Published private(set) var pendingPreview: PendingRequest?
    @Published private(set) var pendingCount: Int = 0

    @Published private(set) var isLoadingFollowers = false
    @Published private(set) var isLoadingFollowing = false
    @Published private(set) var isLoadingMoreFollowers = false
    @Published private(set) var isLoadingMoreFollowing = false
    @Published private(set) var isMutating: Set<UUID> = []
    @Published var errorMessage: String?

    // MARK: - Private

    private let service: FollowServiceProtocol
    private let pageSize: Int
    private let searchDebounceNanos: UInt64

    /// Called after any successful mutation (remove follower / unfollow). The view
    /// wires this to invalidate caches like ProfileSnapshotCache so a back-nav
    /// re-fetches stat counts. Default no-op keeps tests isolated from real singletons.
    private let onMutationCallback: () -> Void

    /// Cursor — last loaded row's `follows.created_at` per tab. Drives infinite scroll.
    private var followersCursor: Date?
    private var followingCursor: Date?

    /// Marks whether we've fetched at least once for the active query. Reset on search change.
    private var followersLoadedForCurrentQuery = false
    private var followingLoadedForCurrentQuery = false

    /// In-flight debounced search task; canceled when input changes so stale results
    /// can't overwrite a newer query.
    private var searchTask: Task<Void, Never>?

    init(
        userId: UUID,
        initialTab: FollowersFollowingTab,
        service: FollowServiceProtocol = FollowService.shared,
        pageSize: Int = 50,
        searchDebounceNanos: UInt64 = 300_000_000,
        onMutation: @escaping () -> Void = {}
    ) {
        self.userId = userId
        self.selectedTab = initialTab
        self.service = service
        self.pageSize = pageSize
        self.searchDebounceNanos = searchDebounceNanos
        self.onMutationCallback = onMutation
    }

    // MARK: - Lifecycle

    func onAppear() async {
        await loadCurrentTabIfNeeded()
        if selectedTab == .followers {
            await loadPendingPreview()
        }
    }

    func selectTab(_ tab: FollowersFollowingTab) async {
        guard tab != selectedTab else { return }
        selectedTab = tab
        await loadCurrentTabIfNeeded()
        if tab == .followers && pendingPreview == nil && pendingCount == 0 {
            await loadPendingPreview()
        }
    }

    /// Push debounced search input. Cancels any in-flight search and refetches
    /// page 1 for the active tab once the debounce window elapses.
    func searchTextChanged(_ newValue: String) {
        searchText = newValue
        searchTask?.cancel()
        let debounce = searchDebounceNanos
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            if Task.isCancelled { return }
            guard let self else { return }
            await self.refetchActiveTabFromScratch()
        }
    }

    // MARK: - Loaders

    private func loadCurrentTabIfNeeded() async {
        switch selectedTab {
        case .followers:
            if !followersLoadedForCurrentQuery && !isLoadingFollowers {
                await loadFollowersPage(reset: true)
            }
        case .following:
            if !followingLoadedForCurrentQuery && !isLoadingFollowing {
                await loadFollowingPage(reset: true)
            }
        }
    }

    private func refetchActiveTabFromScratch() async {
        switch selectedTab {
        case .followers:
            followersLoadedForCurrentQuery = false
            await loadFollowersPage(reset: true)
        case .following:
            followingLoadedForCurrentQuery = false
            await loadFollowingPage(reset: true)
        }
    }

    func loadMoreIfNeeded(currentItem: UserProfile) async {
        switch selectedTab {
        case .followers:
            guard followers.last?.id == currentItem.id, followersCanLoadMore, !isLoadingMoreFollowers else { return }
            await loadFollowersPage(reset: false)
        case .following:
            guard following.last?.id == currentItem.id, followingCanLoadMore, !isLoadingMoreFollowing else { return }
            await loadFollowingPage(reset: false)
        }
    }

    private func loadFollowersPage(reset: Bool) async {
        if reset {
            isLoadingFollowers = true
            followersCursor = nil
            followersCanLoadMore = true
        } else {
            isLoadingMoreFollowers = true
        }
        defer {
            isLoadingFollowers = false
            isLoadingMoreFollowers = false
        }

        do {
            let q = currentQuery()
            let page = try await service.followers(
                userId: userId,
                query: q,
                limit: pageSize,
                before: reset ? nil : followersCursor
            )
            if reset {
                followers = dedup(page.profiles)
            } else {
                followers = dedup(followers + page.profiles)
            }
            followersCursor = page.nextCursor
            followersCanLoadMore = page.profiles.count == pageSize && page.nextCursor != nil
            followersLoadedForCurrentQuery = true
        } catch is CancellationError {
            // ignored
        } catch {
            errorMessage = "Couldn't load followers. \(error.localizedDescription)"
            followersCanLoadMore = false
        }
    }

    private func loadFollowingPage(reset: Bool) async {
        if reset {
            isLoadingFollowing = true
            followingCursor = nil
            followingCanLoadMore = true
        } else {
            isLoadingMoreFollowing = true
        }
        defer {
            isLoadingFollowing = false
            isLoadingMoreFollowing = false
        }

        do {
            let q = currentQuery()
            let page = try await service.following(
                userId: userId,
                query: q,
                limit: pageSize,
                before: reset ? nil : followingCursor
            )
            if reset {
                following = dedup(page.profiles)
            } else {
                following = dedup(following + page.profiles)
            }
            followingCursor = page.nextCursor
            followingCanLoadMore = page.profiles.count == pageSize && page.nextCursor != nil
            followingLoadedForCurrentQuery = true
        } catch is CancellationError {
            // ignored
        } catch {
            errorMessage = "Couldn't load following. \(error.localizedDescription)"
            followingCanLoadMore = false
        }
    }

    private func loadPendingPreview() async {
        do {
            async let preview = service.pendingRequests(limit: 1)
            async let count = service.pendingRequestCount()
            let (p, c) = try await (preview, count)
            pendingPreview = p.first
            pendingCount = c
        } catch {
            // Pending preview is decorative — never block the main list load.
        }
    }

    // MARK: - Mutations

    /// X tap on a Followers row — remove that user as a follower.
    func removeFollower(_ profile: UserProfile) async {
        guard !isMutating.contains(profile.id) else { return }
        isMutating.insert(profile.id)
        defer { isMutating.remove(profile.id) }

        let original = followers
        followers.removeAll { $0.id == profile.id }
        do {
            try await service.removeFollower(userId: profile.id)
            onMutation()
        } catch {
            followers = original
            errorMessage = "Couldn't remove follower. \(error.localizedDescription)"
        }
    }

    /// X tap on a Following row — unfollow that user.
    func unfollow(_ profile: UserProfile) async {
        guard !isMutating.contains(profile.id) else { return }
        isMutating.insert(profile.id)
        defer { isMutating.remove(profile.id) }

        let original = following
        following.removeAll { $0.id == profile.id }
        do {
            try await service.unfollow(userId: profile.id)
            onMutation()
        } catch {
            following = original
            errorMessage = "Couldn't unfollow. \(error.localizedDescription)"
        }
    }

    /// Notify the rest of the app that follow-graph state changed, so caches
    /// (e.g. ProfileSnapshotCache) can refresh on next presentation.
    private func onMutation() {
        onMutationCallback()
    }

    /// Refresh the Follow Requests preview row — call after returning from
    /// FollowRequestsView so the row reflects post-accept/reject state.
    func refreshPendingPreview() async {
        await loadPendingPreview()
    }

    // MARK: - Helpers

    private func currentQuery() -> String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func dedup(_ profiles: [UserProfile]) -> [UserProfile] {
        var seen = Set<UUID>()
        return profiles.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Service Protocol

/// Narrow protocol over the FollowService surface this view model needs.
/// Lets tests inject a mock without touching the Supabase singleton.
protocol FollowServiceProtocol {
    func followers(userId: UUID, query: String?, limit: Int, before: Date?) async throws -> FollowService.FollowListPage
    func following(userId: UUID, query: String?, limit: Int, before: Date?) async throws -> FollowService.FollowListPage
    func removeFollower(userId: UUID) async throws
    func unfollow(userId: UUID) async throws
    func pendingRequests(limit: Int) async throws -> [PendingRequest]
    func pendingRequestCount() async throws -> Int
}

extension FollowService: FollowServiceProtocol {}
