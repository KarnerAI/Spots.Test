//
//  OnboardingRoute.swift
//  Spots.Test
//
//  NavigationStack destinations for the post-signup onboarding flow.
//  The container view (PostSignupOnboardingFlow) holds the welcome
//  step as its root; each subsequent step is pushed by appending a
//  case to OnboardingViewModel.path.
//
//  ┌──────────────────────────────────────────────────────────────────┐
//  │  STATE MACHINE                                                   │
//  │                                                                  │
//  │   path = []                  → screen 1 (Welcome / profile)      │
//  │   path = [.bucket]           → screen 2 (Build your bucket list) │
//  │   path = [.bucket, .fav]     → screen 3 (What do you love?)      │
//  │   path = [.bucket, .fav,                                         │
//  │           .followFounder]    → screen 4 (Follow the founder)     │
//  │                                                                  │
//  │  Back-navigation = path.removeLast(). NavigationStack handles    │
//  │  the gesture + chevron natively. The profiles.onboarding_step    │
//  │  column tracks the FURTHEST step reached, not path.count — see   │
//  │  OnboardingViewModel.back() and plan Design D6.                  │
//  └──────────────────────────────────────────────────────────────────┘
//

import Foundation

enum OnboardingRoute: Hashable {
    /// Screen 2 — bucket-list save grid.
    case bucket
    /// Screen 3 — favorites save grid.
    case favorites
    /// Screen 4 — follow-the-founder card with retry.
    case followFounder
}

extension OnboardingRoute {
    /// 1-indexed screen number. Welcome step is 1 (no route); first
    /// pushed route (.bucket) is screen 2. Used for telemetry events
    /// and the progress-dot indicator.
    var stepNumber: Int {
        switch self {
        case .bucket:        return 2
        case .favorites:     return 3
        case .followFounder: return 4
        }
    }

    /// Total step count across the flow. Drives the progress indicator
    /// ("Step N of 4"). Update if the flow ever grows or shrinks.
    static let totalSteps: Int = 4
}
