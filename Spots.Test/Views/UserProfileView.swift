//
//  UserProfileView.swift
//  Spots.Test
//
//  Read-only profile of another user. Mirrors the layout of `ProfileView`
//  (cover, avatar, name + handle, stats row, "My Lists" tiles, Travel Map),
//  swapping the Settings/Edit affordances for a Follow / Following / Requested
//  button. When the target is private and the viewer is not an accepted
//  follower, the lists + travel sections fall back to a lock state while the
//  header and stats stay visible — matching Instagram-style gating.
//

import SwiftUI
import UIKit

struct UserProfileView: View {
    let userId: UUID

    @State private var profile: UserProfile?
    @State private var relationship: FollowRelationship = .none
    @State private var isLoadingProfile: Bool
    @State private var isMutatingFollow = false
    @State private var errorMessage: String?

    /// Seed `profile` synchronously from ProfileService's cache so navigating
    /// from feed / search / followers lists paints the header instantly.
    /// Cache miss = same behavior as before (spinner until network resolves).
    init(userId: UUID) {
        self.userId = userId
        let cached = ProfileService.shared.cachedProfile(userId: userId)
        _profile = State(initialValue: cached)
        _isLoadingProfile = State(initialValue: cached == nil)
    }

    @State private var followersCount: Int = 0
    @State private var followingCount: Int = 0
    @State private var spotsCount: Int = 0
    @State private var mostExploredCity: String?
    @State private var coverImage: UIImage?
    @State private var listTiles: [ListTileData] = []
    @State private var travelMapSegment: Int = 0

    private let coverHeight: CGFloat = 260
    private let cardOverlap: CGFloat = 30
    private let photoSize: CGFloat = 96
    private let sheetTopCornerRadius: CGFloat = CornerRadius.sheet

    private var photoOffset: CGFloat {
        coverHeight - cardOverlap - photoSize / 2
    }

    private var canSeeContent: Bool {
        guard let profile else { return false }
        if !profile.isPrivate { return true }
        return relationship == .following || relationship == .mutual || relationship == .isSelf
    }

    private let placeholderCities: [CityRowData] = [
        CityRowData(name: "New York",      count: 0),
        CityRowData(name: "Los Angeles",   count: 0),
        CityRowData(name: "San Francisco", count: 0),
        CityRowData(name: "Chicago",       count: 0),
        CityRowData(name: "Miami",         count: 0),
        CityRowData(name: "Boston",        count: 0),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    coverSection
                    whiteCard
                        .offset(y: -cardOverlap)
                }

                profilePhoto
                    .offset(y: photoOffset)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.gray100)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let errorMessage {
                ErrorToast(message: errorMessage)
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task { await load() }
    }

    // MARK: - Cover

    private var coverSection: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color.gray400, Color.gray600],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: coverHeight)

            if let image = coverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: coverHeight)
                    .clipped()
            }

            LinearGradient(
                colors: [Color.black.opacity(0.2), Color.black.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: coverHeight)
        }
        .frame(height: coverHeight)
        .clipped()
    }

    // MARK: - Profile Photo

    private var profilePhoto: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: photoSize + 6, height: photoSize + 6)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)

            AvatarView(urlString: profile?.avatarUrl, size: photoSize)
        }
    }

    // MARK: - White Card

    private var whiteCard: some View {
        VStack(alignment: .center, spacing: 0) {
            Spacer().frame(height: photoSize / 2 + 16)

            profileInfoSection

            statsSection
                .padding(.top, 12)

            followButton
                .padding(.top, 4)
                .padding(.bottom, 16)

            Divider()
                .background(Color.gray200)
                .padding(.horizontal, 20)

            if isLoadingProfile {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
            } else if !canSeeContent {
                lockState
                    .padding(.top, 24)
            } else {
                myListsSection
                    .padding(.top, 20)

                travelMapSection
                    .padding(.top, 28)
            }

            Spacer().frame(height: 100)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedTopCornersBackground(radius: sheetTopCornerRadius))
        .transaction { $0.animation = nil }
    }

    // MARK: - Profile Info

    private var profileInfoSection: some View {
        VStack(spacing: 4) {
            Text(profile?.displayName ?? " ")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))
                .multilineTextAlignment(.center)

            if let username = profile?.username {
                Text("@\(username)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray500)
            }

            if profile?.isPrivate == true {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill").font(.system(size: 11))
                    Text("Private account").font(.system(size: 12))
                }
                .foregroundColor(.gray500)
                .padding(.top, 2)
            } else if let city = mostExploredCity {
                HStack(spacing: 4) {
                    Text("Most Explored:")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.29, green: 0.34, blue: 0.42))
                    Text(city)
                        .font(.system(size: 14))
                        .foregroundColor(.spotsTeal)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Stats Row

    private var statsSection: some View {
        HStack(spacing: 32) {
            statItem(value: "\(spotsCount)", label: "Spots", tappable: false) {
                EmptyView()
            }
            statItem(value: "\(followersCount)", label: "Followers", tappable: canSeeContent) {
                FollowersFollowingView(
                    userId: userId,
                    initialTab: .followers,
                    username: profile?.username
                )
            }
            statItem(value: "\(followingCount)", label: "Following", tappable: canSeeContent) {
                FollowersFollowingView(
                    userId: userId,
                    initialTab: .following,
                    username: profile?.username
                )
            }
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func statItem<Destination: View>(
        value: String,
        label: String,
        tappable: Bool,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        if tappable {
            NavigationLink(destination: destination()) {
                statItemLabel(value: value, label: label)
            }
            .buttonStyle(.plain)
        } else {
            statItemLabel(value: value, label: label)
        }
    }

    private func statItemLabel(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16))
                .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.gray500)
        }
        // Without contentShape, only the rendered text glyphs catch taps —
        // the gap between the number and the label is a dead zone. A clear
        // rectangle over the VStack bounds makes the whole stat tappable
        // with zero visual change.
        .contentShape(Rectangle())
    }

    // MARK: - Follow Button

    @ViewBuilder
    private var followButton: some View {
        switch relationship {
        case .isSelf:
            EmptyView()
        case .none, .followsYou:
            Button(action: { Task { await tapFollow() } }) {
                buttonLabel(text: relationship == .followsYou ? "Follow back" : "Follow",
                            style: .primary)
            }
            .disabled(isMutatingFollow)
        case .requested:
            Button(action: { Task { await tapUnfollow() } }) {
                buttonLabel(text: "Requested", style: .secondary)
            }
            .disabled(isMutatingFollow)
        case .following, .mutual:
            Button(action: { Task { await tapUnfollow() } }) {
                buttonLabel(text: relationship == .mutual ? "Friends" : "Following",
                            style: .secondary)
            }
            .disabled(isMutatingFollow)
        }
    }

    private enum ButtonStyleKind { case primary, secondary }

    private func buttonLabel(text: String, style: ButtonStyleKind) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(style == .primary ? .white : .gray700)
            .padding(.horizontal, 36)
            .padding(.vertical, 10)
            .background(style == .primary ? Color.spotsTeal : Color.gray100)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button, style: .continuous))
    }

    // MARK: - Lock State

    private var lockState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundColor(.gray400)
            Text("This account is private")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.gray900)
            Text("Follow this account to see their saved spots and lists.")
                .font(.system(size: 13))
                .foregroundColor(.gray500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - My Lists

    private var myListsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Lists")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))
                Spacer()
            }
            .padding(.horizontal, 20)

            if listTiles.isEmpty {
                Text("No public lists yet")
                    .font(.system(size: 13))
                    .foregroundColor(.gray500)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(listTiles, id: \.title) { tile in
                            NavigationLink(destination: destinationView(for: tile)) {
                                listCard(tile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    @ViewBuilder
    private func destinationView(for tile: ListTileData) -> some View {
        if tile.isAllSpots {
            ListDetailView(
                title: tile.title,
                mode: .allSpotsForLists(listTiles.compactMap { $0.userList })
            )
        } else if let list = tile.userList {
            ListDetailView(title: tile.title, mode: .singleList(list))
        }
    }

    private func listCard(_ list: ListTileData) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let urlString = list.coverImageUrl, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(list.fallbackColor)
                    }
                }
                .frame(width: 140, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
            } else if let ref = list.coverPhotoReference {
                GooglePlacesImageView(photoReference: ref, maxWidth: 280)
                    .frame(width: 140, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                    .fill(list.fallbackColor)
                    .frame(width: 140, height: 150)
            }

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
            .frame(width: 140, height: 150)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.title)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                Text("\(list.count) spots")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.leading, 12)
            .padding(.bottom, 12)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
    }

    // MARK: - Travel Map

    private var travelMapSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Travel Map")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))
                .padding(.horizontal, 20)

            Picker("Map View", selection: $travelMapSegment) {
                Text("Cities").tag(0)
                Text("Countries").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .fill(Color.gray100)
                .frame(height: 230)
                .overlay(
                    Image(systemName: "map")
                        .font(.system(size: 48))
                        .foregroundColor(.gray300)
                )
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(Array(placeholderCities.enumerated()), id: \.offset) { index, city in
                    cityRow(city, isLast: index == placeholderCities.count - 1)
                }
            }
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                    .stroke(Color.gray200, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
            .padding(.horizontal, 20)
        }
    }

    private func cityRow(_ city: CityRowData, isLast: Bool) -> some View {
        HStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.spotsTeal.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: "mappin")
                        .font(.system(size: 13))
                        .foregroundColor(.spotsTeal)
                }
                Text(city.name)
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))
            }
            Spacer()
            Text("\(city.count) spots")
                .font(.system(size: 12))
                .foregroundColor(.gray500)
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().background(Color.gray100)
            }
        }
    }

    // MARK: - Data loading

    private func load() async {
        // Don't toggle isLoadingProfile back on if we already have a cached
        // profile — the header is already rendered, no spinner needed.
        if profile == nil { isLoadingProfile = true }

        // Fan out the lists + city fetches in parallel with profile/rel/counts.
        // They're independent — no reason to wait for Wave 1. Using Task here
        // (not async let) so the handles can outlive this function and the
        // tile-hydration step can await them in a detached follow-up.
        //
        // forceRefresh: false (default) — the 60s caches in ProfileService
        // and FollowService make repeat navigation instant. Mutations
        // (follow / unfollow) invalidate the cache themselves so we don't
        // need to bypass it on every navigation.
        let listsTask = Task { try await LocationSavingService.shared.getUserLists(userId: userId) }
        let cityTask = Task { try await LocationSavingService.shared.getMostExploredCity(userId: userId) }

        do {
            async let profileTask = ProfileService.shared.fetchProfile(userId: userId)
            async let relTask = FollowService.shared.relationship(with: userId)
            async let countsTask = FollowService.shared.counts(userId: userId)

            let loadedProfileOptional = try await profileTask
            let loadedRelationship = try await relTask
            let loadedCounts = try await countsTask

            guard let loadedProfile = loadedProfileOptional else {
                errorMessage = "Profile not found."
                scheduleErrorDismiss()
                isLoadingProfile = false
                listsTask.cancel()
                cityTask.cancel()
                return
            }

            // Header is fully populated now — render and clear the spinner.
            // Tile + cover hydration continue in the background below.
            profile = loadedProfile
            relationship = loadedRelationship
            followersCount = loadedCounts.followers
            followingCount = loadedCounts.following
            isLoadingProfile = false

            let visible = !loadedProfile.isPrivate
                || loadedRelationship == .following
                || loadedRelationship == .mutual
                || loadedRelationship == .isSelf

            if visible {
                // Detached: header is already interactive; tiles fade in when ready.
                Task { await hydrateListsAndCity(listsTask: listsTask, cityTask: cityTask) }
            } else {
                // Private user we can't see — drop the in-flight queries.
                listsTask.cancel()
                cityTask.cancel()
            }

            // Cover photo: also non-blocking. Header art, not critical path.
            Task { await loadCoverImage(profile: loadedProfile) }
        } catch {
            errorMessage = "Couldn't load profile. \(error.localizedDescription)"
            scheduleErrorDismiss()
            isLoadingProfile = false
            listsTask.cancel()
            cityTask.cancel()
        }
    }

    /// Awaits the already-in-flight lists/city tasks fanned out in `load()`,
    /// then runs the tile RPC + spots batch and applies the result. Runs in a
    /// detached Task so the header doesn't wait on tile latency.
    private func hydrateListsAndCity(
        listsTask: Task<[UserList], Error>,
        cityTask: Task<String?, Error>
    ) async {
        do {
            let userLists = try await listsTask.value
            let city = try await cityTask.value
            let (tiles, totalCount) = try await ProfileTileBuilder.buildTiles(from: userLists)

            listTiles = tiles
            spotsCount = totalCount
            mostExploredCity = city
        } catch {
            print("⚠️ UserProfileView: Could not load lists/city: \(error.localizedDescription)")
        }
    }

    private func loadCoverImage(profile: UserProfile) async {
        if let urlString = profile.coverPhotoUrl,
           let image = await UnsplashService.shared.fetchCoverImageFromURL(urlString) {
            await MainActor.run {
                withTransaction(Transaction(animation: nil)) { coverImage = image }
            }
        }
    }

    // MARK: - Actions

    private func tapFollow() async {
        isMutatingFollow = true
        defer { isMutatingFollow = false }
        do {
            let status = try await FollowService.shared.follow(userId: userId)
            relationship = (status == .accepted) ? .following : .requested
            // Refresh counts so the followers stat ticks up immediately on accept.
            if status == .accepted {
                await refreshCounts()
            }
        } catch {
            errorMessage = "Couldn't follow. \(error.localizedDescription)"
            scheduleErrorDismiss()
        }
    }

    private func tapUnfollow() async {
        isMutatingFollow = true
        defer { isMutatingFollow = false }
        do {
            try await FollowService.shared.unfollow(userId: userId)
            relationship = try await FollowService.shared.relationship(with: userId, forceRefresh: true)
            await refreshCounts()
        } catch {
            errorMessage = "Couldn't update follow. \(error.localizedDescription)"
            scheduleErrorDismiss()
        }
    }

    private func refreshCounts() async {
        do {
            let counts = try await FollowService.shared.counts(userId: userId, forceRefresh: true)
            followersCount = counts.followers
            followingCount = counts.following
        } catch {
            // Non-fatal — leave stale counts in place.
        }
    }

    private func scheduleErrorDismiss() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { errorMessage = nil }
        }
    }
}

// MARK: - Inline error toast

private struct ErrorToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            .frame(maxWidth: 320)
    }
}

// MARK: - UIKit-Backed Rounded Background
// Local copy of the same helper used by ProfileView (kept private there).

private struct RoundedTopCornersBackground: UIViewRepresentable {
    let radius: CGFloat

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = radius
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.cornerCurve = .continuous
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        uiView.layer.cornerRadius = radius
        CATransaction.commit()
    }
}
