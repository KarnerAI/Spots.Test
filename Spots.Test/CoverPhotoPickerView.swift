//
//  CoverPhotoPickerView.swift
//  Spots.Test
//
//  Sheet that lets the user pick a cover photo from the top Unsplash results
//  for their most explored city. The selected URL is persisted to the profiles
//  table and synced to auth metadata.
//

import SwiftUI

struct CoverPhotoPickerView: View {
    let city: String
    let userId: UUID
    /// Called with the chosen URL after the selection is persisted.
    let onSelect: (String) -> Void

    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var photoURLs: [String] = []
    @State private var isLoading = true
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if photoURLs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 44))
                            .foregroundColor(.gray400)
                        Text("No photos found for \(city)")
                            .font(.system(size: 15))
                            .foregroundColor(.gray500)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your most explored city is \(city)! Pick a cover photo that represents it.")
                                .font(.system(size: 14))
                                .foregroundColor(.gray500)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)

                            VStack(spacing: 12) {
                                ForEach(photoURLs, id: \.self) { urlString in
                                    photoTile(urlString: urlString)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .navigationTitle(city)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
        }
        .task {
            photoURLs = await UnsplashService.shared.fetchCoverPhotoURLs(for: city, count: 3)
            isLoading = false
        }
    }

    private func photoTile(urlString: String) -> some View {
        AsyncImage(url: URL(string: urlString)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Rectangle()
                    .fill(Color.gray200)
                    .overlay(
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.gray400)
                    )
            default:
                Rectangle()
                    .fill(Color.gray100)
                    .overlay(ProgressView())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .clipped()
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .opacity(isSaving ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { selectPhoto(urlString) }
    }

    private func selectPhoto(_ urlString: String) {
        guard !isSaving else { return }
        isSaving = true

        Task {
            do {
                try await ProfileService.shared.updateCoverPhoto(userId: userId, url: urlString)
                await ProfileService.shared.syncAuthMetadata(
                    firstName: viewModel.currentUserFirstName,
                    lastName: viewModel.currentUserLastName,
                    username: viewModel.currentUserUsername,
                    avatarUrl: viewModel.currentUserAvatarUrl,
                    coverPhotoUrl: urlString
                )
                viewModel.refreshProfile()
                onSelect(urlString)
                await MainActor.run { dismiss() }
            } catch {
                print("❌ CoverPhotoPickerView: Failed to save cover photo: \(error)")
                await MainActor.run { isSaving = false }
            }
        }
    }
}
