//
//  ProfileView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI
import UIKit

// MARK: - Profile View
// Supporting types ListTileData / CityRowData live in Helpers/ProfileSupportTypes.swift
// (shared with UserProfileView so both screens render the same tile UI).


struct ProfileView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @State private var travelMapSegment: Int = 0
    @State private var spotsCount: Int = 0
    @State private var followersCount: Int = 0
    @State private var followingCount: Int = 0
    @State private var mostExploredCity: String?
    @State private var coverImage: UIImage?
    @State private var listTiles: [ListTileData] = []
    @State private var showCoverPicker = false
    @State private var showErrorToast = false
    @State private var errorToastMessage = ""

    private let coverHeight: CGFloat = 260
    private let cardOverlap: CGFloat = 30
    private let photoSize: CGFloat = 96
    /// Top corner radius of the white content sheet; must match Explore bottom sheet and List Picker (CornerRadius.sheet).
    private let sheetTopCornerRadius: CGFloat = CornerRadius.sheet

    private var photoOffset: CGFloat {
        coverHeight - cardOverlap - photoSize / 2
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
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { loadProfileData() }
        .sheet(isPresented: $showCoverPicker) {
            if let city = mostExploredCity, let userId = viewModel.currentUserId {
                CoverPhotoPickerView(city: city, userId: userId) { selectedURL in
                    Task {
                        let image = await UnsplashService.shared.fetchCoverImageFromURL(selectedURL)
                        await MainActor.run {
                            withTransaction(Transaction(animation: nil)) { coverImage = image }
                        }
                        saveSnapshotToCache()
                    }
                }
                .environmentObject(viewModel)
            }
        }
        .overlay(alignment: .bottom) {
            if showErrorToast {
                Text(errorToastMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 16)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { showErrorToast = false }
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func loadProfileData() {
        guard let userId = viewModel.currentUserId else { return }

        let cache = ProfileSnapshotCache.shared

        // Apply cached snapshot instantly (synchronous, before any async work)
        if let snapshot = cache.snapshot(for: userId) {
            spotsCount = snapshot.spotsCount
            followersCount = snapshot.followersCount
            followingCount = snapshot.followingCount
            mostExploredCity = snapshot.mostExploredCity
            listTiles = snapshot.listTiles.map { ListTileData(cached: $0) }
            loadCoverImage()

            if !cache.isStale { return }
        }

        // Full network refresh (first visit or stale cache)
        Task { await refreshListTilesFromNetwork() }
        Task { await refreshCityAndCover() }
        Task { await refreshFollowCounts(userId: userId) }
    }

    private func refreshFollowCounts(userId: UUID) async {
        do {
            let counts = try await FollowService.shared.counts(userId: userId, forceRefresh: true)
            await MainActor.run {
                withTransaction(Transaction(animation: nil)) {
                    followersCount = counts.followers
                    followingCount = counts.following
                }
            }
            saveSnapshotToCache()
        } catch {
            print("⚠️ ProfileView: Could not load follow counts: \(error.localizedDescription)")
        }
    }

    // MARK: - Cover Image

    private func loadCoverImage() {
        Task {
            if let persistedURL = viewModel.currentUserCoverPhotoUrl {
                let image = await UnsplashService.shared.fetchCoverImageFromURL(persistedURL)
                await MainActor.run {
                    withTransaction(Transaction(animation: nil)) { coverImage = image }
                }
            } else if let city = mostExploredCity {
                let image = await UnsplashService.shared.fetchCoverImage(for: city)
                await MainActor.run {
                    withTransaction(Transaction(animation: nil)) { coverImage = image }
                }
            }
        }
    }

    // MARK: - Network Refresh

    private func refreshCityAndCover() async {
        do {
            let city = try await LocationSavingService.shared.getMostExploredCity()
            await MainActor.run {
                withTransaction(Transaction(animation: nil)) { mostExploredCity = city }
            }

            if let persistedURL = viewModel.currentUserCoverPhotoUrl {
                let image = await UnsplashService.shared.fetchCoverImageFromURL(persistedURL)
                await MainActor.run {
                    withTransaction(Transaction(animation: nil)) { coverImage = image }
                }
            } else if let city {
                let image = await UnsplashService.shared.fetchCoverImage(for: city)
                await MainActor.run {
                    withTransaction(Transaction(animation: nil)) { coverImage = image }
                }
            }

            saveSnapshotToCache()
        } catch {
            print("⚠️ ProfileView: Could not load most explored city: \(error.localizedDescription)")
            await MainActor.run {
                errorToastMessage = "Could not load city data"
                showErrorToast = true
            }
        }
    }

    private func refreshListTilesFromNetwork() async {
        do {
            try await LocationSavingService.shared.ensureDefaultListsForCurrentUser()
            let userLists = try await LocationSavingService.shared.getUserLists()
            let (tiles, totalCount) = try await ProfileTileBuilder.buildTiles(from: userLists)

            await MainActor.run {
                withTransaction(Transaction(animation: nil)) {
                    listTiles = tiles
                    spotsCount = totalCount
                }
            }

            saveSnapshotToCache()
        } catch {
            print("⚠️ ProfileView: Could not load list tiles: \(error.localizedDescription)")
            await MainActor.run {
                errorToastMessage = "Could not load some profile data"
                showErrorToast = true
            }
        }
    }

    // MARK: - Snapshot Persistence

    private func saveSnapshotToCache() {
        guard let userId = viewModel.currentUserId else { return }
        let snapshot = ProfileSnapshot(
            userId: userId.uuidString,
            spotsCount: spotsCount,
            followersCount: followersCount,
            followingCount: followingCount,
            mostExploredCity: mostExploredCity,
            listTiles: listTiles.map { $0.toCached() },
            savedAt: Date()
        )
        ProfileSnapshotCache.shared.save(snapshot)
    }

    // MARK: - Cover Section

    private var coverSection: some View {
        coverContent
            .contentShape(Rectangle())
            .onTapGesture {
                guard mostExploredCity != nil else { return }
                showCoverPicker = true
            }
    }

    private var coverContent: some View {
        ZStack(alignment: .topTrailing) {
            // Gradient is always present — acts as placeholder and loading state.
            // Keeping it in the tree permanently means SwiftUI never inserts/removes
            // its primary sizing child, so the ZStack's layout stays stable.
            LinearGradient(
                colors: [Color.gray400, Color.gray600],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: coverHeight)

            // Image overlays gradient when loaded — no if/else branch switch,
            // no view-type change, no layout recomputation in the parent ZStack.
            if let image = coverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: coverHeight)
                    .clipped()
            }

            // Dark gradient overlay to ensure text/UI legibility
            LinearGradient(
                colors: [Color.black.opacity(0.2), Color.black.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: coverHeight)

            // Settings button
            NavigationLink(destination: SettingsView()) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 40, height: 40)
                        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)

                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.gray700)
                }
            }
            .padding(.top, 56)
            .padding(.trailing, 16)
        }
        // Pin the ZStack to exactly coverHeight so its reported size never
        // changes when children are added/removed. Clip prevents any
        // .scaledToFill() overflow from leaking into the overlap zone.
        .frame(height: coverHeight)
        .clipped()
        .transaction { $0.animation = nil }
    }

    // MARK: - Profile Photo

    private var profilePhoto: some View {
        NavigationLink(destination: EditProfileView()) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: photoSize + 6, height: photoSize + 6)
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)

                if let urlString = viewModel.currentUserAvatarUrl, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            placeholderAvatar
                        }
                    }
                    .frame(width: photoSize, height: photoSize)
                    .clipShape(Circle())
                } else {
                    placeholderAvatar
                        .frame(width: photoSize, height: photoSize)
                        .clipShape(Circle())
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.gray200)
            Image(systemName: "person.fill")
                .font(.system(size: 44))
                .foregroundColor(.gray400)
        }
    }

    // MARK: - White Card

    private var whiteCard: some View {
        VStack(alignment: .center, spacing: 0) {
            // Space for profile photo overlap
            Spacer()
                .frame(height: photoSize / 2 + 16)

            profileInfoSection

            statsSection
                .padding(.top, 12)

            Divider()
                .background(Color.gray200)
                .padding(.horizontal, 20)

            myListsSection
                .padding(.top, 20)

            travelMapSection
                .padding(.top, 28)

            // Bottom padding so content clears the tab bar
            Spacer()
                .frame(height: 100)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedTopCornersBackground(radius: sheetTopCornerRadius))
        .transaction { $0.animation = nil }
    }

    // MARK: - Profile Info

    private var profileInfoSection: some View {
        let displayName = "\(viewModel.currentUserFirstName) \(viewModel.currentUserLastName)".trimmingCharacters(in: .whitespaces)
        let nameText = displayName.isEmpty ? "First Name Last Name" : displayName
        return VStack(spacing: 4) {
            Text(nameText)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))
                .multilineTextAlignment(.center)

            Text("@\(viewModel.currentUserUsername)")
                .font(.system(size: 14))
                .foregroundColor(.gray500)

            HStack(spacing: 4) {
                Text("Most Explored:")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.29, green: 0.34, blue: 0.42))

                Text(mostExploredCity ?? "—")
                    .font(.system(size: 14))
                    .foregroundColor(.spotsTeal)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Stats Row

    private var statsSection: some View {
        HStack(spacing: 32) {
            statItem(value: "\(spotsCount)", label: "Spots") {
                ListDetailView(title: "All Spots", mode: .allSpots)
            }
            statItem(value: "\(followersCount)", label: "Followers") {
                if let userId = viewModel.currentUserId {
                    FollowersFollowingView(
                        userId: userId,
                        initialTab: .followers,
                        username: viewModel.currentUserUsername
                    )
                }
            }
            statItem(value: "\(followingCount)", label: "Following") {
                if let userId = viewModel.currentUserId {
                    FollowersFollowingView(
                        userId: userId,
                        initialTab: .following,
                        username: viewModel.currentUserUsername
                    )
                }
            }
        }
        .padding(.vertical, 16)
    }

    private func statItem<Destination: View>(
        value: String,
        label: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
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
        .buttonStyle(.plain)
    }

    // MARK: - My Lists

    private var myListsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("My Lists")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))

                Spacer()

                Button("View all") {}
                    .font(.system(size: 14))
                    .foregroundColor(.spotsTeal)
            }
            .padding(.horizontal, 20)

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

    @ViewBuilder
    private func destinationView(for tile: ListTileData) -> some View {
        if tile.isAllSpots {
            ListDetailView(title: tile.title, mode: .allSpots)
        } else if let list = tile.userList {
            ListDetailView(title: tile.title, mode: .singleList(list))
        }
    }

    private func listCard(_ list: ListTileData) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Background: Supabase photo URL → Google photo reference → solid color
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
            Text("Your Travel Map")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))
                .padding(.horizontal, 20)

            Picker("Map View", selection: $travelMapSegment) {
                Text("Cities").tag(0)
                Text("Countries").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            // World map placeholder
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .fill(Color.gray100)
                .frame(height: 230)
                .overlay(
                    Image(systemName: "map")
                        .font(.system(size: 48))
                        .foregroundColor(.gray300)
                )
                .padding(.horizontal, 20)

            // City list
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
                Divider()
                    .background(Color.gray100)
            }
        }
    }
}

// MARK: - UIKit-Backed Rounded Background

/// Uses `CALayer.cornerRadius` instead of SwiftUI shapes to avoid animation
/// artifacts from NavigationStack insertion transitions.
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

// MARK: - Preview

#Preview {
    ProfileView().environmentObject(AuthenticationViewModel())
}
