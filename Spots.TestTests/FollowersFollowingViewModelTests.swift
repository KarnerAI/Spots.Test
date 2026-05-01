//
//  FollowersFollowingViewModelTests.swift
//  Spots.TestTests
//
//  Behavior tests for the Followers / Following screen view model. The view
//  model is the source of truth for tab state, paginated lists, debounced
//  server search, and optimistic mutations — exercised here with a mock
//  FollowServiceProtocol so no Supabase connection is required.
//

import Testing
import Foundation
@testable import Spots_Test

// MARK: - Mock service

@MainActor
final class MockFollowService: FollowServiceProtocol {
    var followersPages: [FollowService.FollowListPage] = []
    var followingPages: [FollowService.FollowListPage] = []
    var followersError: Error?
    var followingError: Error?
    var removeFollowerError: Error?
    var unfollowError: Error?

    var followersCalls: [(userId: UUID, query: String?, limit: Int, before: Date?)] = []
    var followingCalls: [(userId: UUID, query: String?, limit: Int, before: Date?)] = []
    var removeFollowerCalls: [UUID] = []
    var unfollowCalls: [UUID] = []
    var pendingRequestsCalls: [Int] = []

    var pendingRequestsResult: [PendingRequest] = []
    var pendingRequestCountResult: Int = 0

    func followers(userId: UUID, query: String?, limit: Int, before: Date?) async throws -> FollowService.FollowListPage {
        followersCalls.append((userId, query, limit, before))
        if let followersError { throw followersError }
        if followersPages.isEmpty { return FollowService.FollowListPage(profiles: [], nextCursor: nil) }
        return followersPages.removeFirst()
    }

    func following(userId: UUID, query: String?, limit: Int, before: Date?) async throws -> FollowService.FollowListPage {
        followingCalls.append((userId, query, limit, before))
        if let followingError { throw followingError }
        if followingPages.isEmpty { return FollowService.FollowListPage(profiles: [], nextCursor: nil) }
        return followingPages.removeFirst()
    }

    func removeFollower(userId: UUID) async throws {
        removeFollowerCalls.append(userId)
        if let removeFollowerError { throw removeFollowerError }
    }

    func unfollow(userId: UUID) async throws {
        unfollowCalls.append(userId)
        if let unfollowError { throw unfollowError }
    }

    func pendingRequests(limit: Int) async throws -> [PendingRequest] {
        pendingRequestsCalls.append(limit)
        return pendingRequestsResult
    }

    func pendingRequestCount() async throws -> Int {
        pendingRequestCountResult
    }
}

// MARK: - Helpers

private func makeProfile(_ name: String) -> UserProfile {
    let json = """
    {"id":"\(UUID().uuidString)","username":"\(name)","is_private":false}
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(UserProfile.self, from: json)
}

private func page(_ profiles: [UserProfile], cursor: Date? = Date()) -> FollowService.FollowListPage {
    FollowService.FollowListPage(profiles: profiles, nextCursor: cursor)
}

@MainActor
private func makeVM(
    initialTab: FollowersFollowingTab = .followers,
    pageSize: Int = 50,
    debounceNanos: UInt64 = 1_000_000   // 1ms — keep tests snappy
) -> (FollowersFollowingViewModel, MockFollowService) {
    let mock = MockFollowService()
    let vm = FollowersFollowingViewModel(
        userId: UUID(),
        initialTab: initialTab,
        service: mock,
        pageSize: pageSize,
        searchDebounceNanos: debounceNanos
    )
    return (vm, mock)
}

// MARK: - Tests

@MainActor
struct FollowersFollowingViewModelTests {

    @Test func initialLoad_fetchesActiveTabAndPendingPreview() async {
        let (vm, mock) = makeVM(initialTab: .followers)
        mock.followersPages = [page([makeProfile("a"), makeProfile("b")])]
        mock.pendingRequestCountResult = 5

        await vm.onAppear()

        #expect(vm.followers.count == 2)
        #expect(mock.followersCalls.count == 1)
        #expect(mock.pendingRequestsCalls == [1])  // preview limit:1
        #expect(vm.pendingCount == 5)
    }

    @Test func tabSwitch_fetchesOtherTabOnFirstSwitch() async {
        let (vm, mock) = makeVM(initialTab: .followers)
        mock.followersPages = [page([makeProfile("a")])]
        mock.followingPages = [page([makeProfile("b")])]

        await vm.onAppear()
        #expect(vm.followers.count == 1)
        #expect(mock.followingCalls.count == 0)

        await vm.selectTab(.following)
        #expect(vm.following.count == 1)
        #expect(mock.followingCalls.count == 1)
    }

    @Test func tabSwitch_doesNotRefetch_ifAlreadyLoaded() async {
        let (vm, mock) = makeVM(initialTab: .followers)
        mock.followersPages = [page([makeProfile("a")])]
        mock.followingPages = [page([makeProfile("b")])]

        await vm.onAppear()
        await vm.selectTab(.following)
        #expect(mock.followingCalls.count == 1)

        await vm.selectTab(.followers)
        await vm.selectTab(.following)
        #expect(mock.followingCalls.count == 1)
        #expect(mock.followersCalls.count == 1)
    }

    @Test func searchInput_debounced_resetsToPageOneWithQuery() async {
        let (vm, mock) = makeVM(initialTab: .followers, debounceNanos: 1_000_000)
        mock.followersPages = [page([makeProfile("a")]), page([makeProfile("hermione")])]

        await vm.onAppear()
        #expect(mock.followersCalls.count == 1)
        #expect(mock.followersCalls[0].query == nil)

        vm.searchTextChanged("her")
        // Wait beyond debounce
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(mock.followersCalls.count == 2)
        #expect(mock.followersCalls[1].query == "her")
        #expect(mock.followersCalls[1].before == nil) // reset to page 1
    }

    @Test func infiniteScroll_appendsPageTwo_withCorrectCursor() async {
        let (vm, mock) = makeVM(initialTab: .followers, pageSize: 2)
        let cursor = Date(timeIntervalSince1970: 1_700_000_000)
        mock.followersPages = [
            page([makeProfile("a"), makeProfile("b")], cursor: cursor),
            page([makeProfile("c"), makeProfile("d")], cursor: nil)
        ]

        await vm.onAppear()
        #expect(vm.followers.count == 2)

        // Trigger load-more by signaling we've reached the last item
        await vm.loadMoreIfNeeded(currentItem: vm.followers.last!)
        #expect(vm.followers.count == 4)
        #expect(mock.followersCalls.count == 2)
        #expect(mock.followersCalls[1].before == cursor)
        #expect(vm.followersCanLoadMore == false)  // last page returned nil cursor
    }

    @Test func xOnFollower_callsRemoveFollower_andRemovesRowOptimistically() async {
        let (vm, mock) = makeVM(initialTab: .followers)
        let target = makeProfile("target")
        mock.followersPages = [page([target, makeProfile("other")])]

        await vm.onAppear()
        #expect(vm.followers.count == 2)

        await vm.removeFollower(target)
        #expect(vm.followers.count == 1)
        #expect(vm.followers.first?.id != target.id)
        #expect(mock.removeFollowerCalls == [target.id])
    }

    @Test func xOnFollower_revertsRow_onError() async {
        struct E: Error {}
        let (vm, mock) = makeVM(initialTab: .followers)
        let target = makeProfile("target")
        mock.followersPages = [page([target])]
        mock.removeFollowerError = E()

        await vm.onAppear()
        await vm.removeFollower(target)

        #expect(vm.followers.count == 1)  // reverted
        #expect(vm.errorMessage != nil)
    }

    @Test func xOnFollowing_callsUnfollow() async {
        let (vm, mock) = makeVM(initialTab: .following)
        let target = makeProfile("target")
        mock.followingPages = [page([target])]

        await vm.onAppear()
        await vm.unfollow(target)

        #expect(vm.following.isEmpty)
        #expect(mock.unfollowCalls == [target.id])
    }

    @Test func error_setsErrorMessage_andStopsLoading() async {
        struct E: Error {}
        let (vm, mock) = makeVM(initialTab: .followers)
        mock.followersError = E()

        await vm.onAppear()

        #expect(vm.followers.isEmpty)
        #expect(vm.errorMessage != nil)
        #expect(vm.isLoadingFollowers == false)
    }
}
