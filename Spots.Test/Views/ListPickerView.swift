//
//  ListPickerView.swift
//  Spots.Test
//
//  Save-to-list sheet. Renders inside a native .sheet via ListPickerSheetModifier.
//  Shows all of the user's lists (system + custom), keyed by UUID. Multi-select
//  with checkmark; pre-seeded with the lists the spot is already in. Save diff
//  is delegated to LocationSavingViewModel.saveSpotToLists.
//

import SwiftUI
import UIKit

struct ListPickerView: View {
    let spotData: PlaceAutocompleteResult
    @ObservedObject var viewModel: LocationSavingViewModel
    var onDismiss: () -> Void
    var onSaveComplete: (() -> Void)? = nil

    @State private var selectedListIds: Set<UUID> = []
    @State private var listCounts: [UUID: Int] = [:]
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Bumped each time the user toggles the elite love tier (`.starred` /
    /// "Favorites") ON via `toggle(_:)`. Bound to `.symbolEffect(.bounce, value:)`
    /// on the Favorites row's heart icon so only user-initiated additions fire
    /// the celebration — initial pre-selection from existing membership and
    /// toggle-OFF do not animate.
    @State private var favoritesBouncePulse: Int = 0
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            // Place-context strip: thumbnail + name + subtitle for the spot
            // being saved. Mirrors Instagram's bookmark sheet — shows users
            // exactly what they're filing away before they choose where.
            placeContextRow
            Divider()

            if isLoading && viewModel.userLists.isEmpty {
                loadingState
            } else {
                listContent
            }

            if let errorMessage {
                errorBanner(errorMessage)
            }

            saveBar
        }
        .background(Color.white)
        .task { await loadInitialData() }
    }

    // MARK: - Header

    private var header: some View {
        Text("Save to lists")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.gray900)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
    }

    // MARK: - Place context (Iteration 3 — Variant B)
    //
    // Shows a 56pt square thumbnail of the spot being saved + its name and
    // a city/category subtitle, in a tinted gray strip directly above the
    // list-of-destinations. Image loading mirrors FeedItemCardView.spotImage:
    //   1. photoUrl (Supabase-cached) — fastest, hits process-wide image cache
    //   2. photoReference (Google Places) — falls back to Google fetch +
    //      shared SpotImageCache; reuses 1200px cache from feed cards so a
    //      spot already viewed elsewhere has zero extra network cost.
    //   3. neither → gray placeholder with photo glyph (no layout collapse).

    private var placeContextRow: some View {
        HStack(spacing: 12) {
            placeThumbnail
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(spotData.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.gray900)
                    .lineLimit(2)
                    .truncationMode(.tail)

                if let subtitle = placeSubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.gray500)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 80)
        // No background tint — Apple's Share Sheet pattern. The dividers above
        // (from the header section) and below (in `body`) carry the visual
        // separation. iter-3.1 dropped the gray100 background after it read
        // as "form input field" against a live map view in TestFlight.
    }

    @ViewBuilder
    private var placeThumbnail: some View {
        if let urlString = spotData.photoUrl, let url = URL(string: urlString) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    placeThumbnailFallback
                @unknown default:
                    placeThumbnailFallback
                }
            }
        } else if let ref = spotData.photoReference {
            // Reuse the same 1200px cache key as feed cards so we don't pay
            // a second Google fetch for places already seen elsewhere. The
            // 56pt display just downsamples.
            GooglePlacesImageView(photoReference: ref, maxWidth: PhotoQuality.maxWidthPx)
        } else {
            placeThumbnailFallback
        }
    }

    private var placeThumbnailFallback: some View {
        Rectangle()
            .fill(Color.gray200)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(.gray400)
            )
    }

    /// City and humanized category, joined by " · ". Mirrors the pattern in
    /// FeedItemCardView.subtitleLine, scoped to the fields available on
    /// PlaceAutocompleteResult (no country, no rating).
    private var placeSubtitle: String? {
        var parts: [String] = []
        if let city = spotData.city, !city.isEmpty {
            parts.append(city)
        }
        if let category = humanizedCategory {
            parts.append(category)
        }
        // If we have neither, fall back to the address so users always see
        // SOMETHING below the place name — empty subtitle reads as a bug.
        if parts.isEmpty, !spotData.address.isEmpty {
            parts.append(spotData.address)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// First non-generic Google Places type, capitalized and underscores
    /// replaced with spaces. Skips "point_of_interest" and "establishment"
    /// since those are uninformative wrappers Google attaches to almost
    /// every result.
    private var humanizedCategory: String? {
        guard let raw = spotData.types?.first(where: {
            $0 != "point_of_interest" && $0 != "establishment"
        }) else {
            return nil
        }
        return raw
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    // MARK: - List rows

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.userLists) { list in
                    listRow(list)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func listRow(_ list: UserList) -> some View {
        let isSelected = selectedListIds.contains(list.id)
        let count = listCounts[list.id] ?? 0
        let isFavorites = list.listType == .starred  // .starred enum case = "Favorites" display label

        return HStack(spacing: 12) {
            Image(systemName: list.listType?.iconName ?? "list.bullet")
                .foregroundColor(list.listType?.iconColor ?? Color.spotsTeal)
                .frame(width: 20, height: 20)
                // Bind the bounce only to the Favorites row so unrelated
                // toggles don't animate it. `favoritesBouncePulse` only ever
                // increments from `toggle(_:)` on a user-initiated add.
                .symbolEffect(.bounce, value: isFavorites ? favoritesBouncePulse : 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.displayName)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.gray900)
                Text("Private list · \(count) \(count == 1 ? "place" : "places")")
                    .font(.system(size: 12))
                    .foregroundColor(.gray500)
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(isSelected ? Color.clear : Color.gray300, lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isSelected ? Color.spotsTeal : Color.clear))
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { toggle(list.id) }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: { Task { await handleSave() } }) {
                Text(isSaving ? "Saving" : "Save")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(SaveToListTealButtonStyle())
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .disabled(isSaving)
            .opacity(isSaving ? 0.6 : 1.0)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.red)
                .multilineTextAlignment(.leading)
            Spacer()
            Button { errorMessage = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray400)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.1))
    }

    // MARK: - Actions

    private func toggle(_ id: UUID) {
        if selectedListIds.contains(id) {
            selectedListIds.remove(id)
        } else {
            // Radio behavior across the three default lists: selecting one
            // (Favorites / Liked / Want to Go) deselects the other two.
            // User-created lists keep checkbox semantics. Enforces the
            // "one default list per spot" invariant at the UI layer; the
            // VM also coerces in saveSpotToLists as belt-and-suspenders.
            let toggledList = viewModel.userLists.first(where: { $0.id == id })
            if toggledList?.listType != nil {
                let otherDefaultIds = viewModel.userLists
                    .filter { $0.listType != nil && $0.id != id }
                    .map(\.id)
                for otherId in otherDefaultIds {
                    selectedListIds.remove(otherId)
                }
            }

            selectedListIds.insert(id)
            // Favorites is the elite tier — celebrate user adds with a bounce
            // + light haptic. Fires only here (user toggle-on), never on
            // initial pre-selection from existing membership or on remove.
            // The .starred enum case maps to the "Favorites" display label.
            if toggledList?.listType == .starred {
                favoritesBouncePulse &+= 1
                lightHaptic.impactOccurred()
            }
        }
    }

    private func loadInitialData() async {
        isLoading = true
        await viewModel.loadUserLists()
        let ids = viewModel.userLists.map(\.id)

        async let countsTask: [UUID: Int] = viewModel.getSpotCounts(listIds: ids)
        let existing: [UUID]
        do {
            existing = try await viewModel.getListsContainingSpot(placeId: spotData.placeId)
        } catch {
            existing = []
        }

        listCounts = await countsTask
        selectedListIds = Set(existing)
        isLoading = false
    }

    private func handleSave() async {
        isSaving = true
        errorMessage = nil
        do {
            try await viewModel.saveSpotToLists(spotData: spotData, listIds: selectedListIds)
            onSaveComplete?()
            onDismiss()
        } catch {
            errorMessage = (error as NSError).localizedDescription.isEmpty
                ? "Failed to save. Please try again."
                : (error as NSError).localizedDescription
            isSaving = false
        }
    }
}

// MARK: - Button style

private struct SaveToListTealButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? Color.spotsTealActive : Color.spotsTeal)
            )
    }
}
