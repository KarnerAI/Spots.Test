//
//  OnboardingFavoritesStep.swift
//  Spots.Test
//
//  Screen 3: "What do you love?" — the favorites moment.
//  Renders the shared curated grid; taps write to .starred (the
//  elite "Favorites" tier in the app's three-list system).
//

import SwiftUI

struct OnboardingFavoritesStep: View {
    var body: some View {
        OnboardingCuratedGridStep(
            stepNumber: 3,
            headline: "What do you love?",
            subhead: "Star your all-time favorites",
            category: .starred,
            primaryTitle: "Continue"
        )
    }
}
