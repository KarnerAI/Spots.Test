//
//  EditProfileView.swift
//  Spots.Test
//
//  Edit Profile screen (Figma node 69-227).
//  Entry points: profile photo tap on ProfileView, and "Edit Profile" row in SettingsView.
//

import SwiftUI
import PhotosUI

// MARK: - Design tokens (reuse existing Color extension values)

private enum EditProfileColors {
    static let primaryText = Color(red: 0.063, green: 0.094, blue: 0.157)   // #101828
    static let secondaryText = Color(red: 0.42, green: 0.45, blue: 0.51)    // #6a7282
    static let fieldBg = Color.gray100                                        // #f3f4f6
    static let infoBg = Color.gray100
    static let errorText = Color(red: 0.91, green: 0, blue: 0.04)            // #e7000b
    static let saveEnabled = Color.spotsTeal
    static let saveDisabled = Color.gray400
}

// MARK: - View Model

@MainActor
class EditProfileViewModel: ObservableObject {
    // Form state
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var username: String = ""
    @Published var avatarUrl: String? = nil

    // UI state
    @Published var selectedImage: UIImage? = nil
    @Published var isSaving: Bool = false
    @Published var isLoadingProfile: Bool = false
    @Published var usernameError: String? = nil
    @Published var generalError: String? = nil
    @Published var saveSuccess: Bool = false

    private var userId: UUID?
    private var originalUsername: String = ""

    var isDirty: Bool {
        firstName != originalUsername       // always allow save if any field differs from loaded
        || true                             // simplify: Save always enabled once loaded
    }

    var usernameStripped: String { username.trimmingCharacters(in: .whitespaces) }
    var firstNameStripped: String { firstName.trimmingCharacters(in: .whitespaces) }
    var lastNameStripped: String { lastName.trimmingCharacters(in: .whitespaces) }

    // MARK: - Load

    func loadProfile(authViewModel: AuthenticationViewModel) async {
        isLoadingProfile = true
        defer { isLoadingProfile = false }

        let uid = authViewModel.currentUserId
        self.userId = uid

        // Seed from auth metadata immediately so UI shows something fast
        firstName = authViewModel.currentUserFirstName == "First Name" ? "" : authViewModel.currentUserFirstName
        lastName = authViewModel.currentUserLastName == "Last Name" ? "" : authViewModel.currentUserLastName
        username = authViewModel.currentUserUsername == "username" ? "" : authViewModel.currentUserUsername
        avatarUrl = authViewModel.currentUserAvatarUrl
        originalUsername = username

        // Then fetch the profiles table row for the latest data
        guard let uid else { return }
        do {
            // Ensure a profile row exists (handles users created before trigger)
            try await ProfileService.shared.ensureProfileExists(
                userId: uid,
                username: username.isEmpty ? (authViewModel.currentUserUsername) : username,
                firstName: firstName,
                lastName: lastName,
                email: ""
            )
            if let profile = try await ProfileService.shared.fetchProfile(userId: uid) {
                firstName = profile.firstName ?? firstName
                lastName = profile.lastName ?? lastName
                username = profile.username
                avatarUrl = profile.avatarUrl ?? avatarUrl
                originalUsername = profile.username
            }
        } catch {
            print("EditProfileViewModel: loadProfile error: \(error)")
        }
    }

    // MARK: - Save

    func save(authViewModel: AuthenticationViewModel) async {
        guard !isSaving else { return }
        usernameError = nil
        generalError = nil

        let uname = usernameStripped
        let fname = firstNameStripped
        let lname = lastNameStripped

        guard !uname.isEmpty else {
            usernameError = "Username cannot be empty"
            return
        }
        guard uname.count >= 3 else {
            usernameError = "Username must be at least 3 characters"
            return
        }

        guard let uid = userId else {
            generalError = "Unable to identify the current user. Please log out and back in."
            return
        }

        isSaving = true
        defer { isSaving = false }

        // Username uniqueness check (skip if unchanged)
        if uname.lowercased() != originalUsername.lowercased() {
            do {
                let taken = try await ProfileService.shared.isUsernameTaken(username: uname, excludingUserId: uid)
                if taken {
                    usernameError = "This username is already taken"
                    return
                }
            } catch {
                generalError = "Could not verify username availability. Please try again."
                return
            }
        }

        // Upload new avatar if one was selected
        var finalAvatarUrl = avatarUrl
        if let img = selectedImage {
            do {
                let uploaded = try await ProfileService.shared.uploadAvatar(userId: uid, image: img)
                finalAvatarUrl = uploaded
            } catch {
                generalError = "Profile photo upload failed: \(error.localizedDescription). Other changes were not saved."
                return
            }
        }

        // Update profiles table
        do {
            try await ProfileService.shared.updateProfile(
                userId: uid,
                firstName: fname,
                lastName: lname,
                username: uname,
                avatarUrl: finalAvatarUrl
            )
        } catch {
            generalError = "Failed to save profile. Please try again."
            return
        }

        // Sync auth metadata so ProfileView updates without re-fetching
        await ProfileService.shared.syncAuthMetadata(
            firstName: fname,
            lastName: lname,
            username: uname,
            avatarUrl: finalAvatarUrl
        )

        // Refresh the shared view model so Profile tab reflects changes instantly
        authViewModel.refreshProfile()
        avatarUrl = finalAvatarUrl
        originalUsername = uname
        selectedImage = nil
        saveSuccess = true
    }
}

// MARK: - View

struct EditProfileView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @StateObject private var vm = EditProfileViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var showPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                photoSection
                formSection
                infoBox
                Spacer().frame(height: 60)
            }
            .padding(.top, 24)
        }
        .background(Color.white)
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await vm.save(authViewModel: authViewModel) }
                } label: {
                    if vm.isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(EditProfileColors.saveEnabled)
                    }
                }
                .disabled(vm.isSaving)
            }
        }
        .onChange(of: photoPickerItem) { _, newItem in
            Task {
                guard let item = newItem,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { return }
                vm.selectedImage = img
            }
        }
        .onChange(of: vm.saveSuccess) { _, success in
            if success { dismiss() }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.generalError != nil },
            set: { if !$0 { vm.generalError = nil } }
        )) {
            Button("OK", role: .cancel) { vm.generalError = nil }
        } message: {
            Text(vm.generalError ?? "")
        }
        .task { await vm.loadProfile(authViewModel: authViewModel) }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoPickerItem,
            matching: .images
        )
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        VStack(spacing: 10) {
            Button { showPhotoPicker = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    avatarCircle

                    // Camera badge
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
                Text("Change Photo")
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

            if let picked = vm.selectedImage {
                Image(uiImage: picked)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let urlString = vm.avatarUrl, let url = URL(string: urlString) {
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

    // MARK: - Form

    private var formSection: some View {
        VStack(spacing: 20) {
            profileField(label: "First Name", placeholder: "First Name", text: $vm.firstName, error: nil)
            profileField(label: "Last Name", placeholder: "Last Name", text: $vm.lastName, error: nil)
            usernameField
        }
        .padding(.horizontal, 20)
    }

    private func profileField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(EditProfileColors.primaryText)

            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .foregroundColor(EditProfileColors.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(EditProfileColors.fieldBg)
                .cornerRadius(10)
                .autocorrectionDisabled()

            if let err = error {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(EditProfileColors.errorText)
            }
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Username")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(EditProfileColors.primaryText)

            HStack(spacing: 0) {
                Text("@")
                    .font(.system(size: 14))
                    .foregroundColor(EditProfileColors.secondaryText)
                    .padding(.leading, 14)

                TextField("username", text: $vm.username)
                    .font(.system(size: 14))
                    .foregroundColor(EditProfileColors.primaryText)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding(.vertical, 12)
                    .padding(.trailing, 14)
                    .padding(.leading, 2)
                    .onChange(of: vm.username) { _, _ in vm.usernameError = nil }
            }
            .background(EditProfileColors.fieldBg)
            .cornerRadius(10)

            if let err = vm.usernameError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(EditProfileColors.errorText)
            }
        }
    }

    // MARK: - Info Box

    private var infoBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your profile information is visible to all Spots users.")
                .font(.system(size: 13))
                .foregroundColor(EditProfileColors.secondaryText)
            Text("Choose a username that represents you well.")
                .font(.system(size: 13))
                .foregroundColor(EditProfileColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(EditProfileColors.infoBg)
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        EditProfileView().environmentObject(AuthenticationViewModel())
    }
}
