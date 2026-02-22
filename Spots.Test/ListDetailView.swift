//
//  ListDetailView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 2/22/26.
//

import SwiftUI
import GoogleMaps

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
    @State private var showUserLocation = false
    @State private var forceCameraUpdate = false

    // MARK: - Computed

    private var filteredAndSortedSpots: [SpotWithMetadata] {
        let filtered = searchText.isEmpty
            ? spots
            : spots.filter { $0.spot.name.localizedCaseInsensitiveContains(searchText) }

        return filtered.sorted { a, b in
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
        .task { await loadSpots() }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray500)
                .font(.system(size: 15))

            TextField("Search spots...", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(.gray900)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.gray100)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        GoogleMapView(
            cameraPosition: $cameraPosition,
            markers: $markers,
            showUserLocation: $showUserLocation,
            forceCameraUpdate: $forceCameraUpdate,
            onMarkerTapped: { _ in }
        )
        .ignoresSafeArea(edges: .bottom)
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
                spots = try await LocationSavingService.shared.getAllSpots()
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
            return marker
        }
        markers = newMarkers
        fitCameraToMarkers()
    }

    private func fitCameraToMarkers() {
        guard markers.count > 1 else {
            if let first = markers.first {
                cameraPosition = GMSCameraPosition.camera(
                    withLatitude: first.position.latitude,
                    longitude: first.position.longitude,
                    zoom: 14
                )
                forceCameraUpdate = true
            }
            return
        }

        var bounds = GMSCoordinateBounds()
        for marker in markers {
            bounds = bounds.includingCoordinate(marker.position)
        }
        let update = GMSCameraUpdate.fit(bounds, withPadding: 60)
        // Store as a sentinel so GoogleMapView's updateUIView applies the fit
        cameraPosition = GMSCameraPosition.camera(withLatitude: 0, longitude: 0, zoom: 2)
        _ = update // GoogleMapView handles forceCameraUpdate via mapView.animate(with:)
        forceCameraUpdate = true
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
    }
}
