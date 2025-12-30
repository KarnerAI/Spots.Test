//
//  SavedSpotsView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

struct SavedSpotsView: View {
    let list: UserList
    @StateObject private var viewModel = LocationSavingViewModel()
    @State private var spots: [SpotWithMetadata] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if spots.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 48))
                        .foregroundColor(.gray400)
                    
                    Text("No spots saved yet")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.gray500)
                    
                    Text("Save places to this list to see them here")
                        .font(.system(size: 15))
                        .foregroundColor(.gray400)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .listRowSeparator(.hidden)
            } else {
                ForEach(spots) { spotWithMetadata in
                    SpotRow(spot: spotWithMetadata.spot)
                }
            }
        }
        .listStyle(PlainListStyle())
        .navigationTitle(list.displayName)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadSpots()
        }
    }
    
    private func loadSpots() async {
        isLoading = true
        errorMessage = nil
        
        do {
            spots = try await viewModel.getSpotsInList(listId: list.id)
        } catch {
            errorMessage = "Failed to load spots: \(error.localizedDescription)"
            print("Error loading spots: \(error)")
        }
        
        isLoading = false
    }
}

struct SpotRow: View {
    let spot: Spot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(spot.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.gray900)
                .lineLimit(2)
            
            if let address = spot.address {
                Text(address)
                    .font(.system(size: 13))
                    .foregroundColor(.gray500)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }
}

