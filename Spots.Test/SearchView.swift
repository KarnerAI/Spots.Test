//
//  SearchView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

// MARK: - Data Models

struct SpotResult: Identifiable {
    let id: String
    let name: String
    let address: String
    let icon: String?
    let status: String?
    let type: SpotType?
    let placeId: String? // Google Place ID for future place detail lookups
    
    enum SpotType {
        case recent
        case saved
    }
}

struct UserResult: Identifiable {
    let id: String
    let name: String
    let username: String
    let avatar: String
    var isFollowing: Bool
    let mutualFriends: Int?
}

enum SearchMode {
    case spots
    case users
}

// MARK: - SearchView

struct SearchView: View {
    @Environment(\.dismiss) var dismiss
    
    let onSelectSpot: (String) -> Void
    let onFiltersClick: (() -> Void)?
    
    var recentSpots: [SpotResult] = []
    var recentUsers: [UserResult] = []
    var searchResults: (spots: [SpotResult], users: [UserResult]) = ([], [])
    var onSearch: ((String, SearchMode) -> Void)?
    var onUserFollow: ((String, Bool) -> Void)?
    var initialSearchMode: SearchMode = .spots
    
    @State private var searchQuery: String = ""
    @State private var searchMode: SearchMode
    @State private var followStates: [String: Bool] = [:]
    @State private var searchTask: Task<Void, Never>?
    @StateObject private var locationManager = LocationManager()
    @State private var autocompleteResults: [PlaceAutocompleteResult] = []
    @State private var isLoadingPlaces: Bool = false
    @State private var placesError: String?
    @StateObject private var locationSavingVM = LocationSavingViewModel()
    @State private var selectedSpotForSaving: PlaceAutocompleteResult?
    
    init(
        onSelectSpot: @escaping (String) -> Void,
        onFiltersClick: (() -> Void)? = nil,
        recentSpots: [SpotResult] = [],
        recentUsers: [UserResult] = [],
        searchResults: (spots: [SpotResult], users: [UserResult]) = ([], []),
        onSearch: ((String, SearchMode) -> Void)? = nil,
        onUserFollow: ((String, Bool) -> Void)? = nil,
        initialSearchMode: SearchMode = .spots
    ) {
        self.onSelectSpot = onSelectSpot
        self.onFiltersClick = onFiltersClick
        self.recentSpots = recentSpots
        self.recentUsers = recentUsers
        self.searchResults = searchResults
        self.onSearch = onSearch
        self.onUserFollow = onUserFollow
        self.initialSearchMode = initialSearchMode
        _searchMode = State(initialValue: initialSearchMode)
    }
    
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search Header
                HStack(spacing: 12) {
                    // Back Button
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.gray900)
                            .frame(width: 44, height: 44)
                    }
                    
                    // Search Input
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundColor(.gray400)
                        
                        TextField("Search here", text: $searchQuery)
                            .font(.system(size: 14))
                            .foregroundColor(.gray900)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.95, green: 0.95, blue: 0.95))
                    .cornerRadius(8)
                    .onChange(of: searchQuery) { oldValue, newValue in
                        handleSearchQueryChange(newValue)
                    }
                    
                    // Filter Button (optional)
                    if let onFiltersClick = onFiltersClick {
                        Button(action: onFiltersClick) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.gray900)
                                .frame(width: 44, height: 44)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .fill(Color.gray200)
                        .frame(height: 0.5)
                        .offset(y: 0.25),
                    alignment: .bottom
                )
                
                // Tab Bar
                HStack(spacing: 0) {
                    // Spots Tab
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            searchMode = .spots
                        }
                    }) {
                        VStack(spacing: 0) {
                            Text("Spots")
                                .font(.system(size: 14, weight: searchMode == .spots ? .medium : .regular))
                                .foregroundColor(searchMode == .spots ? .gray900 : .gray400)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            
                            if searchMode == .spots {
                                Rectangle()
                                    .fill(Color.gray900)
                                    .frame(height: 2)
                            } else {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 2)
                            }
                        }
                    }
                    
                    // Users Tab
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            searchMode = .users
                        }
                    }) {
                        VStack(spacing: 0) {
                            Text("Users")
                                .font(.system(size: 14, weight: searchMode == .users ? .medium : .regular))
                                .foregroundColor(searchMode == .users ? .gray900 : .gray400)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            
                            if searchMode == .users {
                                Rectangle()
                                    .fill(Color.gray900)
                                    .frame(height: 2)
                            } else {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 2)
                            }
                        }
                    }
                }
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .fill(Color.gray200)
                        .frame(height: 0.5),
                    alignment: .bottom
                )
                
                // Content Area
                ScrollView {
                    if searchQuery.isEmpty {
                        // Recent Section
                        if searchMode == .spots {
                            recentSpotsView
                        } else {
                            recentUsersView
                        }
                    } else {
                        // Search Results
                        if searchMode == .spots {
                            searchResultsSpotsView
                        } else {
                            searchResultsUsersView
                        }
                    }
                }
            }
        }
        .transition(.move(edge: .trailing))
        .onAppear {
            locationManager.requestLocationPermission()
            Task {
                await locationSavingVM.loadUserLists()
            }
        }
        .sheet(item: $selectedSpotForSaving) { spot in
            ListPickerView(
                spotData: spot,
                viewModel: locationSavingVM,
                onSaveComplete: {
                    // Dismiss both the sheet and the SearchView to return to Explore
                    dismiss()
                }
            )
        }
    }
    
    // MARK: - Recent Spots View
    
    private var recentSpotsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray900)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                
                Spacer()
            }
            
            if recentSpots.isEmpty {
                emptyStateView(message: "No recent searches")
            } else {
                VStack(spacing: 0) {
                    ForEach(recentSpots) { spot in
                        recentSpotRow(spot: spot)
                    }
                }
            }
        }
    }
    
    private func recentSpotRow(spot: SpotResult) -> some View {
        Button(action: {
            onSelectSpot(spot.name)
            dismiss()
        }) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    if let icon = spot.icon {
                        Text(icon)
                            .font(.system(size: 20))
                            .frame(width: 40, height: 40)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.95, blue: 1.0), Color(red: 0.95, green: 0.9, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "clock")
                            .font(.system(size: 18))
                            .foregroundColor(.gray500)
                            .frame(width: 40, height: 40)
                            .background(Color(red: 0.95, green: 0.95, blue: 0.95))
                            .clipShape(Circle())
                    }
                }
                
                // Text Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.gray900)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    
                    if !spot.address.isEmpty {
                        Text(spot.address)
                            .font(.system(size: 13))
                            .foregroundColor(.gray500)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                    }
                    
                    if let status = spot.status {
                        Text(status)
                            .font(.system(size: 13))
                            .foregroundColor(.gray500)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Recent Users View
    
    private var recentUsersView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray900)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                
                Spacer()
            }
            
            if recentUsers.isEmpty {
                emptyStateView(message: "No recent users")
            } else {
                VStack(spacing: 0) {
                    ForEach(recentUsers) { user in
                        userRow(user: user)
                    }
                }
            }
        }
    }
    
    // MARK: - Search Results Views
    
    private var searchResultsSpotsView: some View {
        VStack(spacing: 0) {
            if isLoadingPlaces {
                VStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Text("Searching...")
                        .font(.system(size: 14))
                        .foregroundColor(.gray500)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else if let error = placesError {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else if autocompleteResults.isEmpty && searchResults.spots.isEmpty {
                emptyStateView(message: "No spots found")
            } else {
                // Show autocomplete results if available, otherwise show searchResults
                if !autocompleteResults.isEmpty {
                    ForEach(autocompleteResults) { result in
                        autocompleteResultRow(result: result)
                    }
                } else {
                    ForEach(searchResults.spots) { spot in
                        searchResultSpotRow(spot: spot)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
    
    private func searchResultSpotRow(spot: SpotResult) -> some View {
        Button(action: {
            onSelectSpot(spot.name)
            dismiss()
        }) {
            HStack(spacing: 12) {
                // Map Pin Icon
                ZStack {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.red)
                        .frame(width: 40, height: 40)
                        .background(Color(red: 1.0, green: 0.9, blue: 0.9))
                        .clipShape(Circle())
                }
                
                // Text Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.gray900)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    
                    Text(spot.address)
                        .font(.system(size: 13))
                        .foregroundColor(.gray500)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    
                    if let status = spot.status {
                        Text(status)
                            .font(.system(size: 13))
                            .foregroundColor(.gray500)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var searchResultsUsersView: some View {
        VStack(spacing: 0) {
            if searchResults.users.isEmpty {
                emptyStateView(message: "No users found")
            } else {
                ForEach(searchResults.users) { user in
                    userRow(user: user)
                }
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - User Row
    
    private func userRow(user: UserResult) -> some View {
        HStack(spacing: 12) {
            // Avatar
            AsyncImage(url: URL(string: user.avatar)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 48, height: 48)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Circle()
                        .fill(Color.gray200)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray400)
                        )
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray900)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(user.username)
                        .font(.system(size: 12))
                        .foregroundColor(.gray500)
                    
                    if let mutualFriends = user.mutualFriends {
                        Text("· \(mutualFriends) mutual friends")
                            .font(.system(size: 12))
                            .foregroundColor(.gray500)
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Follow Button
            Button(action: {
                let currentState = isUserFollowing(user.id, user.isFollowing)
                let newState = !currentState
                followStates[user.id] = newState
                onUserFollow?(user.id, newState)
            }) {
                Text(isUserFollowing(user.id, user.isFollowing) ? "Following" : "Follow")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isUserFollowing(user.id, user.isFollowing) ? .gray700 : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        isUserFollowing(user.id, user.isFollowing)
                            ? Color(red: 0.95, green: 0.95, blue: 0.95)
                            : Color.spotsTeal
                    )
                    .cornerRadius(16)
            }
            .frame(minWidth: 80, minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(
            Rectangle()
                .fill(Color(red: 0.98, green: 0.98, blue: 0.98))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
    
    // MARK: - Empty State
    
    private func emptyStateView(message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.gray500)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
    
    // MARK: - Helper Methods
    
    private func isUserFollowing(_ userId: String, _ defaultState: Bool) -> Bool {
        return followStates[userId] ?? defaultState
    }
    
    private func handleSearchQueryChange(_ query: String) {
        // Cancel previous search task
        searchTask?.cancel()
        
        // Clear previous results
        autocompleteResults = []
        placesError = nil
        
        // If query is empty, clear results
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        
        // If in spots mode, use Places API
        if searchMode == .spots {
            // Create new search task with debounce
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                
                if !Task.isCancelled {
                    await performPlacesSearch(query: query)
                }
            }
        } else {
            // For users mode, use existing search callback
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                
                if !Task.isCancelled {
                    onSearch?(query, searchMode)
                }
            }
        }
    }
    
    @MainActor
    private func performPlacesSearch(query: String) async {
        isLoadingPlaces = true
        placesError = nil
        
        let location = locationManager.getCurrentLocation()
        
        PlacesAPIService.shared.autocomplete(query: query, location: location) { result in
            Task { @MainActor in
                self.isLoadingPlaces = false
                
                switch result {
                case .success(let results):
                    self.autocompleteResults = results
                    self.placesError = nil
                case .failure(let error):
                    self.placesError = error.localizedDescription
                    self.autocompleteResults = []
                    print("Places API error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func autocompleteResultRow(result: PlaceAutocompleteResult) -> some View {
        Button(action: {
            // Show save sheet when tapping on the place
            selectedSpotForSaving = result
        }) {
            HStack(spacing: 12) {
                // Map Pin Icon
                ZStack {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.red)
                        .frame(width: 40, height: 40)
                        .background(Color(red: 1.0, green: 0.9, blue: 0.9))
                        .clipShape(Circle())
                }
                
                // Text Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.gray900)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    
                    Text(result.address)
                        .font(.system(size: 13))
                        .foregroundColor(.gray500)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                // Bookmark icon indicator
                Image(systemName: "bookmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color(red: 0.36, green: 0.69, blue: 0.72))
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    SearchView(
        onSelectSpot: { spotName in
            print("Selected: \(spotName)")
        },
        recentSpots: [
            SpotResult(
                id: "1",
                name: "Tripoli Bakery and Pizza - North Andover",
                address: "542 Turnpike St, North Andover, MA 01845",
                icon: nil,
                status: nil,
                type: .recent,
                placeId: nil
            )
        ],
        recentUsers: [
            UserResult(
                id: "1",
                name: "John Doe",
                username: "@john.doe",
                avatar: "https://via.placeholder.com/48",
                isFollowing: false,
                mutualFriends: 5
            )
        ]
    )
}

