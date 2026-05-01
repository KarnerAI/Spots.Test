//
//  FollowRequestsView.swift
//  Spots.Test
//
//  Inbox of pending follow requests addressed to the current user.
//  Each row supports inline Accept / Reject actions.
//

import SwiftUI

struct FollowRequestsView: View {
    var onChanged: (() -> Void)? = nil

    @State private var requests: [PendingRequest] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pendingActionIds: Set<UUID> = []

    var body: some View {
        Group {
            if isLoading && requests.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, requests.isEmpty {
                SpotsErrorStateView(message: errorMessage) {
                    Task { await load() }
                }
            } else if requests.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(requests) { request in
                            requestRow(request)
                            Divider().padding(.leading, 76)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Follow Requests")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.white)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Row

    private func requestRow(_ request: PendingRequest) -> some View {
        let isBusy = pendingActionIds.contains(request.id)

        return HStack(spacing: 12) {
            AvatarView(urlString: request.profile.avatarUrl, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.profile.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray900)
                    .lineLimit(1)
                Text("@\(request.profile.username)")
                    .font(.system(size: 13))
                    .foregroundColor(.gray500)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button {
                    Task { await accept(request) }
                } label: {
                    Text("Accept")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.spotsTeal)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button, style: .continuous))
                }
                .disabled(isBusy)

                Button {
                    Task { await reject(request) }
                } label: {
                    Text("Reject")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray700)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.gray100)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button, style: .continuous))
                }
                .disabled(isBusy)
            }
            .opacity(isBusy ? 0.5 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.gray400)
            Text("No pending requests")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.gray900)
            Text("When someone asks to follow you, they'll show up here.")
                .font(.system(size: 14))
                .foregroundColor(.gray500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            requests = try await FollowService.shared.pendingRequests()
        } catch {
            errorMessage = "Couldn't load requests. \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func accept(_ request: PendingRequest) async {
        pendingActionIds.insert(request.id)
        defer { pendingActionIds.remove(request.id) }
        do {
            try await FollowService.shared.acceptRequest(from: request.profile.id)
            requests.removeAll { $0.id == request.id }
            onChanged?()
        } catch {
            errorMessage = "Couldn't accept request. \(error.localizedDescription)"
        }
    }

    private func reject(_ request: PendingRequest) async {
        pendingActionIds.insert(request.id)
        defer { pendingActionIds.remove(request.id) }
        do {
            try await FollowService.shared.rejectRequest(from: request.profile.id)
            requests.removeAll { $0.id == request.id }
            onChanged?()
        } catch {
            errorMessage = "Couldn't reject request. \(error.localizedDescription)"
        }
    }
}
