//
//  PostSignupOnboardingFlow.swift
//  Spots.Test
//
//  Container for the 4-screen post-signup onboarding flow.
//  Owns the `OnboardingViewModel` (lifetime = the flow), wraps
//  the steps in a NavigationStack driven by `vm.path`, and hosts
//  the celebration overlay on top.
//
//  Routing:
//   - ContentView renders this when `authVM.needsPostSignupOnboarding`
//     is true. When the user completes (or skips through) the flow,
//     the VM flips that flag and ContentView swaps in MainTabView.
//
//  Design (D4): the entire flow runs in light mode regardless of
//  the user's system theme, via .preferredColorScheme(.light).
//

import SwiftUI

struct PostSignupOnboardingFlow: View {
    /// Owned for the lifetime of the flow. Created with the shared
    /// AuthenticationViewModel so it can read profile state +
    /// signal back when onboarding completes.
    @StateObject private var vm: OnboardingViewModel
    @ObservedObject var authVM: AuthenticationViewModel

    init(authVM: AuthenticationViewModel) {
        self.authVM = authVM
        _vm = StateObject(wrappedValue: OnboardingViewModel(authVM: authVM))
    }

    var body: some View {
        ZStack {
            NavigationStack(path: $vm.path) {
                OnboardingWelcomeStep()
                    .navigationDestination(for: OnboardingRoute.self) { route in
                        switch route {
                        case .bucket:        OnboardingBucketStep()
                        case .favorites:     OnboardingFavoritesStep()
                        case .followFounder: OnboardingFollowFounderStep()
                        }
                    }
            }
            .environmentObject(vm)
            .tint(.spotsNavy)

            if vm.isShowingCelebration {
                OnboardingCelebrationOverlay(
                    firstName: authVM.currentUserFirstName ?? "",
                    onComplete: { vm.dismissCelebration() }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.3), value: vm.isShowingCelebration)
    }
}
