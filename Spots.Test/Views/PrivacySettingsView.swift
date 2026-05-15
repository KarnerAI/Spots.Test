//
//  PrivacySettingsView.swift
//  Spots.Test
//
//  Privacy detail screen reached from Settings → Privacy. Owns the
//  Private-account toggle and the explainer copy describing what changes
//  when an account flips between private (request-to-follow) and public
//  (auto-accept follows). Server-side, the `normalize_follow_status` and
//  `auto_accept_pending_on_public_flip` triggers do the actual work — the
//  toggle only writes to `profiles.is_private`.
//
//  Sized to grow: future controls (block list, hide from search, who can
//  DM you, etc.) drop in as additional sections without restructuring.
//

import SwiftUI

struct PrivacySettingsView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel

    @State private var isPrivate: Bool = true
    @State private var isPrivacyLoaded: Bool = false
    @State private var errorMessage: String?

    private let horizontalPadding: CGFloat = 24
    private let rowMinHeight: CGFloat = 64

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("ACCOUNT PRIVACY")
                privacyToggleSection

                explainerCopy
                    .padding(.top, 16)
                    .padding(.horizontal, horizontalPadding)

                Spacer().frame(height: 32)
            }
            .padding(.top, 8)
        }
        .background(Color.white)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.white, for: .navigationBar)
        .task { await loadPrivacy() }
        .alert("Couldn't update privacy", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Toggle row

    private var privacyToggleSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Private account")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))
                Text("When on, people must request to follow you")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { isPrivate },
                set: { newValue in
                    let previous = isPrivate
                    isPrivate = newValue
                    Task { await savePrivacy(newValue: newValue, previous: previous) }
                }
            ))
            .labelsHidden()
            .tint(.spotsTeal)
            .disabled(!isPrivacyLoaded)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(minHeight: rowMinHeight)
        .background(Color.white)
    }

    // MARK: - Explainer

    private var explainerCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            explainerRow(
                icon: "lock.fill",
                title: "Private",
                body: "People have to send a follow request to see your spots, lists, and footprint. You approve or reject each one."
            )
            explainerRow(
                icon: "globe",
                title: "Public",
                body: "Anyone can follow you instantly and see your spots, lists, and footprint without approval."
            )

            Text("Your existing followers don't change when you flip this. Switching from private to public auto-approves any pending requests.")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private func explainerRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.spotsTeal)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))
                Text(body)
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Section header (matches SettingsView style)

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.3)
            .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 8)
    }

    // MARK: - Load / Save

    private func loadPrivacy() async {
        guard let userId = viewModel.currentUserId else { return }
        do {
            if let profile = try await ProfileService.shared.fetchProfile(userId: userId) {
                await MainActor.run {
                    isPrivate = profile.isPrivate
                    isPrivacyLoaded = true
                }
            } else {
                await MainActor.run { isPrivacyLoaded = true }
            }
        } catch {
            // Leave the toggle disabled rather than showing a confident value
            // that doesn't match the server. User can retry by re-opening.
            print("⚠️ PrivacySettingsView: privacy load failed: \(error.localizedDescription)")
        }
    }

    private func savePrivacy(newValue: Bool, previous: Bool) async {
        guard isPrivacyLoaded, let userId = viewModel.currentUserId else { return }
        do {
            try await ProfileService.shared.updateIsPrivate(userId: userId, isPrivate: newValue)
        } catch {
            await MainActor.run {
                isPrivate = previous
                errorMessage = error.localizedDescription
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

#Preview {
    NavigationStack {
        PrivacySettingsView().environmentObject(AuthenticationViewModel())
    }
}
