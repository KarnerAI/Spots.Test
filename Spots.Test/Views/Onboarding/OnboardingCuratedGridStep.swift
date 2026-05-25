//
//  OnboardingCuratedGridStep.swift
//  Spots.Test
//
//  Shared rendering for onboarding screens 2 (bucket list) and 3
//  (favorites). Both screens display the same 12 curated spots in
//  a 2-column grid — they differ only in:
//
//   - headline copy ("Where will you go next?" vs "What do you love?")
//   - subhead copy
//   - which list a tap writes to (.wantToGo vs .favorites)
//   - the icon overlay (emerald flag vs red heart)
//   - the VM selection set the card reads from (bucket vs favorites)
//
//  Wrapping both behaviors in this single view keeps the logic in
//  one place. The two screens are thin wrappers (see
//  OnboardingBucketStep / OnboardingFavoritesStep).
//
//  Lazy image loading + the 4:5 aspect ratio per card is handled
//  inside CuratedSpotCard — this view just lays them out.
//

import SwiftUI

struct OnboardingCuratedGridStep: View {
    @EnvironmentObject private var vm: OnboardingViewModel

    let stepNumber: Int
    let headline: String
    let subhead: String
    let category: ListKind
    let primaryTitle: String

    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OnboardingHeader(headline: headline, subhead: subhead)
                        .padding(.top, 24)

                    if vm.isLoadingCurated && vm.curatedSpots.isEmpty {
                        loadingPlaceholder
                    } else if vm.curatedLoadFailed && vm.curatedSpots.isEmpty {
                        loadFailedState
                    } else {
                        grid
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        // Solid white nav-bar background kills the iOS translucency
        // effect that otherwise blurs the progress dots into the bar
        // during scroll (the dots are NOT inside the ScrollView but
        // sit in the area iOS treats as scroll-edge for blur).
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // .safeAreaInset reserves space at the bottom of the ScrollView
        // for the bar so the last row of cards doesn't get clipped by
        // the Continue button. The bar itself paints a solid white
        // background through the home-indicator safe area.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingBottomBar(
                primaryTitle: primaryTitle,
                primaryAction: { Task { await vm.advance(from: stepNumber) } },
                skipAction: { Task { await vm.skip(from: stepNumber) } }
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                OnboardingBackButton(onTap: { Task { await vm.back() } })
            }
            // Progress dots ride in the toolbar's `.principal` slot, on
            // the same vertical baseline as the back chevron. This sits
            // them directly on the nav bar's bottom hairline rather than
            // floating in the content area below — avoids the visual
            // "cut off" effect from iOS's translucent scroll-edge.
            ToolbarItem(placement: .principal) {
                OnboardingProgressIndicator(
                    currentStep: stepNumber,
                    totalSteps: OnboardingRoute.totalSteps
                )
            }
        }
        .overlay(alignment: .top) { toastOverlay }
        .task {
            await vm.loadCuratedSpotsIfNeeded()
            await vm.hydrateSelectionsIfNeeded()
        }
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(columns: Self.columns, spacing: 16) {
            ForEach(vm.curatedSpots) { spot in
                CuratedSpotCard(
                    spot: spot,
                    category: category,
                    isSelected: isSelected(spot.placeId),
                    onToggle: { await toggle(spot: spot) }
                )
            }
        }
    }

    private func isSelected(_ placeId: String) -> Bool {
        switch category {
        case .wantToGo: return vm.bucketSelections.contains(placeId)
        case .favorites: return vm.favoriteSelections.contains(placeId)
        case .liked, .custom, .trip, .datePlan:
            return false  // not used by onboarding — only wantToGo + favorites grids ship
        }
    }

    private func toggle(spot: Spot) async {
        switch category {
        case .wantToGo:
            await vm.toggleBucket(placeId: spot.placeId, displayName: spot.name)
        case .favorites:
            await vm.toggleFavorite(placeId: spot.placeId, displayName: spot.name)
        case .liked, .custom, .trip, .datePlan:
            break  // not used by onboarding
        }
    }

    // MARK: - Empty / error states

    private var loadingPlaceholder: some View {
        LazyVGrid(columns: Self.columns, spacing: 16) {
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: CornerRadius.card)
                    .fill(Color.gray100)
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .redacted(reason: .placeholder)
            }
        }
        .accessibilityHidden(true)
    }

    private var loadFailedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.gray500)
            Text("Couldn't load spots.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.gray900)
            Button("Try again") {
                Task { await vm.loadCuratedSpotsIfNeeded() }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.spotsTeal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = vm.toastMessage {
            OnboardingToast(
                message: message,
                onDismiss: { vm.toastMessage = nil }
            )
            .task {
                // Auto-dismiss after 3s. Re-fires on each new toast.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                vm.toastMessage = nil
            }
        }
    }
}
