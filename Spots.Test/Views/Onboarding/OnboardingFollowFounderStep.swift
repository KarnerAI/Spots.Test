//
//  OnboardingFollowFounderStep.swift
//  Spots.Test
//
//  Screen 4: "Follow the founder" — the social-connection moment.
//
//  Avatar-centric card (Design D2):
//   - 96pt circular avatar centered top
//   - Founder name (17pt semibold)
//   - "Founder of Spots" teal pill (14pt)
//   - Social proof "{N} spots · {M} lists" (13pt gray, if available)
//   - 2-line italic tagline (when present in profile bio)
//   - Follow CTA inside the card
//
//  Retry behavior (CEO D11):
//   - Tap Follow → 2 silent retries with 0.5s + 1.5s backoff
//   - On 3rd failure → inline error + Done disabled until success or Skip
//
//  Bottom bar shows Skip + Done. Done is disabled until the follow
//  succeeds; Skip remains available throughout so the user is never
//  trapped on a failing network.
//

import SwiftUI

struct OnboardingFollowFounderStep: View {
    @EnvironmentObject private var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    OnboardingHeader(
                        headline: "Follow the founder",
                        subhead: "Get your Newsfeed started with someone who actually uses the app."
                    )
                    .padding(.top, 24)

                    founderCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        // Same toolbar treatment as the bucket/favorites screens — opaque
        // white nav bar so the progress dots beneath it don't get
        // visually clipped by iOS's translucent scroll-edge effect.
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // See OnboardingBucketStep / OnboardingFavoritesStep / WelcomeStep
        // — same .safeAreaInset pattern so the founder card never gets
        // clipped by the bottom bar.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingBottomBar(
                primaryTitle: "Done",
                isPrimaryEnabled: vm.followState.isSucceeded,
                isPrimaryLoading: vm.isCompletingOnboarding,
                primaryAction: { Task { await vm.completeOnboarding() } },
                skipAction: { Task { await vm.skip(from: 4); await vm.completeOnboarding() } }
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                OnboardingBackButton(onTap: { Task { await vm.back() } })
            }
            // Progress dots ride in the toolbar's principal slot —
            // same treatment as the bucket/favorites screens.
            ToolbarItem(placement: .principal) {
                OnboardingProgressIndicator(
                    currentStep: 4,
                    totalSteps: OnboardingRoute.totalSteps
                )
            }
        }
        .task {
            await vm.loadFounderProfileIfNeeded()
        }
    }

    // MARK: - Founder card

    private var founderCard: some View {
        VStack(spacing: 16) {
            avatar
            VStack(spacing: 6) {
                Text(displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.gray900)
                Text("Founder of Spots")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.spotsTeal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.spotsTeal.opacity(0.10))
                    .clipShape(Capsule())
            }
            if let stats = statsLine {
                Text(stats)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray500)
            }
            followButton

            if let error = vm.followState.errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.white, Color.gray50],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.card)
                .stroke(Color.gray100, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverLabel)
    }

    // MARK: - Avatar

    private var avatar: some View {
        ZStack {
            if let avatarString = vm.founderProfile?.avatarUrl,
               let url = URL(string: avatarString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.gray100, lineWidth: 1))
    }

    private var avatarFallback: some View {
        Circle()
            .fill(Color.gray100)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(.gray500)
            )
    }

    // MARK: - Follow button

    private var followButton: some View {
        Button(action: { Task { await vm.followFounder() } }) {
            ZStack {
                Text(followButtonTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(vm.followState.isInFlight ? 0 : 1)
                if vm.followState.isInFlight {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(followButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button))
        }
        .disabled(vm.followState.isSucceeded || vm.followState.isInFlight)
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(followButtonTitle)
    }

    private var followButtonTitle: String {
        switch vm.followState {
        case .succeeded: return "Following"
        case .failed:    return "Try again"
        default:         return "Follow"
        }
    }

    private var followButtonBackground: Color {
        switch vm.followState {
        case .succeeded: return Color.gray500
        default:         return Color.spotsNavy
        }
    }

    // MARK: - Display strings

    private var displayName: String {
        if let profile = vm.founderProfile {
            return profile.displayName
        }
        return "Hussain"
    }

    private var statsLine: String? {
        let spots = vm.founderSpotCount ?? 0
        let lists = vm.founderListCount ?? 0
        guard spots > 0 || lists > 0 else { return nil }
        let spotsLabel = "\(spots) spot\(spots == 1 ? "" : "s")"
        let listsLabel = "\(lists) list\(lists == 1 ? "" : "s")"
        return "\(spotsLabel) · \(listsLabel)"
    }

    private var voiceOverLabel: String {
        let stats = statsLine.map { ". \($0)." } ?? ""
        return "\(displayName), founder of Spots\(stats) Tap to follow."
    }
}
