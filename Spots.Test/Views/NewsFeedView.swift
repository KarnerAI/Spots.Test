//
//  NewsFeedView.swift
//  Spots.Test
//
//  Following-only newsfeed. Drives FeedViewModel; pushes navigation into
//  UserProfileView (for actor taps) and a placeholder list-detail view
//  (Phase 2 will replace with a viewer-aware list view).
//

import SwiftUI

struct NewsFeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var presentSearch = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .background(Color.gray100.ignoresSafeArea())
                .navigationTitle("Feed")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .navigationDestination(for: FeedRoute.self) { route in
                    destination(for: route)
                }
                .task {
                    await viewModel.loadInitial()
                    await viewModel.refreshPendingRequestCount()
                }
                .refreshable {
                    await viewModel.refresh()
                    await viewModel.refreshPendingRequestCount()
                }
                .sheet(isPresented: $presentSearch) {
                    NavigationStack {
                        SearchView(
                            onSelectSpot: { _ in presentSearch = false },
                            initialSearchMode: .users
                        )
                    }
                }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: FeedRoute.requests) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "tray")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.gray900)
                    if viewModel.pendingRequestCount > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -2)
                    }
                }
                .frame(width: 44, height: 44)
            }
        }
    }

    // MARK: - Content state machine

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingInitial && viewModel.items.isEmpty {
            loadingState
        } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
            SpotsErrorStateView(message: errorMessage) {
                Task { await viewModel.loadInitial(forceRefresh: true) }
            }
        } else if viewModel.items.isEmpty {
            emptyState
        } else {
            feedList
        }
    }

    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonSpotCard()
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundColor(.gray400)
            Text("Your feed is empty")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.gray900)
            Text("Follow people to see their saved spots and lists here.")
                .font(.system(size: 14))
                .foregroundColor(.gray500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Button {
                presentSearch = true
            } label: {
                Text("Find People")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.spotsTeal)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button, style: .continuous))
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Feed list

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.items) { item in
                    feedRow(item)
                        .padding(.horizontal, 16)
                        .onAppear {
                            if item.id == viewModel.items.last?.id {
                                Task { await viewModel.loadMore() }
                            }
                        }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding(.vertical, 16)
                }

                // Bottom spacer so the last card clears the custom bottom nav.
                Color.clear.frame(height: 88)
            }
            .padding(.vertical, 16)
        }
    }

    private func feedRow(_ item: FeedItem) -> some View {
        let actor = viewModel.actorsById[item.actorId]
        let spot: Spot? = {
            if case .spotSave(let payload) = item.payload {
                return viewModel.spotsById[payload.spotId]
            }
            return nil
        }()

        return FeedItemCardView(
            item: item,
            actor: actor,
            spot: spot,
            onTapActor: {
                navigationPath.append(FeedRoute.user(item.actorId))
            },
            onTap: {
                switch item.payload {
                case .listCreated(let payload):
                    navigationPath.append(
                        FeedRoute.list(actorId: item.actorId, listId: payload.listId, name: payload.listDisplayName)
                    )
                case .spotSave(let payload):
                    navigationPath.append(
                        FeedRoute.list(actorId: item.actorId, listId: payload.listId, name: payload.listDisplayName)
                    )
                }
            }
        )
    }

    // MARK: - Routes

    @ViewBuilder
    private func destination(for route: FeedRoute) -> some View {
        switch route {
        case .user(let id):
            UserProfileView(userId: id)
        case .list(_, _, let name):
            // Phase 1: ListDetailView is hardcoded to the current user's data via singletons.
            // A viewer-aware list view lands in Phase 2.
            FeedListPlaceholderView(title: name)
        case .requests:
            FollowRequestsView {
                Task { await viewModel.refreshPendingRequestCount() }
            }
        }
    }
}

// MARK: - Routes

enum FeedRoute: Hashable {
    case user(UUID)
    case list(actorId: UUID, listId: UUID, name: String)
    case requests
}

// MARK: - Placeholder for another user's list (Phase 2 will replace with a real list view)

private struct FeedListPlaceholderView: View {
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 48))
                .foregroundColor(.gray400)
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.gray900)
            Text("Viewing other users' lists is coming next.")
                .font(.system(size: 14))
                .foregroundColor(.gray500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NewsFeedView()
}
