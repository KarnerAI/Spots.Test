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
    var initialSearchMode: SearchMode = .spots

    @EnvironmentObject var locationSavingVM: LocationSavingViewModel
    @State private var searchQuery: String = ""
    @State private var searchMode: SearchMode
    @State private var searchTask: Task<Void, Never>?
    @StateObject private var locationManager = LocationManager()
    @State private var autocompleteResults: [PlaceAutocompleteResult] = []
    @State private var isLoadingPlaces: Bool = false
    @State private var placesError: String?
    @State private var selectedSpotForSaving: PlaceAutocompleteResult?

    // User search state (backed by ProfileService.searchUsers + FollowService).
    @State private var userResults: [UserProfile] = []
    @State private var isLoadingUsers: Bool = false
    @State private var usersError: String?
    @State private var userRelationships: [UUID: FollowRelationship] = [:]
    @State private var followActionInFlight: Set<UUID> = []
    @State private var presentedUserProfileId: UUID?

    init(
        onSelectSpot: @escaping (String) -> Void,
        onFiltersClick: (() -> Void)? = nil,
        recentSpots: [SpotResult] = [],
        initialSearchMode: SearchMode = .spots
    ) {
        self.onSelectSpot = onSelectSpot
        self.onFiltersClick = onFiltersClick
        self.recentSpots = recentSpots
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
                    
                    // Search Input (unified spec: 15pt, gray100)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundColor(.gray400)
                        
                        TextField("Search here", text: $searchQuery)
                            .font(.system(size: 15))
                            .foregroundColor(.gray900)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.gray100)
                    .cornerRadius(CornerRadius.small)
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
            
            // MARK: - List Picker Overlay
            if selectedSpotForSaving != nil {
                // Dimmed background - tap to dismiss
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedSpotForSaving = nil
                        }
                    }
                    .transition(.opacity)
            }
            
            if let spot = selectedSpotForSaving {
                ListPickerView(
                    spotData: spot,
                    viewModel: locationSavingVM,
                    onDismiss: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedSpotForSaving = nil
                        }
                    },
                    onSaveComplete: {
                        dismiss()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedSpotForSaving != nil)
        .transition(.move(edge: .trailing))
        .onAppear {
            locationManager.requestLocationPermission()
            Task {
                await locationSavingVM.loadUserLists()
            }
        }
        .sheet(item: Binding(
            get: { presentedUserProfileId.map(IdentifiableUUID.init) },
            set: { presentedUserProfileId = $0?.id }
        )) { wrapper in
            NavigationStack {
                UserProfileView(userId: wrapper.id)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { presentedUserProfileId = nil }
                        }
                    }
            }
            .onDisappear {
                // Refresh the relationship pill in case the user followed/unfollowed inside the sheet.
                Task {
                    if let updated = try? await FollowService.shared.relationship(with: wrapper.id, forceRefresh: true) {
                        await MainActor.run { userRelationships[wrapper.id] = updated }
                    }
                }
            }
        }
    }

    private struct IdentifiableUUID: Identifiable {
        let id: UUID
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
        VStack(spacing: 12) {
            Spacer().frame(height: 32)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.gray400)
            Text("Search for people")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.gray900)
            Text("Type a name or @username to find someone to follow.")
                .font(.system(size: 13))
                .foregroundColor(.gray500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
            } else if autocompleteResults.isEmpty {
                emptyStateView(message: "No spots found")
            } else {
                ForEach(autocompleteResults) { result in
                    autocompleteResultRow(result: result)
                }
            }
        }
        .padding(.top, 8)
    }

    private var searchResultsUsersView: some View {
        VStack(spacing: 0) {
            if isLoadingUsers && userResults.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else if let usersError, userResults.isEmpty {
                emptyStateView(message: usersError)
            } else if userResults.isEmpty {
                emptyStateView(message: "No users found")
            } else {
                ForEach(userResults) { profile in
                    userRow(profile: profile)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - User Row

    private func userRow(profile: UserProfile) -> some View {
        let relationship = userRelationships[profile.id] ?? .none
        let isBusy = followActionInFlight.contains(profile.id)

        return Button {
            presentedUserProfileId = profile.id
        } label: {
            HStack(spacing: 12) {
                // Avatar
                AsyncImage(url: profile.avatarUrl.flatMap(URL.init(string:))) { phase in
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
                    HStack(spacing: 4) {
                        Text(profile.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray900)
                            .lineLimit(1)
                        if profile.isPrivate {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.gray400)
                        }
                    }

                    Text("@\(profile.username)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray500)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Follow Button
                followButton(for: profile, relationship: relationship, isBusy: isBusy)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(Color(red: 0.98, green: 0.98, blue: 0.98))
                    .frame(height: 0.5),
                alignment: .bottom
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func followButton(for profile: UserProfile, relationship: FollowRelationship, isBusy: Bool) -> some View {
        switch relationship {
        case .isSelf:
            EmptyView()
        case .none, .followsYou:
            followPillButton(label: "Follow", primary: true, isBusy: isBusy) {
                Task { await tapFollow(profile: profile) }
            }
        case .requested:
            followPillButton(label: "Requested", primary: false, isBusy: isBusy) {
                Task { await tapUnfollow(profile: profile) }
            }
        case .following, .mutual:
            followPillButton(label: relationship == .mutual ? "Friends" : "Following", primary: false, isBusy: isBusy) {
                Task { await tapUnfollow(profile: profile) }
            }
        }
    }

    private func followPillButton(label: String, primary: Bool, isBusy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(primary ? .white : .gray700)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(primary ? Color.spotsTeal : Color(red: 0.95, green: 0.95, blue: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
                .opacity(isBusy ? 0.5 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isBusy)
        .frame(minWidth: 80, minHeight: 44)
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
            // For users mode, hit Supabase via ProfileService.searchUsers
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                if !Task.isCancelled {
                    await performUserSearch(query: query)
                }
            }
        }
    }

    @MainActor
    private func performUserSearch(query: String) async {
        isLoadingUsers = true
        usersError = nil
        do {
            let results = try await ProfileService.shared.searchUsers(query: query, limit: 25)
            userResults = results
            await loadRelationships(for: results.map(\.id))
        } catch {
            usersError = "Couldn't search users. \(error.localizedDescription)"
            userResults = []
        }
        isLoadingUsers = false
    }

    private func loadRelationships(for userIds: [UUID]) async {
        // Fan out — small N (search limit 25) so per-user calls are fine here.
        // A batch RPC is a future optimization once user search becomes hot.
        await withTaskGroup(of: (UUID, FollowRelationship?).self) { group in
            for id in userIds {
                group.addTask {
                    let relationship = try? await FollowService.shared.relationship(with: id)
                    return (id, relationship)
                }
            }
            for await (id, relationship) in group {
                if let relationship {
                    await MainActor.run { userRelationships[id] = relationship }
                }
            }
        }
    }

    @MainActor
    private func tapFollow(profile: UserProfile) async {
        followActionInFlight.insert(profile.id)
        defer { followActionInFlight.remove(profile.id) }
        do {
            let status = try await FollowService.shared.follow(userId: profile.id)
            userRelationships[profile.id] = (status == .accepted) ? .following : .requested
        } catch {
            usersError = "Couldn't follow @\(profile.username). \(error.localizedDescription)"
        }
    }

    @MainActor
    private func tapUnfollow(profile: UserProfile) async {
        followActionInFlight.insert(profile.id)
        defer { followActionInFlight.remove(profile.id) }
        do {
            try await FollowService.shared.unfollow(userId: profile.id)
            userRelationships[profile.id] = try await FollowService.shared.relationship(with: profile.id, forceRefresh: true)
        } catch {
            usersError = "Couldn't update follow. \(error.localizedDescription)"
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
            // Dismiss keyboard so the Save to Spots sheet is fully visible (matches bookmark flow)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        ]
    )
    .environmentObject(LocationSavingViewModel())
}

