//
//  FeedItemCardView.swift
//  Spots.Test
//
//  Vertical feed card for the Newsfeed tab. Renders the actor header,
//  a relative timestamp, the activity verb, and an embedded preview of
//  the spot or list referenced by the activity.
//

import SwiftUI

struct FeedItemCardView: View {
    let item: FeedItem
    let actor: UserProfile?
    let spot: Spot?           // nil for list_created events
    let onTapActor: () -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onTapActor) {
                avatar
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: 2) {
                Button(action: onTapActor) {
                    Text(actor?.displayName ?? "Someone")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.gray900)
                }
                .buttonStyle(PlainButtonStyle())

                Text(activityVerb)
                    .font(.system(size: 13))
                    .foregroundColor(.gray500)
                    .lineLimit(2)
            }

            Spacer()

            Text(relativeTime)
                .font(.system(size: 12))
                .foregroundColor(.gray400)
        }
    }

    private var avatar: some View {
        Group {
            if let urlString = actor?.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        avatarPlaceholder
                    @unknown default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.gray200)
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundColor(.gray400)
            )
    }

    // MARK: - Activity copy

    private var activityVerb: String {
        switch item.payload {
        case .spotSave(let p):
            return "saved a spot to \(p.listDisplayName)"
        case .listCreated(let p):
            return "created a new list: \(p.listDisplayName)"
        }
    }

    private var relativeTime: String {
        Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    // MARK: - Body content per kind

    @ViewBuilder
    private var content: some View {
        switch item.payload {
        case .spotSave(let payload):
            spotPreview(payload: payload)
        case .listCreated(let payload):
            listPreview(payload: payload)
        }
    }

    // MARK: - Spot preview

    private func spotPreview(payload: FeedItemPayload.SpotSavePayload) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                spotImage(payload: payload)
                    .frame(width: 80, height: 80)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(spot?.name ?? "Saved spot")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.gray900)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let address = spot?.address, !address.isEmpty {
                        Text(address)
                            .font(.system(size: 12))
                            .foregroundColor(.gray500)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if let listType = payload.listType {
                        HStack(spacing: 4) {
                            ListIconView(listType: listType)
                                .font(.system(size: 11))
                            Text(listType.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray600)
                        }
                        .padding(.top, 2)
                    }
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
            GooglePlacesImageView(photoReference: ref, maxWidth: 200)
        } else {
            fallbackSpotImage
        }
    }

    private var fallbackSpotImage: some View {
        Rectangle()
            .fill(Color.gray200)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(.gray400)
            )
    }

    // MARK: - List preview

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
