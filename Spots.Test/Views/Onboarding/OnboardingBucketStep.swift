//
//  OnboardingBucketStep.swift
//  Spots.Test
//
//  Screen 2: "Where will you go next?" — the bucket-list moment.
//  Renders the shared curated grid; taps write to .wantToGo.
//

import SwiftUI

struct OnboardingBucketStep: View {
    var body: some View {
        OnboardingCuratedGridStep(
            stepNumber: 2,
            headline: "Where will you go next?",
            subhead: "Save spots you want to explore",
            category: .wantToGo,
            primaryTitle: "Continue"
        )
    }
}
