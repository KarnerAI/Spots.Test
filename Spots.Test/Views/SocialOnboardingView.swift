//
//  SocialOnboardingView.swift
//  Spots.Test
//
//  One-time onboarding screen for users who signed in via a social provider
//  (Google, Apple). The SQL trigger has already created their `profiles` row
//  with auto-derived values; this screen lets them confirm or edit before
//  the app routes them to MainTabView.
//

import SwiftUI
import PhotosUI

struct SocialOnboardingView: View {
    @ObservedObject var viewModel: AuthenticationViewModel

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var username: String = ""
    @State private var avatarUrl: String? = nil
    @State private var selectedImage: UIImage? = nil

    @State private var usernameError: String? = nil
    @State private var generalError: String? = nil
    @State private var isLoadingProfile: Bool = true
    @State private var isSaving: Bool = false

    @State private var showPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem? = nil

    /// Debounce token for the live username uniqueness check.
    @State private var usernameCheckTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    photoSection
                    formSection
                    Spacer().frame(height: 12)
                    continueButton
                    Spacer().frame(height: 40)
                }
                .padding(.top, 32)
            }
            .disabled(isLoadingProfile || isSaving)

            if isLoadingProfile {
                ProgressView()
                    .scaleEffect(1.3)
            }
        }
        .task { await loadInitial() }
        .onChange(of: photoPickerItem) { _, newItem in
            Task {
                guard let item = newItem,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { return }
                selectedImage = img
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoPickerItem,
            matching: .images
        )
        .alert("Error", isPresented: Binding(
            get: { generalError != nil },
            set: { if !$0 { generalError = nil } }
        )) {
            Button("OK", role: .cancel) { generalError = nil }
        } message: {
            Text(generalError ?? "")
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Welcome to Spots")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.gray900)
            Text("Tell us a bit about yourself to get started.")
                .font(.system(size: 15))
                .foregroundColor(.gray600)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var photoSection: some View {
        VStack(spacing: 8) {
            Button { showPhotoPicker = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    avatarCircle
                    ZStack {
                        Circle()
                            .fill(Color.spotsTeal)
                            .frame(width: 30, height: 30)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                    .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)

            Button { showPhotoPicker = true } label: {
                Text(selectedImage == nil && avatarUrl == nil ? "Add Photo" : "Change Photo")
                    .font(.system(size: 14))
                    .foregroundColor(.spotsTeal)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var avatarCircle: some View {
        let size: CGFloat = 100
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: size + 6, height: size + 6)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)

            if let picked = selectedImage {
                Image(uiImage: picked)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let urlString = avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        placeholderIcon
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                placeholderIcon
                    .frame(width: size, height: size)
                    .background(Color.gray200)
                    .clipShape(Circle())
            }
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 44))
            .foregroundColor(.gray400)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray200)
    }

    private var formSection: some View {
        VStack(spacing: 16) {
            FormField(
                label: "First Name",
                placeholder: "Enter your first name",
                text: $firstName,
                icon: nil,
                error: nil,
                isSecure: false
            )
            FormField(
                label: "Last Name",
                placeholder: "Enter your last name",
                text: $lastName,
                icon: nil,
                error: nil,
                isSecure: false
            )
            FormField(
                label: "Username",
                placeholder: "Choose a username",
                text: Binding(
                    get: { username },
                    set: { newValue in
                        username = newValue
                        scheduleUsernameCheck(newValue)
                    }
                ),
                icon: "person",
                error: usernameError,
                isSecure: false
            )
        }
        .padding(.horizontal, 24)
    }

    private var continueButton: some View {
        Button(action: { Task { await save() } }) {
            HStack {
                if isSaving {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Continue")
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(canSave ? Color.spotsTeal : Color.gray400)
            .cornerRadius(28)
        }
        .disabled(!canSave || isSaving)
        .padding(.horizontal, 24)
    }

    // MARK: - Validation

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        username.trimmingCharacters(in: .whitespaces).count >= 3 &&
        usernameError == nil
    }

    // MARK: - Username availability

    private func scheduleUsernameCheck(_ value: String) {
        usernameCheckTask?.cancel()
        usernameError = nil
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return }

        usernameCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard let uid = viewModel.currentUserId else { return }
            do {
                let taken = try await ProfileService.shared.isUsernameTaken(
                    username: trimmed,
                    excludingUserId: uid
                )
                guard !Task.isCancelled else { return }
                if taken { usernameError = "This username is already taken" }
            } catch {
                // Silently swallow — DB constraint will catch a stale check on save.
            }
        }
    }

    // MARK: - Load (pre-fill from profiles row)

    private func loadInitial() async {
        defer { isLoadingProfile = false }
        guard let uid = viewModel.currentUserId else { return }

        // Seed from auth metadata where it exists (Google sets first_name/last_name
        // via given_name/family_name? No — auth metadata uses Google's keys, which
        // loadProfileFromUser does NOT translate. So these will be the placeholder
        // strings "First Name"/"Last Name" — fall through to the profiles row.
        do {
            if let profile = try await ProfileService.shared.fetchProfile(userId: uid) {
                firstName = profile.firstName ?? ""
                lastName = profile.lastName ?? ""
                username = profile.username
                avatarUrl = profile.avatarUrl
            }
        } catch {
            print("SocialOnboardingView: fetchProfile failed: \(error)")
            // Form stays empty; user can still type values and save.
        }
    }

    // MARK: - Save

    private func save() async {
        guard canSave, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let fname = firstName.trimmingCharacters(in: .whitespaces)
        let lname = lastName.trimmingCharacters(in: .whitespaces)
        let uname = username.trimmingCharacters(in: .whitespaces)

        do {
            try await viewModel.completeSocialOnboarding(
                firstName: fname,
                lastName: lname,
                username: uname,
                avatarImage: selectedImage
            )
            // ContentView re-routes to MainTabView once needsSocialOnboarding flips false.
        } catch {
            // DB unique constraint surfaces here if a race grabbed the username.
            let message = error.localizedDescription
            if message.contains("duplicate key") || message.contains("unique constraint") {
                usernameError = "Just got taken — pick another"
            } else {
                generalError = message
            }
        }
    }
}

#Preview {
    SocialOnboardingView(viewModel: AuthenticationViewModel())
}
