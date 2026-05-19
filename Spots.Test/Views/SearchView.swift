//
//  SearchView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI
import CoreLocation

// MARK: - Data Models

enum SearchMode {
    case spots
    case users
}

enum ProfileRoute: Hashable {
    case user(UUID)
}

// MARK: - SearchView

struct SearchView: View {
    @Environment(\.dismiss) var dismiss

    /// Fires when a Spots-tab result is tapped. Caller is expected to dismiss
    /// the search view, pan the map to the place, and present the place card.
    /// Mirrors Google Maps' "search → drop into context" behavior; save flow
    /// is reached from the place card, not from the search row.
    let onSelectSpot: (PlaceAutocompleteResult) -> Void
    let onFiltersClick: (() -> Void)?

    var initialSearchMode: SearchMode = .spots

    @EnvironmentObject var locationSavingVM: LocationSavingViewModel
    @State private var searchQuery: String = ""
    @State private var searchMode: SearchMode
    @State private var searchTask: Task<Void, Never>?
    @StateObject private var locationManager = LocationManager()
    @StateObject private var searchVM = SearchViewModel()
    @State private var autocompleteResults: [PlaceAutocompleteResult] = []
    /// Drives the "Clear all recent searches?" confirmation dialog. Kept at
    /// view scope (vs. inside the Recent section) so the dialog's lifecycle
    /// survives the section collapsing once recents becomes empty.
    @State private var showClearConfirm: Bool = false
    @State private var isLoadingPlaces: Bool = false
    @State private var placesError: String?

    // User search state (backed by ProfileService.searchUsers + FollowService).
    @State private var userResults: [UserProfile] = []
    @State private var isLoadingUsers: Bool = false
    @State private var usersError: String?
    @State private var userRelationships: [UUID: FollowRelationship] = [:]
    @State private var followActionInFlight: Set<UUID> = []
    /// Currently-presented cancel-request confirmation, keyed by the profile
    /// whose pill was tapped. `nil` = no sheet visible. Lifted to view-scope
    /// (vs per-row state) because SwiftUI re-instantiates row Views on data
    /// changes; keeping the flag here survives those rebuilds.
    @State private var cancelRequestTarget: UserProfile?

    init(
        onSelectSpot: @escaping (PlaceAutocompleteResult) -> Void,
        onFiltersClick: (() -> Void)? = nil,
        initialSearchMode: SearchMode = .spots
    ) {
        self.onSelectSpot = onSelectSpot
        self.onFiltersClick = onFiltersClick
        self.initialSearchMode = initialSearchMode
        _searchMode = State(initialValue: initialSearchMode)
    }
    
    var body: some View {
        NavigationStack {
            content
                .navigationBarHidden(true)
                .navigationDestination(for: ProfileRoute.self) { route in
                    switch route {
                    case .user(let id):
                        UserProfileView(userId: id)
                    }
                }
                .confirmationDialog(
                    "Cancel follow request?",
                    isPresented: cancelRequestPresented,
                    titleVisibility: .visible,
                    presenting: cancelRequestTarget
                ) { profile in
                    Button("Cancel request", role: .destructive) {
                        let target = profile
                        cancelRequestTarget = nil
                        Task { await tapUnfollow(profile: target) }
                    }
                    Button("Keep waiting", role: .cancel) {
                        cancelRequestTarget = nil
                    }
                } message: { profile in
                    Text("You sent a request to follow @\(profile.username). They won't see it after you cancel.")
                }
        }
    }

    private var cancelRequestPresented: Binding<Bool> {
        Binding(
            get: { cancelRequestTarget != nil },
            set: { if !$0 { cancelRequestTarget = nil } }
        )
    }

    private var content: some View {
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
                
                // Category filter chips — only visible on the Spots tab's
                // pre-typing state. Filters Nearby in place; never touches Recent.
                if searchMode == .spots && searchQuery.isEmpty {
                    categoryChipsBar
                }

                // Content Area. Pre-typing Spots state uses a List so we get
                // native Section semantics and .swipeActions on Recent rows;
                // every other state stays a plain ScrollView.
                if searchMode == .spots && searchQuery.isEmpty {
                    discoveryList
                } else {
                    ScrollView {
                        if searchQuery.isEmpty {
                            // Users tab pre-typing state.
                            recentUsersView
                        } else if searchMode == .spots {
                            searchResultsSpotsView
                        } else {
                            searchResultsUsersView
                        }
                    }
                }
            }

        }
        .transition(.move(edge: .trailing))
        // Confirmation dialog for "Clear all recents". Attached at the
        // outermost content view so the dialog's presentation lifecycle is
        // independent of the Recent section's visibility — the section
        // collapses to nothing the moment the user confirms, and an
        // inside-the-section attachment would tear down mid-animation.
        .confirmationDialog(
            "Clear all recent searches?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                searchVM.clearRecents()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This can't be undone.")
        }
        .onAppear {
            locationManager.requestLocationPermission()
            Task {
                await locationSavingVM.loadUserLists()
            }
            // Nearby fetch fires as soon as we know the user's location.
            // First fix may already be available (cached); if not, the
            // onChange below picks up the next published value.
            searchVM.loadNearby(from: locationManager.getCurrentLocation())
            // Re-sync follow pills when returning from a pushed UserProfileView,
            // in case the user followed/unfollowed inside the detail screen.
            if !userResults.isEmpty {
                Task { await loadRelationships(for: userResults.map(\.id)) }
            }
        }
        .onChange(of: locationManager.location) { _, newLocation in
            // Refire nearby fetch when the location finally resolves
            // (or jumps materially) after the initial onAppear.
            if newLocation != nil && searchVM.nearbySpots.isEmpty {
                searchVM.loadNearby(from: newLocation)
            }
        }
    }

    // MARK: - Discovery (pre-typing) view — Recent + Nearby

    /// The pre-typing state of the Spots tab. A single `List` so Recent
    /// rows can use SwiftUI's native `.swipeActions` without the
    /// fixed-height-nested-List footgun (broken under Dynamic Type,
    /// gesture conflicts with an outer ScrollView). Section headers carry
    /// the section labels — "RECENT" (with a Clear button) and the
    /// dynamic "NEARBY NOW" / "NEARBY COFFEE" header.
    private var discoveryList: some View {
        List {
            if !searchVM.recents.isEmpty {
                Section {
                    ForEach(searchVM.recents) { ref in
                        recentRow(ref: ref)
                            .modifier(DiscoveryRowStyle())
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    searchVM.removeRecent(placeId: ref.placeId)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    recentSectionHeader
                        .modifier(DiscoveryHeaderStyle())
                }
            }

            Section {
                nearbyListRows
            } header: {
                nearbyHeaderRow
                    .modifier(DiscoveryHeaderStyle())
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .environment(\.defaultMinListRowHeight, 0)
    }

    /// "RECENT" section header with the trailing Clear button. 44pt hit
    /// target on the button via .frame(minHeight:) so it stays accessible
    /// even though the label is only 13pt.
    private var recentSectionHeader: some View {
        HStack {
            Text("RECENT")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(.gray500)
            Spacer()
            Button(action: { showClearConfirm = true }) {
                Text("Clear")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.spotsTeal)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    /// Renders the Nearby section's state machine as a sequence of List
    /// rows (location-denied prompt, loading indicator, error message,
    /// filtered empty state, or the populated list). Each branch applies
    /// the same DiscoveryRowStyle so backgrounds, insets, and separator
    /// suppression are consistent across every state.
    @ViewBuilder
    private var nearbyListRows: some View {
        let denied = locationManager.authorizationStatus == .denied
            || locationManager.authorizationStatus == .restricted
        if denied {
            locationDeniedRow
                .modifier(DiscoveryRowStyle())
        } else if searchVM.isShowingLoadingState {
            ProgressView()
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .modifier(DiscoveryRowStyle())
        } else if let error = searchVM.visibleError, searchVM.filteredNearby.isEmpty {
            VStack(spacing: 6) {
                Text("Couldn't load nearby spots")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray700)
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.gray500)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .modifier(DiscoveryRowStyle())
        } else if searchVM.filteredNearby.isEmpty {
            filteredEmptyRow
                .modifier(DiscoveryRowStyle())
        } else {
            ForEach(searchVM.filteredNearby) { spot in
                nearbyRow(spot: spot)
                    .modifier(DiscoveryRowStyle())
            }
        }
    }

    /// Nearby header. Includes a teal "Clear filter" affordance when a chip
    /// is active so the user has a discoverable way to reset without
    /// scrolling up to the chips bar. Rendered as the Nearby Section header
    /// inside `discoveryList`.
    private var nearbyHeaderRow: some View {
        HStack {
            Text(searchVM.nearbyHeader.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(.gray500)
            Spacer()
            if searchVM.activeFilter != nil {
                Button(action: { searchVM.setFilter(nil) }) {
                    Text("Clear filter")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.spotsTeal)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    /// Tap-target row prompting the user to enable location access in
    /// system Settings. Replaces the nearby list when permission is denied.
    private var locationDeniedRow: some View {
        Button(action: openSystemSettings) {
            HStack(spacing: 12) {
                Image(systemName: "location.slash")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.gray500)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable location to see nearby spots")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray900)
                    Text("Opens Settings")
                        .font(.system(size: 12))
                        .foregroundColor(.gray500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray400)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Inline row that takes the place of the nearby list when a category
    /// filter is active but no nearby spots match.
    private var filteredEmptyRow: some View {
        VStack(spacing: 6) {
            let label = searchVM.activeFilter?.displayName.lowercased() ?? "spots"
            Text("No \(label) spots nearby")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray700)
            Text("Try a different category, or widen the radius in filters.")
                .font(.system(size: 12))
                .foregroundColor(.gray500)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    /// Recent search row — red map pin glyph + name + address. Tapping
    /// re-enters the place-card flow via the existing onSelectSpot callback.
    private func recentRow(ref: RecentSpotRef) -> some View {
        Button(action: {
            let result = PlaceAutocompleteResult(
                placeId: ref.placeId,
                name: ref.name,
                address: ref.address
            )
            onSelectSpot(result)
            dismiss()
        }) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.spotsCoral)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray900)
                        .lineLimit(1)
                    if !ref.address.isEmpty {
                        Text(ref.address)
                            .font(.system(size: 12))
                            .foregroundColor(.gray500)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray400)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(
            Rectangle()
                .fill(Color.gray200)
                .frame(height: 0.5)
                .padding(.leading, 56),
            alignment: .bottom
        )
    }

    /// Nearby spot row — 32pt category-emoji circle, name, category·distance
    /// subtitle. Real photos are intentionally not fetched here — Google
    /// Places photo requests are billed per impression and Search opens
    /// frequently. Emoji glyphs convey category at a glance for free.
    private func nearbyRow(spot: NearbySpot) -> some View {
        Button(action: {
            searchVM.recordRecent(placeId: spot.placeId, name: spot.name, address: spot.address)
            onSelectSpot(spot.toPlaceAutocompleteResult())
            dismiss()
        }) {
            HStack(spacing: 12) {
                nearbyEmojiCircle(for: spot)

                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray900)
                        .lineLimit(1)

                    Text(nearbySubtitle(for: spot))
                        .font(.system(size: 12))
                        .foregroundColor(.gray500)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray400)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(
            Rectangle()
                .fill(Color.gray200)
                .frame(height: 0.5)
                .padding(.leading, 64),
            alignment: .bottom
        )
    }

    private func nearbySubtitle(for spot: NearbySpot) -> String {
        let distance = spot.formattedDistance
        if distance.isEmpty {
            return spot.category
        }
        return "\(spot.category) · \(distance)"
    }

    /// Subtitle for an autocomplete result row. Appends "· {distance}"
    /// when both the user location and the result's coordinate are known.
    /// Round 7 Text Search returns coordinates inline so this branch fires
    /// for every nearest-first result; trip-planning fallback results
    /// (Autocomplete + bias) still get coordinates via the existing
    /// sortResultsByDistance step before they reach the view.
    private func autocompleteSubtitle(for result: PlaceAutocompleteResult) -> String {
        guard let coord = result.coordinate,
              let userLocation = locationManager.getCurrentLocation() else {
            return result.address
        }
        let placeLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let meters = userLocation.distance(from: placeLocation)
        let distance = DistanceCalculator.formattedDistance(meters)
        if result.address.isEmpty { return distance }
        return "\(result.address) · \(distance)"
    }

    /// 32pt circular emoji glyph used as the leading element of each
    /// Nearby row. Re-uses PlaceTypeEmoji by synthesizing a single-element
    /// `types` array from NearbySpot.category (same trick NearbySpot.toSpot
    /// uses), falling back to a generic pin when nothing matches.
    private func nearbyEmojiCircle(for spot: NearbySpot) -> some View {
        let synthesizedType = spot.category
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        let glyph = PlaceTypeEmoji.emoji(for: [synthesizedType]) ?? "📍"
        return Text(glyph)
            .font(.system(size: 16))
            .frame(width: 32, height: 32)
            .background(Color.gray100)
            .clipShape(Circle())
    }

    // MARK: - Category Chips

    /// Horizontal pill chips between the tabs and the content area. "All"
    /// resets the filter (activeFilter == nil); tapping any other category
    /// toggles into single-select. Re-tapping the active chip also clears.
    private var categoryChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                allChipButton
                ForEach(SpotCategory.allCases) { category in
                    categoryChipButton(category: category)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color.gray100)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var allChipButton: some View {
        let isActive = searchVM.activeFilter == nil
        return Button(action: { searchVM.setFilter(nil) }) {
            HStack(spacing: 6) {
                Text("✦")
                    .font(.system(size: 13))
                Text("All")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isActive ? .white : .gray900)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isActive ? Color.spotsNavy : Color.gray100)
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func categoryChipButton(category: SpotCategory) -> some View {
        let isActive = searchVM.activeFilter == category
        return Button(action: {
            // Re-tapping the active chip clears the filter (a common iOS
            // affordance for single-select filters that doubles as a way out).
            searchVM.setFilter(isActive ? nil : category)
        }) {
            HStack(spacing: 6) {
                Text(category.emoji)
                    .font(.system(size: 13))
                Text(category.displayName)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isActive ? .white : .gray900)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isActive ? Color.spotsNavy : Color.gray100)
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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

        return HStack(spacing: 12) {
            NavigationLink(value: ProfileRoute.user(profile.id)) {
                HStack(spacing: 12) {
                    AvatarView(urlString: profile.avatarUrl, size: 48)

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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Follow Button — sibling of the NavigationLink so its tap is not swallowed.
            followButton(for: profile, relationship: relationship, isBusy: isBusy)
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

    @ViewBuilder
    private func followButton(for profile: UserProfile, relationship: FollowRelationship, isBusy: Bool) -> some View {
        switch relationship {
        case .isSelf:
            EmptyView()
        case .none, .followsYou:
            // Private profiles produce a pending follow row server-side, so the
            // pre-tap label reflects what the user is actually doing.
            followPillButton(label: profile.isPrivate ? "Request" : "Follow", primary: true, isBusy: isBusy) {
                Task { await tapFollow(profile: profile) }
            }
        case .requested:
            // Tap opens a confirm sheet (presented at the view level by
            // `cancelRequestTarget`) before retracting the pending request.
            followPillButton(label: "Requested", primary: false, isBusy: isBusy) {
                cancelRequestTarget = profile
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
            // Dismiss keyboard before transitioning back to the map.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            // Selecting a typed result is a real "search" — record it so the
            // Recent section reflects what the user actually visited.
            searchVM.recordRecent(placeId: result.placeId, name: result.name, address: result.address)
            onSelectSpot(result)
            dismiss()
        }) {
            HStack(spacing: 12) {
                // Same red pin glyph used by Recent rows. Earlier versions
                // wrapped this in a 40pt pink circle which made autocomplete
                // visually inconsistent with the rest of the screen — pin
                // style is now uniform across Recent and autocomplete.
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.spotsCoral)
                    .frame(width: 24)

                // Text Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray900)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)

                    Text(autocompleteSubtitle(for: result))
                        .font(.system(size: 12))
                        .foregroundColor(.gray500)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray400)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(
            Rectangle()
                .fill(Color.gray200)
                .frame(height: 0.5)
                .padding(.leading, 56),
            alignment: .bottom
        )
    }
}

// MARK: - List Styling Modifiers

/// Strips List's default row chrome — insets, separator, and grouped-style
/// background — so rows render edge-to-edge on a white surface, matching
/// the rest of the Search screen. Their visual dividers come from each
/// row's own `.overlay(Rectangle...)` rather than the List separator.
private struct DiscoveryRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.white)
    }
}

/// Section header styling — same insets/background treatment as rows so
/// the custom-padded HStack inside the header renders without an extra
/// margin layer from List's default header chrome. `textCase(nil)` keeps
/// our manual uppercase string as-is instead of List's default upcasing.
private struct DiscoveryHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.white)
            .textCase(nil)
    }
}

#Preview {
    SearchView(
        onSelectSpot: { result in
            print("Selected: \(result.name) (\(result.placeId))")
        }
    )
    .environmentObject(LocationSavingViewModel())
}

