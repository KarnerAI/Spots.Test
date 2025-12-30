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
    @Environment(\.dismiss) var dismiss
    var onSaveComplete: (() -> Void)? = nil
    
    @State private var selectedListIds: Set<UUID> = []
    @State private var listCounts: [UUID: Int] = [:]
    @State private var isLoadingCounts = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            
            // Bottom Sheet
            VStack(spacing: 0) {
                // Drag Handle
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.gray400)
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                
                // Header
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.gray900)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Save to Spots")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.gray900)
                    
                    Spacer()
                    
                    // Spacer for balance
                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(
                    Rectangle()
                        .fill(Color.gray200)
                        .frame(height: 0.5),
                    alignment: .bottom
                )
                
                // Lists - no ScrollView, just show the 3 lists
                VStack(spacing: 0) {
                    ForEach(viewModel.userLists) { list in
                        listRow(list: list)
                    }
                }
                
                // Error Message Display
                if let errorMessage = errorMessage {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.gray200)
                            .frame(height: 0.5)
                        
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 16))
                            
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            Button(action: {
                                self.errorMessage = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray400)
                                    .font(.system(size: 16))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.1))
                    }
                }
                
                // Save Button
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.gray200)
                        .frame(height: 0.5)
                    
                    Button(action: {
                        Task {
                            await handleSave()
                        }
                    }) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isSaving ? "Saving..." : "Save")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(red: 0.36, green: 0.69, blue: 0.72)) // #5DB0B8
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .disabled(isSaving || selectedListIds.isEmpty)
                    .opacity(isSaving || selectedListIds.isEmpty ? 0.6 : 1.0)
                }
                .background(Color.white)
            }
            .background(Color.white)
            .cornerRadius(24, corners: [.topLeft, .topRight])
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -2)
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.height > 100 {
                            dismiss()
                        }
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
        .transition(.move(edge: .bottom))
        .onAppear {
            Task {
                await loadInitialData()
            }
        }
    }
    
    private func listRow(list: UserList) -> some View {
        let isSelected = selectedListIds.contains(list.id)
        let count = listCounts[list.id] ?? 0
        
        return Button(action: {
            toggleList(list.id)
        }) {
            HStack(spacing: 12) {
                // Icon
                iconForList(list: list)
                    .frame(width: 24, height: 24)
                
                // Text Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.displayName)
                        .font(.system(size: 15, weight: .semibold))
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
                
                // Checkbox
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.clear : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(isSelected ? Color(red: 0.36, green: 0.69, blue: 0.72) : Color.clear)
                        )
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconForList(list: UserList) -> some View {
        if let listType = list.listType {
            switch listType {
            case .starred:
                return Image(systemName: "star")
                    .foregroundColor(.yellow)
                    .anyView
            case .favorites:
                return Image(systemName: "heart")
                    .foregroundColor(.red)
                    .anyView
            case .bucketList:
                return Image(systemName: "flag")
                    .foregroundColor(.blue)
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
                dismiss()
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

// Helper extension for type erasure
extension View {
    var anyView: AnyView {
        AnyView(self)
    }
}

