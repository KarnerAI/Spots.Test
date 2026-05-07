//
//  SpottedByView.swift
//  Spots.Test
//
//  Modal sheet listing every user who has saved a given place to a public list.
//  Opens from a feed card's stacked-avatars / "Spotted by N others" tap targets.
//

import SwiftUI

struct SpottedByView: View {
    let spot: Spot

    @Environment(\.dismiss) private var dismiss

    @State private var spotters: [Spotter] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var profileToOpen: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                sortRow
                Divider()
                content
            }
            .background(Color.white)
            .navigationDestination(item: $profileToOpen) { userId in
                UserProfileView(userId: userId)
            }
            .task { await load() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("Spotted By")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.gray900)
                Spacer(minLength: 8)
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.gray700)
                        .frame(width: 32, height: 32)
                        .background(Color.gray100)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Text(spot.name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.gray900)
                .lineLimit(2)

            if let subtitle = subtitleLine, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.gray500)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var subtitleLine: String? {
        var parts: [String] = []
        if let city = spot.city, !city.isEmpty { parts.append(city) }
        if let country = spot.country, !country.isEmpty { parts.append(country) }
        if let category = humanizedCategory { parts.append(category) }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var humanizedCategory: String? {
        guard let raw = spot.types?.first(where: { $0 != "point_of_interest" && $0 != "establishment" }) else {
            return nil
        }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Sort row

    private var sortRow: some View {
        Menu {
            // Single option for v1 — surface is in place to add Alphabetical /
            // Mutuals later without restructuring the UI.
            Button {
                // no-op: only Recent is supported today
            } label: {
                Label("Recent", systemImage: "checkmark")
            }
        } label: {
            HStack(spacing: 6) {
                Text("Sort by")
                    .font(.system(size: 14))
                    .foregroundColor(.gray500)
                Text("Recent")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray900)
                Spacer()
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray500)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && spotters.isEmpty {
            VStack {
                ProgressView()
                    .padding(.top, 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if let message = loadError, spotters.isEmpty {
            errorState(message: message)
        } else if spotters.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Text(countLabel)
                        .font(.system(size: 13))
                        .foregroundColor(.gray500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 8)

                    ForEach(spotters) { spotter in
                        Button {
                            profileToOpen = spotter.userId
                        } label: {
                            spotterRow(spotter)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var countLabel: String {
        spotters.count == 1
            ? "1 person spotted this"
            : "\(spotters.count) people spotted this"
    }

    private func spotterRow(_ spotter: Spotter) -> some View {
        HStack(spacing: 12) {
            AvatarView(urlString: spotter.avatarUrl, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(spotter.username)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.gray900)
                    .lineLimit(1)
                Text(spotter.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(.gray500)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 36))
                .foregroundColor(.gray400)
            Text("No one else has spotted this yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.gray500)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 48)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.gray400)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.gray600)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await load() }
            } label: {
                Text("Try again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.spotsTeal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 48)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let rows = try await LocationSavingService.shared.fetchSpotters(spotId: spot.placeId)
            spotters = rows
        } catch {
            loadError = "Couldn't load spotters. \(error.localizedDescription)"
        }
        isLoading = false
    }
}
