//
//  ListDetailView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 2/22/26.
//

import SwiftUI
import GoogleMaps
import CoreLocation

// MARK: - Supporting Types

enum ListDetailMode {
    case singleList(UserList)
    case allSpots
}

enum SpotSortOrder: String, CaseIterable {
    case dateNewest = "Date Added (Newest)"
    case dateOldest = "Date Added (Oldest)"
    case nameAZ     = "Name (A–Z)"
    case nameZA     = "Name (Z–A)"
}

enum ListViewStyle {
    case list, map
}

// MARK: - List Detail View

struct ListDetailView: View {
    let title: String
    let mode: ListDetailMode

    @State private var spots: [SpotWithMetadata] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOrder: SpotSortOrder = .dateNewest
    @State private var viewStyle: ListViewStyle = .list
    @State private var showSortDialog = false

    // Map state
    @State private var cameraPosition: GMSCameraPosition? = nil
    @State private var markers: [GMSMarker] = []
    @State private var showUserLocation = true
    @State private var forceCameraUpdate = false
    @State private var mapView: GMSMapView? = nil
    @State private var selectedSpot: SpotWithMetadata? = nil
    @State private var markerIconCache: [String: UIImage] = [:]
    @EnvironmentObject var locationSavingVM: LocationSavingViewModel
    @State private var spotForSaving: NearbySpot? = nil
    @StateObject private var locationManager = LocationManager()
    @State private var spotToOpenInMaps: NearbySpot? = nil
    @State private var shouldCenterWhenLocationArrives = false

    // Cached derived data (updated only when spots, searchText, or sortOrder change)
    @State private var cachedSpotListTypeMap: [String: ListType] = [:]
    @State private var cachedFilteredAndSortedSpots: [SpotWithMetadata] = []

    // MARK: - Computed (delegate to cache)
    private var spotListTypeMap: [String: ListType] { cachedSpotListTypeMap }
    private var filteredAndSortedSpots: [SpotWithMetadata] { cachedFilteredAndSortedSpots }

    private func updateCachedSpots() {
        cachedSpotListTypeMap = Dictionary(
            uniqueKeysWithValues: spots.compactMap { s in
                s.listTypes.first.map { (s.spot.placeId, $0) }
            }
        )
        let filtered = searchText.isEmpty
            ? spots
            : spots.filter { $0.spot.name.localizedCaseInsensitiveContains(searchText) }
        cachedFilteredAndSortedSpots = filtered.sorted { a, b in
            switch sortOrder {
            case .dateNewest: return a.savedAt > b.savedAt
            case .dateOldest: return a.savedAt < b.savedAt
            case .nameAZ:     return a.spot.name.localizedCaseInsensitiveCompare(b.spot.name) == .orderedAscending
            case .nameZA:     return a.spot.name.localizedCaseInsensitiveCompare(b.spot.name) == .orderedDescending
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            controlsRow

            Divider()

            Group {
                if isLoading {
                    Spacer()
                    ProgressView()
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if let errorMessage {
                    Spacer()
                    errorView(errorMessage)
                    Spacer()
                } else {
                    switch viewStyle {
                    case .list: listContent
                    case .map:  mapContent
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    // TODO: Share
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }

                Button {
                    // TODO: Filter
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
            }
        }
        .confirmationDialog("Sort by", isPresented: $showSortDialog, titleVisibility: .visible) {
            ForEach(SpotSortOrder.allCases, id: \.self) { order in
                Button(order.rawValue) { sortOrder = order }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: locationManager.location) { _, newLocation in
            guard shouldCenterWhenLocationArrives, let location = newLocation else { return }
            shouldCenterWhenLocationArrives = false
            centerMapOnLocation(location)
        }
        .onChange(of: spots) { _, _ in updateCachedSpots() }
        .onChange(of: searchText) { _, _ in updateCachedSpots() }
        .onChange(of: sortOrder) { _, _ in updateCachedSpots() }
        .task { await loadSpots() }
        .overlay {
            ZStack(alignment: .bottom) {
                if spotForSaving != nil {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                spotForSaving = nil
                            }
                        }
                        .transition(.opacity)
                }
                if let spot = spotForSaving {
                    ListPickerView(
                        spotData: spot.toPlaceAutocompleteResult(),
                        viewModel: locationSavingVM,
                        onDismiss: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                spotForSaving = nil
                            }
                        },
                        onSaveComplete: {
                            Task { await loadSpots() }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                spotForSaving = nil
                            }
                        }
                    )
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: spotForSaving != nil)
            .allowsHitTesting(spotForSaving != nil)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.gray400)

            TextField("Search spots...", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(.gray900)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.gray100)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.field, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Controls Row (view toggle + sort)

    private var controlsRow: some View {
        HStack {
            // List / Map toggle using SF Symbol icons
            HStack(spacing: 0) {
                Button {
                    viewStyle = .list
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16))
                        .frame(width: 40, height: 32)
                        .foregroundColor(viewStyle == .list ? .white : .gray500)
                        .background(viewStyle == .list ? Color.spotsTeal : Color.clear)
                }

                Button {
                    viewStyle = .map
                    buildMarkers()
                } label: {
                    Image(systemName: "map")
                        .font(.system(size: 16))
                        .frame(width: 40, height: 32)
                        .foregroundColor(viewStyle == .map ? .white : .gray500)
                        .background(viewStyle == .map ? Color.spotsTeal : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.gray200, lineWidth: 1)
            )

            Spacer()

            Button {
                showSortDialog = true
            } label: {
                HStack(spacing: 4) {
                    Text("Sort: \(sortOrder.shortLabel)")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.gray700)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.gray100)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - List Content

    private var listContent: some View {
        Group {
            if filteredAndSortedSpots.isEmpty {
                emptyState
            } else {
                List(filteredAndSortedSpots) { spotWithMetadata in
                    SavedSpotRow(spotWithMetadata: spotWithMetadata)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.visible)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Map Content

    private var mapContent: some View {
        ZStack(alignment: .bottom) {
                GoogleMapView(
                    cameraPosition: $cameraPosition,
                    markers: $markers,
                    showUserLocation: $showUserLocation,
                    forceCameraUpdate: $forceCameraUpdate,
                    onMapReady: { mv in
                        self.mapView = mv
                        fitCameraToMapView(mv)
                        locationManager.requestLocation()
                    },
                    onMarkerTapped: { marker in
                        if let spotWithMetadata = marker.userData as? SpotWithMetadata {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedSpot = spotWithMetadata
                            }
                        }
                    },
                    onMapTapped: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSpot = nil
                        }
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                // Locate-me button (top-right of card when card visible, else bottom-right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            locateMe()
                        } label: {
                            Image(systemName: "scope")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.gray900)
                                .frame(width: 44, height: 44)
                                .background(Color.white)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, selectedSpot != nil
                            ? 70 + 36 + 120 + 8
                            : 70 + 44)
                        .animation(.easeInOut(duration: 0.25), value: selectedSpot != nil)
                    }
                }

                // Spot detail card (slides up when a marker is tapped) — matches Explore SpotCardView
                if let spot = selectedSpot {
                    let nearby = spot.toNearbySpot()
                    SpotCardView(
                        spot: nearby,
                        spotListTypeMap: spotListTypeMap,
                        hasLoadedSavedPlaces: true,
                        onBookmarkTap: { spotForSaving = nearby },
                        onCardTap: { spotToOpenInMaps = nearby }
                    )
                    .frame(width: SpotCardView.cardWidth(for: UIScreen.main.bounds.width))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 70 + 36)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

            googleMapsPromptOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: spotToOpenInMaps != nil)
    }

    // MARK: - Open in Google Maps Overlay

    @ViewBuilder
    private var googleMapsPromptOverlay: some View {
        if let spot = spotToOpenInMaps {
            ZStack {
                // Blurred backdrop matching native action sheet scrim
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { spotToOpenInMaps = nil }
                    .transition(.opacity)

                VStack(spacing: 8) {
                    Spacer()

                    // Main action card (header + Open button)
                    VStack(spacing: 0) {
                        // Header: title + message
                        VStack(spacing: 2) {
                            Text("Open in Google Maps?")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Text(spot.name)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)

                        Divider()

                        // Open button
                        Button {
                            openInGoogleMaps(spot: spot)
                            spotToOpenInMaps = nil
                        } label: {
                            Text("Open")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 57)
                        }
                    }
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Cancel card (visually separate like native)
                    Button {
                        spotToOpenInMaps = nil
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 57)
                    }
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 70 + 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "mappin.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray300)

            Text(searchText.isEmpty ? "No spots yet" : "No results for \"\(searchText)\"")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.gray500)

            if searchText.isEmpty {
                Text("Save places to this list to see them here")
                    .font(.system(size: 15))
                    .foregroundColor(.gray400)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.gray400)
            Text("Failed to load spots")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.gray700)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.gray400)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Data Loading

    private func loadSpots() async {
        isLoading = true
        errorMessage = nil

        do {
            switch mode {
            case .singleList(let list):
                spots = try await LocationSavingService.shared.getSpotsInList(
                    listId: list.id,
                    listType: list.listType ?? .starred
                )
            case .allSpots:
                let service = LocationSavingService.shared
                let starredList = try await service.getListByType(.starred)
                let favoritesList = try await service.getListByType(.favorites)
                let bucketList = try await service.getListByType(.bucketList)

                var allPlaces: [SpotWithMetadata] = []
                if let id = starredList?.id { allPlaces += try await service.getSpotsInList(listId: id, listType: .starred) }
                if let id = favoritesList?.id { allPlaces += try await service.getSpotsInList(listId: id, listType: .favorites) }
                if let id = bucketList?.id { allPlaces += try await service.getSpotsInList(listId: id, listType: .bucketList) }

                // Deduplicate by placeId, union listTypes, keep most recent savedAt
                var unique: [String: SpotWithMetadata] = [:]
                for place in allPlaces {
                    if let existing = unique[place.spot.placeId] {
                        unique[place.spot.placeId] = SpotWithMetadata(
                            spot: existing.spot,
                            savedAt: max(existing.savedAt, place.savedAt),
                            listTypes: existing.listTypes.union(place.listTypes)
                        )
                    } else {
                        unique[place.spot.placeId] = place
                    }
                }
                spots = Array(unique.values).sorted { $0.savedAt > $1.savedAt }
            }
            buildMarkers()
        } catch {
            errorMessage = error.localizedDescription
            print("⚠️ ListDetailView: Could not load spots: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - Map Helpers

    private func buildMarkers() {
        let validSpots = spots.filter { $0.spot.latitude != nil && $0.spot.longitude != nil }
        let newMarkers = validSpots.map { spotWithMetadata -> GMSMarker in
            let spot = spotWithMetadata.spot
            let marker = GMSMarker(
                position: CLLocationCoordinate2D(
                    latitude: spot.latitude!,
                    longitude: spot.longitude!
                )
            )
            marker.title = spot.name
            marker.snippet = spot.address
            marker.userData = spotWithMetadata
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            marker.icon = MarkerIconHelper.iconForListTypes(
                spotWithMetadata.listTypes,
                cache: &markerIconCache
            )
            return marker
        }
        markers = newMarkers

        // If the map is already visible, fit immediately; otherwise onMapReady will handle it.
        if let mv = mapView {
            fitCameraToMapView(mv)
        }
    }

    private func fitCameraToMapView(_ mv: GMSMapView) {
        guard !markers.isEmpty else { return }

        if markers.count == 1, let first = markers.first {
            mv.animate(to: GMSCameraPosition.camera(
                withLatitude: first.position.latitude,
                longitude: first.position.longitude,
                zoom: 14
            ))
            return
        }

        var bounds = GMSCoordinateBounds()
        for marker in markers {
            bounds = bounds.includingCoordinate(marker.position)
        }
        mv.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 60))
    }

    private func centerMapOnLocation(_ location: CLLocation) {
        cameraPosition = GMSCameraPosition.camera(
            withLatitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            zoom: 15
        )
        forceCameraUpdate = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            forceCameraUpdate = false
        }
    }

    private func locateMe() {
        let bestLocation: CLLocation? = mapView?.myLocation ?? locationManager.location
        if let location = bestLocation {
            centerMapOnLocation(location)
        } else {
            shouldCenterWhenLocationArrives = true
            locationManager.requestLocationPermission()
            locationManager.requestLocation()
        }
    }

    private func openInGoogleMaps(spot: NearbySpot) {
        let urlString = "https://www.google.com/maps/search/?api=1&query=\(spot.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&query_place_id=\(spot.placeId)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - SpotSortOrder short label

private extension SpotSortOrder {
    var shortLabel: String {
        switch self {
        case .dateNewest: return "Recent"
        case .dateOldest: return "Oldest"
        case .nameAZ:     return "A–Z"
        case .nameZA:     return "Z–A"
        }
    }
}

// MARK: - Saved Spot Row

struct SavedSpotRow: View {
    let spotWithMetadata: SpotWithMetadata

    private var spot: Spot { spotWithMetadata.spot }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(spot.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.gray900)
                    .lineLimit(1)

                if let address = spot.address, !address.isEmpty {
                    Text(address)
                        .font(.system(size: 13))
                        .foregroundColor(.gray500)
                        .lineLimit(1)
                }

                if let city = spot.city, !city.isEmpty {
                    Text(city)
                        .font(.system(size: 12))
                        .foregroundColor(.gray400)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let urlString = spot.photoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    photoReferenceFallback
                }
            }
        } else {
            photoReferenceFallback
        }
    }

    @ViewBuilder
    private var photoReferenceFallback: some View {
        if let ref = spot.photoReference {
            GooglePlacesImageView(photoReference: ref, maxWidth: 120)
        } else {
            Rectangle()
                .fill(Color.gray200)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.gray400)
                        .font(.system(size: 18))
                )
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ListDetailView(title: "Starred", mode: .allSpots)
            .environmentObject(LocationSavingViewModel())
    }
}
