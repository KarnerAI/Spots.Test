//
//  OnboardingWelcomeStep.swift
//  Spots.Test
//
//  Screen 1 of the post-signup onboarding flow. Two render modes:
//
//   Google-path (no username in auth metadata yet):
//     - first name + last name (pre-filled from auth metadata)
//     - username (BLANK, debounced uniqueness check, required)
//     - "Add photo" picker (optional)
//     - Continue button (disabled until username is valid)
//
//   Email-path (username + names already set during SignUpView):
//     - "Add photo" + Continue only
//     - No name/username fields shown
//
//  Skip is NOT offered here — username + identity is the only
//  required step in the flow. The bottom bar shows a Continue CTA
//  only.
//

import SwiftUI
import PhotosUI

struct OnboardingWelcomeStep: View {
    @EnvironmentObject private var vm: OnboardingViewModel

    @State private var photosPickerItem: PhotosPickerItem? = nil
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case firstName, lastName, username }

    var body: some View {
        VStack(spacing: 0) {
            logoMark
                .padding(.top, 24)
                .padding(.bottom, 16)

            OnboardingProgressIndicator(
                currentStep: 1,
                totalSteps: OnboardingRoute.totalSteps
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    OnboardingHeader(
                        headline: vm.welcomeStepShowsProfileFields
                            ? "Welcome to Spots"
                            : "Almost there",
                        subhead: vm.welcomeStepShowsProfileFields
                            ? "Pick a username and add a photo so people can find you."
                            : "Add a photo so people can find you."
                    )
                    .padding(.top, 24)

                    photoPicker

                    if vm.welcomeStepShowsProfileFields {
                        nameFields
                        usernameField
                    }

                    if let error = vm.profileSaveError {
                        Text(error)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        // Attaching the bottom bar via .safeAreaInset (instead of placing it
        // inside the VStack) tells the ScrollView above to reserve space
        // for the bar — so scrolled content stops cleanly above the
        // button instead of disappearing beneath it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingBottomBar(
                primaryTitle: "Continue",
                isPrimaryEnabled: canContinue,
                isPrimaryLoading: vm.isSavingProfile,
                showsSkip: false,
                primaryAction: handleContinue
            )
        }
        .onChange(of: photosPickerItem) { _, newItem in
            Task { await loadPhoto(from: newItem) }
        }
    }

    // MARK: - Logo mark

    /// Brand logo, centered above the progress indicator at the top of
    /// the screen. Renders the `LogoMark` asset when available; falls
    /// back to a system-symbol stand-in so the view still looks
    /// intentional during development before the PNG/PDF has been
    /// imported into Assets.xcassets.
    ///
    /// Asset contract: same as OnboardingCelebrationOverlay — name
    /// `LogoMark`, square aspect (the brand logo's pin geometry already
    /// has its own colored shapes; no surrounding background needed).
    private var logoMark: some View {
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

    // MARK: - Photo picker

    private var photoPicker: some View {
        HStack {
            Spacer()
            PhotosPicker(selection: $photosPickerItem, matching: .images) {
                ZStack {
                    if let photo = vm.selectedPhoto {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.gray100)
                            .frame(width: 88, height: 88)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundColor(.gray500)
                            )
                    }
                }
                .overlay(
                    Circle()
                        .stroke(Color.gray200, lineWidth: 1)
                )
            }
            .accessibilityLabel(vm.selectedPhoto == nil ? "Add a profile photo" : "Change profile photo")
            Spacer()
        }
    }

    @MainActor
    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            vm.selectedPhoto = image
        }
    }

    // MARK: - Name fields (Google path only)

    private var nameFields: some View {
        VStack(spacing: 12) {
            labeledField(
                "First name",
                text: Binding(get: { vm.firstName }, set: { vm.firstName = $0 }),
                field: .firstName,
                textContentType: .givenName
            )
            labeledField(
                "Last name",
                text: Binding(get: { vm.lastName }, set: { vm.lastName = $0 }),
                field: .lastName,
                textContentType: .familyName
            )
        }
    }

    private func labeledField(
        _ label: String,
        text: Binding<String>,
        field: Field,
        textContentType: UITextContentType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.gray500)
            TextField(label, text: text)
                .textContentType(textContentType)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.gray50)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.field))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.field)
                        .stroke(focusedField == field ? Color.spotsNavy : Color.gray200, lineWidth: 1)
                )
        }
    }

    // MARK: - Username field (Google path only)

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Username")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray500)
                Spacer()
                usernameStateIndicator
            }
            TextField("Username", text: Binding(
                get: { vm.username },
                set: { newValue in
                    vm.username = newValue
                    vm.onUsernameChanged(newValue)
                }
            ))
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .username)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.gray50)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.field))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.field)
                    .stroke(usernameBorderColor, lineWidth: 1)
            )

            if let errorMessage = vm.usernameState.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.red)
                    .accessibilityLiveRegion(.polite)
            }
        }
    }

    private var usernameBorderColor: Color {
        // Border picks up the username's validation state: green-on-valid uses
        // teal (the accent for positive confirmation), red on error/taken, and
        // navy when focused-but-still-typing (matches the focused state of
        // the name fields above).
        switch vm.usernameState {
        case .valid: return Color.spotsTeal
        case .taken, .error: return .red
        case .idle, .checking: return focusedField == .username ? Color.spotsNavy : Color.gray200
        }
    }

    @ViewBuilder
    private var usernameStateIndicator: some View {
        switch vm.usernameState {
        case .checking:
            ProgressView().scaleEffect(0.7)
        case .valid:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.spotsTeal)
                .font(.system(size: 14))
        case .taken, .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 14))
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Continue gating

    private var canContinue: Bool {
        if vm.welcomeStepShowsProfileFields {
            let trimmedFirst = vm.firstName.trimmingCharacters(in: .whitespaces)
            let trimmedLast = vm.lastName.trimmingCharacters(in: .whitespaces)
            return !trimmedFirst.isEmpty &&
                   !trimmedLast.isEmpty &&
                   vm.usernameState.isValid
        } else {
            // Email-path: photo is optional, so Continue is always enabled.
            return true
        }
    }

    private func handleContinue() {
        focusedField = nil
        Task { _ = await vm.saveProfileAndAdvance() }
    }
}

// MARK: - Polite-announce extension stub

private extension View {
    /// Conditional polite-announce that no-ops on iOS < 16.4. iOS 17+
    /// has accessibilitySpeechAnnouncementsQueued via `accessibilityRespondsToUserInteraction`;
    /// for our minimum target (17.0) `.accessibilityLiveRegion` would be a
    /// custom modifier. Keep this as a no-op shim so the call site is
    /// future-friendly and can be swapped without touching the view.
    @ViewBuilder
    func accessibilityLiveRegion(_ politeness: AccessibilityLiveRegionPoliteness) -> some View {
        self
    }
}

private enum AccessibilityLiveRegionPoliteness { case polite, assertive }
