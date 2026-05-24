//
//  CuratedSpotCard.swift
//  Spots.Test
//
//  Image-led card surfaced on onboarding screens 2 (bucket list) and
//  3 (favorites).
//
//  Layout (2026-05-12 update — moved save toggle off the photo):
//   ┌─────────────────────┐
//   │                     │
//   │      PHOTO          │  top 60%, full-bleed, no overlays
//   │                     │
//   ├─────────────────────┤
//   │ Name           [🔖] │  bottom 40%, HStack
//   │ City                │
//   └─────────────────────┘
//
//  The save toggle previously overlaid the top-right of the photo;
//  it obscured key brand content (e.g. the Joe's Pizza neon sign)
//  and was relocated into the text band. Tap target stays 44×44 to
//  meet the WCAG touch-target minimum.
//
//  Visual spec lives in the plan's "Design Specifications →
//  CuratedSpotCard spec" section. Token bindings (radii, colors,
//  type sizes) are pulled from the existing Color extension and
//  CornerRadius helper so the cards feel native to the rest of
//  the app.
//
//  Save tap behavior:
//   - Haptic (.light) + scale pulse 1.0 → 1.05 → 1.0 over ~200ms
//   - Reduce Motion: replace pulse with a brief color-shift flash
//   - On failure the parent VM reverts isSelected and shows a toast
//

import SwiftUI

struct CuratedSpotCard: View {
    /// The DB-backed spot row. `spot.placeId` is the join key.
    let spot: Spot
    /// Which list this card writes to when tapped. Screen 2 passes
    /// `.wantToGo` (emerald flag); screen 3 passes `.favorites` (red heart).
    let category: ListKind
    /// True when the spot is currently in the user's `category` list.
    let isSelected: Bool
    /// Tap action. Awaits the VM toggle so the parent can manage
    /// optimistic flip + revert-on-failure.
    let onToggle: () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1.0

    private static let cornerRadius: CGFloat = CornerRadius.card
    private static let aspectRatio: CGFloat = 4.0 / 5.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            photoSection
            textSection
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .stroke(Color.gray100, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .scaleEffect(scale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityHint(voiceOverHint)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Photo

    /// Full-bleed photo, unobstructed. The save toggle lives in the
    /// text band below (see `textSection`) rather than overlaying the
    /// image — moving it off the photo gives spots like Joe's Pizza
    /// (where the brand identity IS the photo) their full canvas.
    private var photoSection: some View {
        GeometryReader { geo in
            Group {
                if let url = spot.photoUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            placeholderTile
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .transition(.opacity.animation(.easeOut(duration: 0.2)))
                        case .failure:
                            placeholderTile
                        @unknown default:
                            placeholderTile
                        }
                    }
                } else {
                    placeholderTile
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .aspectRatio(1.0 / Self.aspectRatio, contentMode: .fit)
    }

    private var placeholderTile: some View {
        ZStack {
            Color.gray100
            Image(systemName: "photo")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.gray300)
        }
    }

    // MARK: - Save button

    private var saveButtonWrapper: some View {
        // The existing SaveSpotButton encodes the icon+state mapping
        // (heart for starred, flag for bucketList). We wrap it in a
        // 44×44 hit target via contentShape + an enlarged tap region.
        Button(action: handleTap) {
            SaveSpotButton(
                placeId: spot.placeId,
                kind: isSelected ? category : nil,
                hasLoadedSavedPlaces: true,
                onTap: {} // owning Button intercepts the tap
            )
            .allowsHitTesting(false) // pass-through so our Button owns the gesture
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func handleTap() {
        // Haptic first — instant tactile confirmation.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Visual pulse, unless Reduce Motion is on.
        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.1)) {
                scale = 1.05
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeIn(duration: 0.1)) {
                    scale = 1.0
                }
            }
        }

        Task { await onToggle() }
    }

    // MARK: - Text + save toggle

    /// Bottom band of the card: name + city on the left, save button on
    /// the right. HStack with `.center` alignment keeps the icon
    /// vertically centered against the two-line text stack regardless
    /// of whether the name wraps to one or two lines.
    private var textSection: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.gray900)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(displayCity)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray500)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            saveButtonWrapper
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Display city for the card. Reads `Spot.displayCity`, which prefers the
    /// real locality ("Paris") and falls back to the misnamed `city` (region)
    /// for pre-backfill rows. The earlier `CuratedSpot.displayCity` workaround
    /// is no longer needed now that the schema has a true locality column.
    private var displayCity: String {
        spot.displayCity ?? ""
    }

    // MARK: - Accessibility

    private var voiceOverLabel: String {
        "\(spot.name), \(displayCity)"
    }

    private var voiceOverHint: String {
        if isSelected {
            return "Saved to \(category.displayName). Tap to remove."
        } else {
            return "Tap to save to \(category.displayName)."
        }
    }
}

#Preview("Bucket — unsaved") {
    let preview = Spot(
        placeId: "ChIJLU7jZClu5kcR4PcOOO6p3I0",
        name: "Eiffel Tower",
        city: "Île-de-France",
        photoUrl: "https://images.unsplash.com/photo-1499856871958-5b9627545d1a"
    )
    return CuratedSpotCard(
        spot: preview,
        category: .wantToGo,
        isSelected: false,
        onToggle: {}
    )
    .frame(width: 160)
    .padding()
    .background(Color.gray50)
}

#Preview("Favorites — saved") {
    let preview = Spot(
        placeId: "ChIJ8Q2WSpJZwokRQz-bYYgEskM",
        name: "Joe's Pizza",
        city: "New York",
        photoUrl: "https://images.unsplash.com/photo-1593504049359-74330189a345"
    )
    return CuratedSpotCard(
        spot: preview,
        category: .favorites,
        isSelected: true,
        onToggle: {}
    )
    .frame(width: 160)
    .padding()
    .background(Color.gray50)
}
