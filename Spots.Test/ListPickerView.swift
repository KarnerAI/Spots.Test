//
//  ListPickerView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

struct ListPickerView: View {
    let spotData: PlaceAutocompleteResult
    @ObservedObject var viewModel: LocationSavingViewModel
    var onDismiss: () -> Void
    var onSaveComplete: (() -> Void)? = nil
    
    @State private var selectedListIds: Set<UUID> = []
    @State private var listCounts: [UUID: Int] = [:]
    @State private var isLoadingCounts = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    // Layout constants
    private let topCornerRadius: CGFloat = 20
    private let dragHandleWidth: CGFloat = 40
    private let dragHandleHeight: CGFloat = 4
    private let listRowHeight: CGFloat = 68
    private let listVerticalPadding: CGFloat = 16
    private let fixedPartsHeight: CGFloat = 155
    private let minSheetHeight: CGFloat = 280

    var body: some View {
        GeometryReader { geometry in
            let bottomSafeArea = geometry.safeAreaInsets.bottom
            let screenHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let listContentHeight = CGFloat(viewModel.userLists.count) * listRowHeight + listVerticalPadding
            let contentDrivenHeight = fixedPartsHeight + listContentHeight
            let maxSheetHeight = min(screenHeight * 0.45, 420)
            let sheetHeight = max(minSheetHeight, min(maxSheetHeight, contentDrivenHeight))
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 0) {
                    // Drag handle
                    dragHandle
                    
                    // Header with close button
                    HStack {
                        Button(action: { onDismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.gray900)
                                .frame(width: 44, height: 44)
                        }

                        Spacer()

                        Text("Save to Spots")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.gray900)

                        Spacer()

                        Color.clear
                            .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 12)
                    
                    // Divider
                    Rectangle()
                        .fill(Color.gray200)
                        .frame(height: 1)

                    // List content
                    VStack(spacing: 0) {
                        ForEach(viewModel.userLists) { list in
                            listRow(list: list)
                        }
                    }
                    .padding(.vertical, 8)

                    // Error message if any
                    if let errorMessage = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 16))
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Button(action: { self.errorMessage = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray400)
                                    .font(.system(size: 16))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.1))
                    }

                    // Save button area
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.gray200)
                            .frame(height: 1)

                        Button(action: {
                            Task { await handleSave() }
                        }) {
                            Text(isSaving ? "Saving" : "Save")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(SaveToListTealButtonStyle())
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, max(bottomSafeArea, 16))
                        .disabled(isSaving || selectedListIds.isEmpty)
                        .opacity(isSaving || selectedListIds.isEmpty ? 0.6 : 1.0)
                    }
                }
                .frame(height: sheetHeight)
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: topCornerRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: topCornerRadius
                    )
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: -4)
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            Task { await loadInitialData() }
        }
    }
    
    // MARK: - Drag Handle
    
    private var dragHandle: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray300)
                .frame(width: dragHandleWidth, height: dragHandleHeight)
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func listRow(list: UserList) -> some View {
        let isSelected = selectedListIds.contains(list.id)
        let count = listCounts[list.id] ?? 0
        
        return Button(action: { toggleList(list.id) }) {
            HStack(spacing: 12) {
                iconForList(list: list)
                    .frame(width: 20, height: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.displayName)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.gray900)
                    
                    HStack(spacing: 4) {
                        Text("Private list")
                            .font(.system(size: 12))
                            .foregroundColor(.gray500)
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundColor(.gray500)
                        if isLoadingCounts {
                            Text("...")
                                .font(.system(size: 12))
                                .foregroundColor(.gray500)
                        } else {
                            Text("\(count) \(count == 1 ? "place" : "places")")
                                .font(.system(size: 12))
                                .foregroundColor(.gray500)
                        }
                    }
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.clear : Color.gray300, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(isSelected ? Color.spotsTeal : Color.clear)
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
        }
        .buttonStyle(ListRowButtonStyle())
    }
    
    private func iconForList(list: UserList) -> some View {
        if let listType = list.listType {
            switch listType {
            case .starred:
                return Image(systemName: "star.fill")
                    .foregroundColor(Color(red: 0.92, green: 0.70, blue: 0.03)) // #EAB308
                    .anyView
            case .favorites:
                return Image(systemName: "heart.fill")
                    .foregroundColor(Color(red: 0.94, green: 0.27, blue: 0.27)) // #EF4444
                    .anyView
            case .bucketList:
                return Image(systemName: "flag.fill")
                    .foregroundColor(Color(red: 0.23, green: 0.51, blue: 0.96)) // #3B82F6
                    .anyView
            }
        } else {
            return Image(systemName: "list.bullet")
                .foregroundColor(.gray500)
                .anyView
        }
    }
    
    private func toggleList(_ listId: UUID) {
        if selectedListIds.contains(listId) {
            selectedListIds.remove(listId)
        } else {
            selectedListIds.insert(listId)
        }
    }
    
    private func loadInitialData() async {
        // Load lists if not already loaded
        if viewModel.userLists.isEmpty {
            await viewModel.loadUserLists()
        }
        
        // Load counts for each list
        isLoadingCounts = true
        var counts: [UUID: Int] = [:]
        
        for list in viewModel.userLists {
            do {
                let count = try await viewModel.getSpotCount(listId: list.id)
                counts[list.id] = count
            } catch {
                print("Error loading count for list \(list.id): \(error)")
                counts[list.id] = 0
            }
        }
        
        listCounts = counts
        isLoadingCounts = false
        
        // Check which lists already contain this spot
        do {
            let existingListIds = try await viewModel.getListsContainingSpot(placeId: spotData.placeId)
            selectedListIds = Set(existingListIds)
        } catch {
            print("Error checking existing lists: \(error)")
        }
    }
    
    private func handleSave() async {
        guard !selectedListIds.isEmpty else { return }
        
        // #region agent log
        DebugLogger.log(
            runId: "pre-fix",
            hypothesisId: "H1",
            location: "ListPickerView.handleSave:entry",
            message: "Handle save tapped",
            data: [
                "placeId": spotData.placeId,
                "selectedCount": selectedListIds.count
            ]
        )
        // #endregion
        
        await MainActor.run {
            isSaving = true
            errorMessage = nil
        }
        
        // Get original lists that contained this spot
        let originalListIds: Set<UUID>
        do {
            let existing = try await viewModel.getListsContainingSpot(placeId: spotData.placeId)
            originalListIds = Set(existing)
        } catch {
            print("Error getting existing lists: \(error)")
            originalListIds = []
        }
        
        // Determine what changed
        let toAdd = selectedListIds.subtracting(originalListIds)
        let toRemove = originalListIds.subtracting(selectedListIds)
        
        // #region agent log
        DebugLogger.log(
            runId: "pre-fix",
            hypothesisId: "H1",
            location: "ListPickerView.handleSave:diff",
            message: "Computed list diffs",
            data: [
                "placeId": spotData.placeId,
                "toAddCount": toAdd.count,
                "toRemoveCount": toRemove.count
            ]
        )
        // #endregion
        
        do {
            print("Saving spot to \(toAdd.count) lists, removing from \(toRemove.count) lists")
            
            // Add to new lists
            for listId in toAdd {
                print("Adding spot to list \(listId)")
                try await viewModel.saveSpot(
                    placeId: spotData.placeId,
                    name: spotData.name,
                    address: spotData.address,
                    latitude: spotData.coordinate?.latitude,
                    longitude: spotData.coordinate?.longitude,
                    types: spotData.types,
                    toListId: listId
                )
            }
            
            // Remove from lists
            for listId in toRemove {
                print("Removing spot from list \(listId)")
                try await viewModel.removeSpot(placeId: spotData.placeId, fromListId: listId)
            }
            
            // Update counts for all affected lists
            for listId in toAdd.union(toRemove) {
                do {
                    let count = try await viewModel.getSpotCount(listId: listId)
                    await MainActor.run {
                        listCounts[listId] = count
                    }
                } catch {
                    print("Error updating count for list \(listId): \(error)")
                }
            }
            
            print("Successfully saved spot")
            
            // Call completion callback before dismissing
            await MainActor.run {
                onSaveComplete?()
            }
            
            // Close sheet on main thread
            await MainActor.run {
                onDismiss()
            }
        } catch {
            let errorMsg: String
            // Try to extract a meaningful error message
            if let nsError = error as NSError? {
                if let errorMessage = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                    errorMsg = errorMessage
                } else {
                    errorMsg = "Failed to save. Please try again."
                }
            } else {
                errorMsg = error.localizedDescription.isEmpty ? "Failed to save. Please try again." : error.localizedDescription
            }
            
            print("Error saving spot: \(error)")
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain), code: \(nsError.code)")
                print("Error userInfo: \(nsError.userInfo)")
            }
            
            // #region agent log
            let nsError = error as NSError
            DebugLogger.log(
                runId: "pre-fix",
                hypothesisId: "H4",
                location: "ListPickerView.handleSave:catch",
                message: "Save failed",
                data: [
                    "placeId": spotData.placeId,
                    "errorDomain": nsError.domain,
                    "errorCode": nsError.code,
                    "errorDescription": nsError.localizedDescription
                ]
            )
            // #endregion
            
            await MainActor.run {
                errorMessage = errorMsg
                isSaving = false
            }
        }
    }
}

// Helper extension for corner radius
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - List row style (gray-100 when pressed)
private struct ListRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.gray100 : Color.white)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Save button style (teal / darker teal when pressed)
private struct SaveToListTealButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? Color.spotsTealActive : Color.spotsTeal)
            )
    }
}

// Helper extension for type erasure
extension View {
    var anyView: AnyView {
        AnyView(self)
    }
}

// Preference Key to pass the size up
struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Minimum sheet height used when content height is not yet measured (avoids .medium detent).
enum ListPickerSheetLayout {
    static let initialHeight: CGFloat = 400
}
