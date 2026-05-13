//
//  OnboardingChrome.swift
//  Spots.Test
//
//  Shared UI primitives used by all four onboarding step views.
//  Pulling them into one file keeps the steps focused on their
//  own copy/layout, and keeps the visual conventions consistent
//  (progress indicator, bottom CTA row, header block).
//
//  All token bindings come from the existing app design system —
//  Color.spotsTeal, Color.gray500/900, CornerRadius.button — so
//  the onboarding chrome reads as part of the same product.
//

import SwiftUI

// MARK: - Progress indicator

/// 4 horizontal dots at the top of every onboarding screen. The dot
/// for the current step is filled teal; everything else is gray.
/// Drives the "Step N of 4" VoiceOver label as well.
struct OnboardingProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { idx in
                Capsule()
                    .fill(idx == currentStep ? Color.spotsNavy : Color.gray200)
                    .frame(width: idx == currentStep ? 24 : 8, height: 8)
                    .animation(.easeOut(duration: 0.2), value: currentStep)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(currentStep) of \(totalSteps)")
    }
}

// MARK: - Headline + subhead block

/// Standard headline + subhead pair used at the top of each step
/// below the progress indicator.
struct OnboardingHeader: View {
    let headline: String
    let subhead: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.gray900)
                .fixedSize(horizontal: false, vertical: true)
            if let subhead {
                Text(subhead)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.gray500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Bottom CTA bar

/// Bottom CTA row: an optional Skip text-button on the left + a
/// filled-teal primary CTA on the right. Used on every screen.
/// The primary CTA is disabled when `isPrimaryEnabled` is false (e.g.
/// username invalid on screen 1).
struct OnboardingBottomBar: View {
    let primaryTitle: String
    let isPrimaryEnabled: Bool
    let isPrimaryLoading: Bool
    let showsSkip: Bool
    let primaryAction: () -> Void
    let skipAction: (() -> Void)?

    init(
        primaryTitle: String,
        isPrimaryEnabled: Bool = true,
        isPrimaryLoading: Bool = false,
        showsSkip: Bool = true,
        primaryAction: @escaping () -> Void,
        skipAction: (() -> Void)? = nil
    ) {
        self.primaryTitle = primaryTitle
        self.isPrimaryEnabled = isPrimaryEnabled
        self.isPrimaryLoading = isPrimaryLoading
        self.showsSkip = showsSkip
        self.primaryAction = primaryAction
        self.skipAction = skipAction
    }

    var body: some View {
        // Stacked layout (2026-05-12 update): primary CTA full-width on
        // top, Skip as a smaller centered text link below. Matches the
        // contemporary onboarding pattern used by Pinterest, Instagram,
        // Stripe, and Duolingo — the primary action gets undisputed
        // visual weight, and Skip remains available without competing.
        VStack(spacing: 8) {
            Button(action: primaryAction) {
                ZStack {
                    Text(primaryTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .opacity(isPrimaryLoading ? 0 : 1)
                    if isPrimaryLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isPrimaryEnabled ? Color.spotsNavy : Color.gray300)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button))
            }
            .disabled(!isPrimaryEnabled || isPrimaryLoading)
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(primaryTitle)

            if showsSkip {
                Button(action: { skipAction?() }) {
                    Text("Skip")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.gray500)
                        // Tighter padding gives Skip its own visual weight
                        // without competing with the primary CTA. Tap
                        // target is ~36pt — slightly under the 44pt WCAG
                        // ideal, but acceptable for a clearly-secondary
                        // text link that's also offered as a hardware
                        // back gesture on screens 2-4.
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .accessibilityHint("Skip this step")
            }
        }
        // Generous top padding gives the navy button breathing room from
        // whatever scrolls behind. 16pt internal, plus the 1pt hairline
        // divider above acts as a visual separator from the cards.
        .padding(.top, 16)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        // Solid white background extends through the home-indicator safe
        // area so the bar reads as its own layer, and scrolling cards
        // don't peek out beneath the button.
        .background(
            ZStack(alignment: .top) {
                Color.white
                    .ignoresSafeArea(edges: .bottom)
                Rectangle()
                    .fill(Color.gray100)
                    .frame(height: 1)
            }
        )
    }
}

// MARK: - Top toast

/// Top-aligned auto-dismissing toast surfaced from the VM's
/// `toastMessage` published string. Used by the bucket/favorites
/// screens on save failure (D3).
struct OnboardingToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray900)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray500)
                    .padding(8)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray200, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Back button (custom toolbar leading)

/// Custom back-button used in the toolbar for screens 2-4. We hide the
/// native NavigationStack back button and route through this so we can
/// fire the `OnboardingViewModel.back()` telemetry hook instead of
/// just popping the path silently.
struct OnboardingBackButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.gray900)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Back")
    }
}
