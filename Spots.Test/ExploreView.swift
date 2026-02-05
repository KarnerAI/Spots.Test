//
//  ExploreView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI
import GoogleMaps

struct ExploreView: View {
    @ObservedObject var viewModel: MapViewModel
    @State private var showSearchView = false
    @State private var showFiltersPlaceholder = false
    @StateObject private var locationSavingVM = LocationSavingViewModel()
    @State private var mapView: GMSMapView?
    @State private var markers: [GMSMarker] = []
    
    // Bottom sheet state
    @State private var spotForSaving: NearbySpot? = nil
    @State private var spotToOpenInMaps: NearbySpot? = nil
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Full screen map
            GoogleMapView(
                cameraPosition: $viewModel.cameraPosition,
                markers: $markers,
                showUserLocation: .constant(true),
                forceCameraUpdate: $viewModel.forceCameraUpdate,
                onMapReady: { mapView in
                    self.mapView = mapView
                    viewModel.setupMap(mapView)
                    // Track initial camera position only on first open; when restoring we keep saved currentCameraPosition so onAppear can restore last view
                    if !viewModel.hasExploreAppearedBefore {
                        viewModel.currentCameraPosition = mapView.camera
                    }
                },
                onCameraChanged: { position in
                    // Update current camera position in ViewModel
                    viewModel.currentCameraPosition = position
                    // Handle camera changes if needed
                    let radius = viewModel.calculateRadius(for: position.zoom)
                    print("Map zoom: \(position.zoom), calculated radius: \(radius)m")
                },
                onMarkerTapped: { marker in
                    handleMarkerTap(marker)
                },
                onPOITapped: { placeId, name, location in
                    // Fetch POI details and show in carousel
                    Task {
                        await viewModel.fetchAndSelectPOI(placeId: placeId, name: name, location: location)
                    }
                },
                onMapTapped: {
                    // Clear selection when tapping empty map area
                    viewModel.deselectSpot()
                }
            )
            .ignoresSafeArea()
            
            // Floating search bar overlay
            VStack(spacing: 0) {
                // Search Bar with integrated filter
                HStack(spacing: 12) {
                    // Magnifying glass icon
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(.gray400)
                    
                    // Search text
                    Text("Search spots, friends...")
                        .font(.system(size: 16))
                        .foregroundColor(.gray400)
                    
                    Spacer()
                    
                    // Filter icon (integrated)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.gray900)
                        .onTapGesture {
                            showFiltersPlaceholder = true
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(24)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
                .onTapGesture {
                    showSearchView = true
                }
                .padding(.horizontal, 20) // ADJUSTABLE: Controls search bar width
                .padding(.top, 8)
                
                Spacer()
            }
            
            // Locate Me Button and location status - positioned above the bottom sheet
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    // Location status: show instantly whether user is located
                    Text(viewModel.currentLocation != nil ? "Located" : "Locating...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(viewModel.currentLocation != nil ? .secondary : .orange)
                    Button(action: {
                        viewModel.centerOnCurrentLocation()
                    }) {
                        Image(systemName: "scope")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.gray900)
                            .frame(width: 44, height: 44)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, 16)
                }
                .padding(.bottom, bottomSheetHeight + 70 + 16) // Position above bottom sheet + tab bar
            }
            
            // Bottom Sheet with Spots Carousel - anchored to bottom
            VStack {
                Spacer()
                
                SpotsBottomSheetView(
                    sheetState: $viewModel.sheetState,
                    spots: viewModel.displayedSpots,
                    isLoading: viewModel.isLoadingNearbySpots,
                    hasMorePages: viewModel.hasMorePages,
                    errorMessage: viewModel.nearbyErrorMessage,
                    onBookmarkTap: { spot in
                        spotForSaving = spot
                    },
                    onCardTap: { spot in
                        spotToOpenInMaps = spot
                    },
                    onLoadMore: {
                        Task {
                            await viewModel.loadMoreNearbySpots()
                        }
                    },
                    onRetry: {
                        Task {
                            await viewModel.fetchNearbySpots(refresh: true)
                        }
                    }
                )
                .padding(.bottom, 70) // Space for tab bar
            }
            
            // MARK: - List Picker Overlay
            if spotForSaving != nil {
                // Dimmed background - tap to dismiss
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
                        Task {
                            await viewModel.loadSavedPlaces()
                            updateMarkers()
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            spotForSaving = nil
                        }
                    }
                )
                .padding(.bottom, 70) // Keep sheet above tab bar so Save button stays visible
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: spotForSaving != nil)
        .onAppear {
            // Restore map to last camera only when returning from another tab in the same session (not on first open or after app was backgrounded)
            if viewModel.hasExploreAppearedBefore, let lastCamera = viewModel.currentCameraPosition {
                viewModel.cameraPosition = lastCamera
            }
            viewModel.hasExploreAppearedBefore = true
            // Load saved places and lists; nearby spots are fetched when location becomes available (MapViewModel)
            Task {
                await viewModel.loadSavedPlaces()
                await locationSavingVM.loadUserLists()
                updateMarkers()
            }
        }
        .onChange(of: viewModel.savedPlaces.count) { oldValue, newValue in
            updateMarkers()
        }
        .onChange(of: viewModel.nearbySpots) { oldValue, newValue in
            updateMarkers()
        }
        .onChange(of: viewModel.selectedSpot) { oldValue, newValue in
            updateMarkers()
        }
        .fullScreenCover(isPresented: $showSearchView) {
            SearchView(
                onSelectSpot: { spotName in
                    print("Selected spot: \(spotName)")
                    // Handle spot selection here
                },
                onFiltersClick: {
                    // Handle filters click here
                    print("Filters clicked")
                },
                recentSpots: [],
                recentUsers: [],
                searchResults: (spots: [], users: []),
                onSearch: { query, mode in
                    print("Search: \(query) in mode: \(mode)")
                    // Handle search here - fetch results and update searchResults
                },
                onUserFollow: { userId, isFollowing in
                    print("User \(userId) follow state: \(isFollowing)")
                    // Handle follow/unfollow here
                }
            )
        }
        .confirmationDialog(
            "Open in Google Maps?",
            isPresented: Binding(
                get: { spotToOpenInMaps != nil },
                set: { if !$0 { spotToOpenInMaps = nil } }
            ),
            titleVisibility: .visible,
            presenting: spotToOpenInMaps
        ) { spot in
            Button("Open") {
                openInGoogleMaps(spot: spot)
            }
            Button("Cancel", role: .cancel) { }
        } message: { spot in
            Text(spot.name)
        }
        .alert("Filters Coming Soon", isPresented: $showFiltersPlaceholder) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Filter functionality will be available in a future update.")
        }
    }
    
    // MARK: - Computed Properties
    
    private var bottomSheetHeight: CGFloat {
        viewModel.sheetState.height
    }
    
    // MARK: - Helper Methods
    
    private func updateMarkers() {
        // Only show saved places markers (no nearby spot markers)
        markers = viewModel.createMarkers()
    }
    
    private func handleMarkerTap(_ marker: GMSMarker) {
        // Check if this is a saved spot marker (custom markers have placeId in userData)
        if let placeId = marker.userData as? String,
           let spot = viewModel.findSavedPlace(byPlaceId: placeId) {
            viewModel.selectSpot(spot)
        }
    }
    
    private func openInGoogleMaps(spot: NearbySpot) {
        let urlString = "https://www.google.com/maps/search/?api=1&query=\(spot.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&query_place_id=\(spot.placeId)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    ExploreView(viewModel: MapViewModel())
}

