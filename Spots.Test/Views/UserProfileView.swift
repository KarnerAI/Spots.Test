//
//  UserProfileView.swift
//  Spots.Test
//
//  Read-only profile of another user. Shows the cover photo, avatar, name,
//  username, account-privacy state, and a Follow / Requested / Following
//  button. When the target is private and the viewer is not an accepted
//  follower, the spot lists are hidden behind a lock state.
//

import SwiftUI

struct UserProfileView: View {
    let userId: UUID

    @State private var profile: UserProfile?
    @State private var relationship: FollowRelationship = .none
    @State private var isLoadingProfile = true
    @State private var isMutatingFollow = false
    @State private var errorMessage: String?

    private let coverHeight: CGFloat = 180
    private let avatarSize: CGFloat = 92

    var body: some View {
        ZStack(alignment: .top) {
            Color.gray100.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    coverSection
                    headerCard
                    contentSection
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
            }

            if let errorMessage {
                ErrorToast(message: errorMessage)
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationTitle((profile?.username).map { "@\($0)" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Cover

    private var coverSection: some View {
        Group {
            if let urlString = profile?.coverPhotoUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        coverFallback
                    @unknown default:
                        coverFallback
                    }
                }
            } else {
                coverFallback
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: coverHeight)
        .clipped()
    }

    private var coverFallback: some View {
        LinearGradient(
            colors: [Color.spotsTeal.opacity(0.5), Color.spotsTeal.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Header card

    private var headerCard: some View {
        VStack(spacing: 12) {
            avatar
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 4))
                .offset(y: -avatarSize / 2)
                .padding(.bottom, -avatarSize / 2)

            VStack(spacing: 4) {
                Text(profile?.displayName ?? "")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.gray900)
                if let username = profile?.username {
                    Text("@\(username)")
                        .font(.system(size: 14))
                        .foregroundColor(.gray500)
                }
                if profile?.isPrivate == true {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                        Text("Private account")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.gray500)
                    .padding(.top, 2)
                }
            }

            followButton
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Color.white)
    }

    private var avatar: some View {
        Group {
            if let urlString = profile?.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        avatarPlaceholder
                    @unknown default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.gray200)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.gray400)
            )
    }

    // MARK: - Follow button

    @ViewBuilder
    private var followButton: some View {
        switch relationship {
        case .isSelf:
            EmptyView()
        case .none, .followsYou:
            Button(action: { Task { await tapFollow() } }) {
                buttonLabel(text: "Follow", style: .primary)
            }
            .disabled(isMutatingFollow)
        case .requested:
            Button(action: { Task { await tapUnfollow() } }) {
                buttonLabel(text: "Requested", style: .secondary)
            }
            .disabled(isMutatingFollow)
        case .following, .mutual:
            Button(action: { Task { await tapUnfollow() } }) {
                buttonLabel(text: relationship == .mutual ? "Friends" : "Following", style: .secondary)
            }
            .disabled(isMutatingFollow)
        }
    }

    private enum ButtonStyleKind { case primary, secondary }

    private func buttonLabel(text: String, style: ButtonStyleKind) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(style == .primary ? .white : .gray700)
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(style == .primary ? Color.spotsTeal : Color.gray100)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button, style: .continuous))
    }

    // MARK: - Content (lists or lock)

    @ViewBuilder
    private var contentSection: some View {
        if isLoadingProfile {
            ProgressView().padding(.vertical, 40)
        } else if profile?.isPrivate == true,
                  relationship != .following,
                  relationship != .mutual,
                  relationship != .isSelf {
            lockState
        } else {
            // Phase 1 keeps this section sparse — it's the doorway, not the destination.
            // Phase 2 will surface the user's public lists / recent activity here.
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundColor(.gray400)
                Text("Activity preview coming soon")
                    .font(.system(size: 14))
                    .foregroundColor(.gray500)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }

    private var lockState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundColor(.gray400)
            Text("This account is private")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.gray900)
            Text("Follow this account to see their saved spots and lists.")
                .font(.system(size: 13))
                .foregroundColor(.gray500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func load() async {
        isLoadingProfile = true
        do {
            async let profileTask = ProfileService.shared.fetchProfile(userId: userId)
            async let relTask = FollowService.shared.relationship(with: userId, forceRefresh: true)
            let (loadedProfile, loadedRelationship) = try await (profileTask, relTask)
            profile = loadedProfile
            relationship = loadedRelationship
        } catch {
            errorMessage = "Couldn't load profile. \(error.localizedDescription)"
            scheduleErrorDismiss()
        }
        isLoadingProfile = false
    }

    private func tapFollow() async {
        isMutatingFollow = true
        defer { isMutatingFollow = false }
        do {
            let status = try await FollowService.shared.follow(userId: userId)
            relationship = (status == .accepted) ? .following : .requested
        } catch {
            errorMessage = "Couldn't follow. \(error.localizedDescription)"
            scheduleErrorDismiss()
        }
    }

    private func tapUnfollow() async {
        isMutatingFollow = true
        defer { isMutatingFollow = false }
        do {
            try await FollowService.shared.unfollow(userId: userId)
            relationship = try await FollowService.shared.relationship(with: userId, forceRefresh: true)
        } catch {
            errorMessage = "Couldn't update follow. \(error.localizedDescription)"
            scheduleErrorDismiss()
        }
    }

    private func scheduleErrorDismiss() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { errorMessage = nil }
        }
    }
}

// MARK: - Inline error toast

private struct ErrorToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            .frame(maxWidth: 320)
    }
}
