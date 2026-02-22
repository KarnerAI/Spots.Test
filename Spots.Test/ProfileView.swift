//
//  ProfileView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI
import UIKit

// MARK: - Supporting Types

private struct ListTileData {
    let title: String
    let count: Int
    let fallbackColor: Color
    let coverImageUrl: String?
    let coverPhotoReference: String?
}

private struct CityRowData {
    let name: String
    let count: Int
}

// MARK: - Profile View

struct ProfileView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @State private var travelMapSegment: Int = 0
    @State private var spotsCount: Int = 0
    @State private var mostExploredCity: String?
    @State private var coverImage: UIImage?
    @State private var listTiles: [ListTileData] = []

    private let coverHeight: CGFloat = 260
    private let cardOverlap: CGFloat = 30
    private let photoSize: CGFloat = 96

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
        .onAppear { loadProfileData() }
    }

    private func loadProfileData() {
        // Load list tiles concurrently with other profile data
        Task { await loadListTiles() }

        Task {
            // Spots count
            do {
                let count = try await LocationSavingService.shared.getUniqueSpotCountInStarredAndFavorites()
                await MainActor.run { spotsCount = count }
            } catch {
                await MainActor.run { spotsCount = 0 }
            }

            // Most explored city + cover photo
            do {
                let city = try await LocationSavingService.shared.getMostExploredCity()
                await MainActor.run { mostExploredCity = city }

                if let city {
                    let image = await UnsplashService.shared.fetchCoverImage(for: city)
                    await MainActor.run { coverImage = image }
                }
            } catch {
                // Non-fatal: city label stays as placeholder, cover stays as gradient
                print("⚠️ ProfileView: Could not load most explored city: \(error.localizedDescription)")
            }
        }
    }

    private func loadListTiles() async {
        do {
            try await LocationSavingService.shared.ensureDefaultListsForCurrentUser()
            let userLists = try await LocationSavingService.shared.getUserLists()

            let listConfigs: [(type: ListType, title: String, color: Color)] = [
                (.starred,    "Starred",     Color(red: 0.60, green: 0.50, blue: 0.30)),
                (.favorites,  "Favorites",   Color(red: 0.55, green: 0.30, blue: 0.30)),
                (.bucketList, "Bucket List", Color(red: 0.28, green: 0.45, blue: 0.60)),
            ]

            var systemTiles: [ListTileData] = []
            var totalCount = 0
            var allListIds: [UUID] = []

            for config in listConfigs {
                guard let list = userLists.first(where: { $0.listType == config.type }) else {
                    systemTiles.append(ListTileData(
                        title: config.title, count: 0,
                        fallbackColor: config.color,
                        coverImageUrl: nil, coverPhotoReference: nil
                    ))
                    continue
                }

                allListIds.append(list.id)

                // Fetch count and cover spot for this list concurrently
                async let count = LocationSavingService.shared.getSpotCount(listId: list.id)
                async let recentSpot = LocationSavingService.shared.getMostRecentSpotInList(listId: list.id)
                let (resolvedCount, resolvedSpot) = try await (count, recentSpot)
                totalCount += resolvedCount

                systemTiles.append(ListTileData(
                    title: config.title,
                    count: resolvedCount,
                    fallbackColor: config.color,
                    coverImageUrl: resolvedSpot?.photoUrl,
                    coverPhotoReference: resolvedSpot?.photoReference
                ))
            }

            // All Spots: cover from most recently saved spot across all lists
            let allSpotsSpot = try await LocationSavingService.shared.getMostRecentSpotAcrossLists(listIds: allListIds)
            let allSpotsTile = ListTileData(
                title: "All Spots",
                count: totalCount,
                fallbackColor: Color.gray400,
                coverImageUrl: allSpotsSpot?.photoUrl,
                coverPhotoReference: allSpotsSpot?.photoReference
            )

            let tiles = [allSpotsTile] + systemTiles
            await MainActor.run { listTiles = tiles }
        } catch {
            print("⚠️ ProfileView: Could not load list tiles: \(error.localizedDescription)")
        }
    }

    // MARK: - Cover Section

    private var coverSection: some View {
        ZStack(alignment: .topTrailing) {
            // Cover image: Unsplash city photo or gradient placeholder
            if let image = coverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: coverHeight)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color.gray400, Color.gray600],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: coverHeight)
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
                    AsyncImage(url: url) { phase in
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
                .padding(.top, 20)

            myListsSection
                .padding(.top, 24)

            travelMapSection
                .padding(.top, 28)

            // Bottom padding so content clears the tab bar
            Spacer()
                .frame(height: 100)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedCornerShape(radius: 30, corners: [.topLeft, .topRight]))
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
            statItem(value: "\(spotsCount)", label: "Spots")
            statItem(value: "0", label: "Followers")
            statItem(value: "0", label: "Following")
        }
        .padding(.vertical, 16)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16))
                .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))

            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.gray500)
        }
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
                    ForEach(listTiles, id: \.title) { list in
                        listCard(list)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func listCard(_ list: ListTileData) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Background: Supabase photo URL → Google photo reference → solid color
            if let urlString = list.coverImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(list.fallbackColor)
                    }
                }
                .frame(width: 140, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if let ref = list.coverPhotoReference {
                GooglePlacesImageView(photoReference: ref, maxWidth: 280)
                    .frame(width: 140, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(list.fallbackColor)
                    .frame(width: 140, height: 150)
            }

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.gray200, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

// MARK: - Custom Corner Shape

private struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview

#Preview {
    ProfileView().environmentObject(AuthenticationViewModel())
}
