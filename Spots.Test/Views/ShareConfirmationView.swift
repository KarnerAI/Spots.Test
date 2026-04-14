//
//  ShareConfirmationView.swift
//  Spots.Test
//
//  Created for Share Extension feature
//

import SwiftUI

struct ShareConfirmationView: View {
    let places: [PlaceAutocompleteResult]
    let onSave: ([PlaceAutocompleteResult], Set<String>) async throws -> Int
    let onCancel: () -> Void
    
    @State private var selectedPlaceIds: Set<String> = []
    @State private var existingPlaceIds: Set<String> = []
    @State private var isLoadingExisting = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    private let locationSavingService = LocationSavingService.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                if showSuccess {
                    successView
                } else {
                    mainView
                }
            }
            .navigationTitle("Import Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .task {
            await checkExistingPlaces()
        }
    }
    
    private var mainView: some View {
        VStack(spacing: 0) {
            // Header with select all/deselect all
            if !places.isEmpty {
                HStack {
                    Button(action: {
                        if selectedPlaceIds.count == places.count {
                            selectedPlaceIds.removeAll()
                        } else {
                            selectedPlaceIds = Set(places.map { $0.placeId })
                        }
                    }) {
                        Text(selectedPlaceIds.count == places.count ? "Deselect All" : "Select All")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Text("\(selectedPlaceIds.count) of \(places.count) selected")
                        .font(.system(size: 15))
                        .foregroundColor(.gray600)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                
                Divider()
            }
            
            // Places list
            if isLoadingExisting {
                ProgressView("Checking existing places...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else if places.isEmpty {
                emptyStateView
            } else {
                placesListView
            }
            
            // Save button
            if !places.isEmpty && !isLoadingExisting {
                VStack(spacing: 0) {
                    Divider()
                    
                    Button(action: {
                        Task {
                            await savePlaces()
                        }
                    }) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Save \(selectedPlaceIds.count) spot\(selectedPlaceIds.count == 1 ? "" : "s")")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(selectedPlaceIds.isEmpty ? Color.gray300 : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(selectedPlaceIds.isEmpty || isSaving)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemBackground))
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }
    
    private var placesListView: some View {
        List {
            ForEach(places) { place in
                PlaceSelectionRow(
                    place: place,
                    isSelected: selectedPlaceIds.contains(place.placeId),
                    isExisting: existingPlaceIds.contains(place.placeId),
                    onToggle: {
                        if selectedPlaceIds.contains(place.placeId) {
                            selectedPlaceIds.remove(place.placeId)
                        } else {
                            selectedPlaceIds.insert(place.placeId)
                        }
                    }
                )
            }
        }
        .listStyle(PlainListStyle())
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray400)
            
            Text("No places found")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.gray500)
            
            Text("We couldn't find any places in the shared content")
                .font(.system(size: 15))
                .foregroundColor(.gray400)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("Saved Successfully!")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.gray900)
            
            Text("\(selectedPlaceIds.count) spot\(selectedPlaceIds.count == 1 ? "" : "s") added to your bucket list")
                .font(.system(size: 16))
                .foregroundColor(.gray600)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Actions
    
    private func checkExistingPlaces() async {
        isLoadingExisting = true
        
        do {
            let placeIds = places.map { $0.placeId }
            existingPlaceIds = try await locationSavingService.checkPlacesInBucketlist(placeIds)
            
            // Pre-select all places that aren't already in bucketlist
            selectedPlaceIds = Set(places.filter { !existingPlaceIds.contains($0.placeId) }.map { $0.placeId })
        } catch {
            errorMessage = "Failed to check existing places: \(error.localizedDescription)"
            print("Error checking existing places: \(error)")
            // Still allow user to proceed
            selectedPlaceIds = Set(places.map { $0.placeId })
        }
        
        isLoadingExisting = false
    }
    
    private func savePlaces() async {
        guard !selectedPlaceIds.isEmpty else { return }
        
        isSaving = true
        errorMessage = nil
        
        do {
            let savedCount = try await onSave(places, selectedPlaceIds)
            if savedCount > 0 {
                // Show success briefly, then close
                showSuccess = true
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                onCancel()
            } else {
                errorMessage = "Failed to save places. Please try again."
            }
        } catch {
            errorMessage = "Error saving places: \(error.localizedDescription)"
            print("Error saving places: \(error)")
        }
        
        isSaving = false
    }
}

struct PlaceSelectionRow: View {
    let place: PlaceAutocompleteResult
    let isSelected: Bool
    let isExisting: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .blue : .gray400)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Place info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(place.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray900)
                        .lineLimit(2)
                    
                    if isExisting {
                        Text("Already saved")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray600)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray200)
                            .cornerRadius(8)
                    }
                }
                
                Text(place.address)
                    .font(.system(size: 14))
                    .foregroundColor(.gray600)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}

