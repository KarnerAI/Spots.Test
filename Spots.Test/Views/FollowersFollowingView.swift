//
//  FollowersFollowingView.swift
//  Spots.Test
//
//  Followers + Following list, two tabs in one screen. Reachable from a profile's
//  stat row (Followers / Following stat tap). Shows server-search, infinite scroll,
//  optimistic remove (X), an Invite Friends CTA placeholder, and — on the Followers
//  tab — a Follow requests preview row that pushes FollowRequestsView.
//

import SwiftUI

struct FollowersFollowingView: View {
    let username: String?

    @StateObject private var vm: FollowersFollowingViewModel
    @State private var searchInput: String = ""
    @State private var profileToOpen: UUID?

    init(
        userId: UUID,
        initialTab: FollowersFollowingTab,
        username: String? = nil
    ) {
        self.username = username
        _vm = StateObject(
            wrappedValue: FollowersFollowingViewModel(
                userId: userId,
                initialTab: initialTab,
                onMutation: { ProfileSnapshotCache.shared.markStale() }
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().background(Color.gray200)

            ScrollView {
                LazyVStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    inviteFriendsCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    if vm.selectedTab == .followers, vm.pendingCount > 0 {
                        followRequestsRow
                    }

                    listSection
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color.white)
        .navigationTitle(username ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.onAppear() }
        .onChange(of: searchInput) { _, newValue in
            vm.searchTextChanged(newValue)
        }
        .navigationDestination(item: $profileToOpen) { userId in
            UserProfileView(userId: userId)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(vm.errorMessage ?? "") }
        )
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.followers, label: "Followers")
            tabButton(.following, label: "Following")
        }
        .frame(height: 48)
    }

    private func tabButton(_ tab: FollowersFollowingTab, label: String) -> some View {
        let isActive = vm.selectedTab == tab
        return Button {
            Task { await vm.selectTab(tab) }
        } label: {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Text(label)
                    .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .gray900 : .gray500)
                Rectangle()
                    .fill(isActive ? Color.gray900 : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray500)
            TextField("Search", text: $searchInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.gray100)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.field, style: .continuous))
    }

    // MARK: - Invite Friends CTA (disabled placeholder)

    private var inviteFriendsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Don't see someone you know?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.gray900)
            Text("Invite your friends to Spots")
                .font(.system(size: 13))
                .foregroundColor(.gray500)

            Button(action: {}) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Invite Friends")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundColor(.white)
                .background(Color.spotsTeal.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button, style: .continuous))
            }
            .disabled(true)
            // TODO: Wire to ShareLink with App Store URL once the App Store ID is finalized.
        }
        .padding(16)
        .background(Color.gray50)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
    }

    // MARK: - Follow requests (Followers tab only)

    private var followRequestsRow: some View {
        NavigationLink(destination: FollowRequestsView(
            onChanged: { Task { await vm.refreshPendingPreview() } }
        )) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(urlString: vm.pendingPreview?.profile.avatarUrl, size: 48)

                    if vm.pendingCount > 0 {
                        Text("+\(vm.pendingCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.spotsTeal)
                            .clipShape(Capsule())
                            .offset(x: 4, y: 4)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Follow requests")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.gray900)
                    Text(followRequestsSubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.gray500)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray400)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var followRequestsSubtitle: String {
        guard let preview = vm.pendingPreview else { return "\(vm.pendingCount) waiting" }
        let others = max(0, vm.pendingCount - 1)
        if others > 0 {
            return "\(preview.profile.username) + \(others) others"
        } else {
            return preview.profile.username
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listSection: some View {
        switch vm.selectedTab {
        case .followers:
            renderList(
                items: vm.followers,
                isLoading: vm.isLoadingFollowers,
                isLoadingMore: vm.isLoadingMoreFollowers,
                emptyTitle: "No followers yet",
                onRemove: { profile in Task { await vm.removeFollower(profile) } }
            )
        case .following:
            renderList(
                items: vm.following,
                isLoading: vm.isLoadingFollowing,
                isLoadingMore: vm.isLoadingMoreFollowing,
                emptyTitle: "Not following anyone yet",
                onRemove: { profile in Task { await vm.unfollow(profile) } }
            )
        }
    }

    @ViewBuilder
    private func renderList(
        items: [UserProfile],
        isLoading: Bool,
        isLoadingMore: Bool,
        emptyTitle: String,
        onRemove: @escaping (UserProfile) -> Void
    ) -> some View {
        if isLoading && items.isEmpty {
            ProgressView()
                .padding(.top, 48)
                .frame(maxWidth: .infinity)
        } else if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(.system(size: 36))
                    .foregroundColor(.gray400)
                Text(emptyTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray500)
            }
            .padding(.top, 48)
            .frame(maxWidth: .infinity)
        } else {
            ForEach(items) { profile in
                UserListRowView(
                    profile: profile,
                    onViewProfile: { profileToOpen = profile.id },
                    onRemove: { onRemove(profile) },
                    isRemoving: vm.isMutating.contains(profile.id)
                )
                .task { await vm.loadMoreIfNeeded(currentItem: profile) }
                Divider().padding(.leading, 76)
            }

            if isLoadingMore {
                ProgressView()
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
