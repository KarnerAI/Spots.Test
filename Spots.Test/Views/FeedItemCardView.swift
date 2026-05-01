//
//  FeedItemCardView.swift
//  Spots.Test
//
//  Vertical feed card for the Newsfeed tab. Spot-save activities render as a
//  hero card (full-width photo, overlaid title/location, "spotted by" footer
//  with stacked avatars and a Spot button). List-created activities keep the
//  compact preview layout.
//

import SwiftUI

struct FeedItemCardView: View {
    let item: FeedItem
    let actor: UserProfile?
    let spot: Spot?           // nil for list_created events
    let onTapActor: () -> Void
    let onTap: () -> Void
    let onTapSpot: () -> Void

    init(
        item: FeedItem,
        actor: UserProfile?,
        spot: Spot?,
        onTapActor: @escaping () -> Void,
        onTap: @escaping () -> Void,
        onTapSpot: @escaping () -> Void = {}
    ) {
        self.item = item
        self.actor = actor
        self.spot = spot
        self.onTapActor = onTapActor
        self.onTap = onTap
        self.onTapSpot = onTapSpot
    }

    var body: some View {
        switch item.payload {
        case .spotSave(let payload):
            heroCard(payload: payload)
        case .listCreated(let payload):
            compactCard {
                listPreview(payload: payload)
            }
        }
    }

    // MARK: - Hero card (spot save)

    private func heroCard(payload: FeedItemPayload.SpotSavePayload) -> some View {
        VStack(spacing: 0) {
            // Header + photo navigate to the list-detail when tapped. Footer
            // stays untouched so the Spot button's own tap target works
            // without being swallowed by a card-wide gesture.
            header(verb: spotSaveVerb(payload: payload))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture { onTap() }

            heroImage(payload: payload)
                .contentShape(Rectangle())
                .onTapGesture { onTap() }

            // Footer is unconditional: the Spot button is a permanent
            // affordance, regardless of how many other people have saved
            // this spot. Stacked avatars + "Spotted by N others" only render
            // when count > 0.
            Divider()
            spottedByRow(payload: payload)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .background(Color.white)
    }

    // MARK: - Compact card (list created)

    private func compactCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(verb: listCreatedVerb)
            content()
        }
        .padding(16)
        .background(Color.white)
    }

    // MARK: - Header

    private func header(verb: String) -> some View {
        HStack(spacing: 10) {
            Button(action: onTapActor) {
                AvatarView(urlString: actor?.avatarUrl, size: 32)
            }
            .buttonStyle(PlainButtonStyle())

            (
                Text(actor?.displayName ?? "Someone")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray900)
                + Text(" \(verb)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray500)
            )
            .lineLimit(2)

            Spacer(minLength: 8)

            Text(relativeTime)
                .font(.system(size: 12))
                .foregroundColor(.gray400)
        }
    }

    // MARK: - Activity copy

    private func spotSaveVerb(payload: FeedItemPayload.SpotSavePayload) -> String {
        switch payload.listType {
        case .favorites:  return "favorited"
        case .bucketList: return "added to bucket list"
        case .starred:    return "starred"
        case .none:       return "saved to \(payload.listDisplayName)"
        }
    }

    private var listCreatedVerb: String {
        if case .listCreated(let payload) = item.payload {
            return "created a new list: \(payload.listDisplayName)"
        }
        return ""
    }

    private var relativeTime: String {
        Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    // MARK: - Hero image with overlay

    private func heroImage(payload: FeedItemPayload.SpotSavePayload) -> some View {
        // Use Color.gray200 as the sizing container. The 16:10 aspect ratio is
        // enforced on the placeholder color (which has a determinate intrinsic
        // size at any width) rather than on the AsyncImage subtree, where the
        // image's own intrinsic size would otherwise win and produce inconsistent
        // heights across cards.
        Color.gray200
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                spotImage(payload: payload)
                    .scaledToFill()
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 110)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(spot?.name ?? "Saved spot")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)

                        if let subtitle = subtitleLine, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                        }
                    }

                    Spacer(minLength: 0)

                    if let rating = ratingText {
                        HStack(spacing: 4) {
                            Text(rating)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.18))
                        }
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    }
                }
                .padding(16)
            }
            .clipped()
    }

    @ViewBuilder
    private func spotImage(payload: FeedItemPayload.SpotSavePayload) -> some View {
        if let urlString = spot?.photoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    fallbackSpotImage
                @unknown default:
                    fallbackSpotImage
                }
            }
        } else if let ref = spot?.photoReference {
            GooglePlacesImageView(photoReference: ref, maxWidth: 800)
        } else {
            fallbackSpotImage
        }
    }

    private var fallbackSpotImage: some View {
        Rectangle()
            .fill(Color.gray200)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundColor(.gray400)
            )
    }

    // MARK: - Hero subtitle / rating

    private var subtitleLine: String? {
        var parts: [String] = []
        if let city = spot?.city, !city.isEmpty {
            parts.append(city)
        }
        if let country = spot?.country, !country.isEmpty {
            parts.append(country)
        }
        if let category = humanizedCategory {
            parts.append(category)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var humanizedCategory: String? {
        guard let raw = spot?.types?.first(where: { $0 != "point_of_interest" && $0 != "establishment" }) else {
            return nil
        }
        return raw
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var ratingText: String? {
        guard let rating = spot?.rating, rating > 0 else { return nil }
        return String(format: "%.1f", rating)
    }

    // MARK: - Spotted-by footer

    private func spottedByRow(payload: FeedItemPayload.SpotSavePayload) -> some View {
        HStack(spacing: 10) {
            // Stacked avatars + label only render when there's actually a
            // co-saver count to surface. The Spot button below stays
            // unconditional so the affordance is always available.
            if payload.otherSaversCount > 0 || !payload.otherSavers.isEmpty {
                stackedAvatars(savers: payload.otherSavers)

                Text(spottedByLabel(count: payload.otherSaversCount))
                    .font(.system(size: 13))
                    .foregroundColor(.gray600)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onTapSpot) {
                Text("Spot")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color.spotsTeal)
                    .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func stackedAvatars(savers: [FeedItemPayload.OtherSaver]) -> some View {
        let visible = Array(savers.prefix(3))
        return HStack(spacing: -10) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, saver in
                AvatarView(urlString: saver.avatarUrl, size: 28)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
        }
    }

    private func spottedByLabel(count: Int) -> String {
        if count <= 0 { return "Spotted by others" }
        if count == 1 { return "Spotted by 1 other" }
        return "Spotted by \(count) others"
    }

    // MARK: - List preview (unchanged compact layout)

    private func listPreview(payload: FeedItemPayload.ListCreatedPayload) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
                        .fill(Color.spotsTeal.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.spotsTeal)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(payload.listDisplayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.gray900)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("New list")
                        .font(.system(size: 12))
                        .foregroundColor(.gray500)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray400)
            }
            .padding(12)
            .background(Color.gray100)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }
}
