//
//  ListPickerView.swift
//  Spots.Test
//
//  Save-to-list sheet. Renders inside a native .sheet via ListPickerSheetModifier.
//  Shows all of the user's lists (system + custom), keyed by UUID. Multi-select
//  with checkmark; pre-seeded with the lists the spot is already in. Save diff
//  is delegated to LocationSavingViewModel.saveSpotToLists.
//

import SwiftUI

struct ListPickerView: View {
    let spotData: PlaceAutocompleteResult
    @ObservedObject var viewModel: LocationSavingViewModel
    var onDismiss: () -> Void
    var onSaveComplete: (() -> Void)? = nil

    @State private var selectedListIds: Set<UUID> = []
    @State private var listCounts: [UUID: Int] = [:]
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading && viewModel.userLists.isEmpty {
                loadingState
            } else {
                listContent
            }

            if let errorMessage {
                errorBanner(errorMessage)
            }

            saveBar
        }
        .background(Color.white)
        .task { await loadInitialData() }
    }

    // MARK: - Header

    private var header: some View {
        Text("Save to Spots")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.gray900)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
    }

    // MARK: - List rows

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.userLists) { list in
                    listRow(list)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func listRow(_ list: UserList) -> some View {
        let isSelected = selectedListIds.contains(list.id)
        let count = listCounts[list.id] ?? 0

        return HStack(spacing: 12) {
            Image(systemName: list.listType?.iconName ?? "list.bullet")
                .foregroundColor(list.listType?.iconColor ?? Color.spotsTeal)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.displayName)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.gray900)
                Text("Private list · \(count) \(count == 1 ? "place" : "places")")
                    .font(.system(size: 12))
                    .foregroundColor(.gray500)
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(isSelected ? Color.clear : Color.gray300, lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isSelected ? Color.spotsTeal : Color.clear))
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { toggle(list.id) }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: { Task { await handleSave() } }) {
                Text(isSaving ? "Saving" : "Save")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(SaveToListTealButtonStyle())
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .disabled(isSaving)
            .opacity(isSaving ? 0.6 : 1.0)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.red)
                .multilineTextAlignment(.leading)
            Spacer()
            Button { errorMessage = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray400)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.1))
    }

    // MARK: - Actions

    private func toggle(_ id: UUID) {
        if selectedListIds.contains(id) {
            selectedListIds.remove(id)
        } else {
            selectedListIds.insert(id)
        }
    }

    private func loadInitialData() async {
        isLoading = true
        await viewModel.loadUserLists()
        let ids = viewModel.userLists.map(\.id)

        async let countsTask: [UUID: Int] = viewModel.getSpotCounts(listIds: ids)
        let existing: [UUID]
        do {
            existing = try await viewModel.getListsContainingSpot(placeId: spotData.placeId)
        } catch {
            existing = []
        }

        listCounts = await countsTask
        selectedListIds = Set(existing)
        isLoading = false
    }

    private func handleSave() async {
        isSaving = true
        errorMessage = nil
        do {
            try await viewModel.saveSpotToLists(spotData: spotData, listIds: selectedListIds)
            onSaveComplete?()
            onDismiss()
        } catch {
            errorMessage = (error as NSError).localizedDescription.isEmpty
                ? "Failed to save. Please try again."
                : (error as NSError).localizedDescription
            isSaving = false
        }
    }
}

// MARK: - Button style

private struct SaveToListTealButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? Color.spotsTealActive : Color.spotsTeal)
            )
    }
}
