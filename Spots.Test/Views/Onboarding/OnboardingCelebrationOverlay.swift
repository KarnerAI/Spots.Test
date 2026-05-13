//
//  OnboardingCelebrationOverlay.swift
//  Spots.Test
//
//  Subtle fade overlay rendered above the flow on Done tap (screen 4).
//  Shows a frosted-glass card with the Spots logo + a personalized
//  greeting ("Welcome to Spots, {firstName}.") for 1.5s, then calls
//  the dismiss closure so the parent can cross-fade to Explore.
//
//  Design spec (plan Design D9):
//   - 64pt logo at top, name greeting (24pt semibold, gray900) below
//   - Frosted glass card on a 30%-opacity dim
//   - Hold 1.5s
//   - 300ms cross-fade in / out
//   - Reduce Motion: skip the scale + dim animations, plain fade only
//
//  Lifecycle:
//   - Caller renders this with `.opacity(vm.isShowingCelebration ? 1 : 0)`
//     and `.animation(.easeInOut(duration: 0.3))`.
//   - On appear, this view starts a 1.5s timer then calls `onComplete`.
//

import SwiftUI
import UIKit

struct OnboardingCelebrationOverlay: View {
    let firstName: String
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasStartedTimer = false
    @State private var cardScale: CGFloat = 0.96

    /// How long the greeting card stays on screen before dismiss.
    private static let holdDuration: TimeInterval = 1.5

    var body: some View {
        ZStack {
            // Dim the underlying screen to 30% opacity (= 70% black overlay
            // tinted toward neutral). Reduce Motion: skip the dim entirely.
            (reduceMotion ? Color.clear : Color.black.opacity(0.30))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                logoBadge

                Text(greeting)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.gray900)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 28)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 4)
            .scaleEffect(reduceMotion ? 1.0 : cardScale)
            .padding(.horizontal, 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(greeting)
        .onAppear(perform: startTimer)
    }

    // MARK: - Logo

    /// 64pt logo. Renders the brand mark from the asset catalog if
    /// available; falls back to a system-symbol-on-navy circle so the
    /// overlay still looks intentional during development before the
    /// asset has been imported.
    ///
    /// Asset contract: name `LogoMark`, ideally a 1024×1024 PNG or PDF
    /// vector imported into Assets.xcassets. The logo itself already
    /// has its own colored geometry (coral pin + teal check) so no
    /// background circle is drawn around it — that would clash.
    private var logoBadge: some View {
        Group {
            if UIImage(named: "LogoMark") != nil {
                Image("LogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.spotsNavy)
                        .frame(width: 64, height: 64)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Greeting copy

    private var greeting: String {
        let trimmed = firstName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "Welcome to Spots."
        }
        return "Welcome to Spots, \(trimmed)."
    }

    // MARK: - Timing

    /// Start the hold timer + the subtle scale-in animation. Guarded so a
    /// re-render during the hold (e.g. orientation change) doesn't restart
    /// the dismiss timer and keep the overlay alive longer than expected.
    private func startTimer() {
        guard !hasStartedTimer else { return }
        hasStartedTimer = true

        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) {
                cardScale = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDuration) {
            onComplete()
        }
    }
}

#Preview("With name") {
    OnboardingCelebrationOverlay(firstName: "Maya", onComplete: {})
        .background(Color.gray100)
}

#Preview("Empty name fallback") {
    OnboardingCelebrationOverlay(firstName: "", onComplete: {})
        .background(Color.gray100)
}
