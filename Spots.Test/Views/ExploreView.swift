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
    @EnvironmentObject var locationSavingVM: LocationSavingViewModel
    @State private var showSearchView = false
    @State private var showFiltersPlaceholder = false
    @State private var mapView: GMSMapView?
    @State private var markers: [GMSMarker] = []

    // Bottom sheet state
    @State private var spotForSaving: NearbySpot? = nil
    @State private var spotToOpenInMaps: NearbySpot? = nil

    // MARK: - Marker Update Trigger

    /// Captures all inputs that affect markers so we fire a single `updateMarkers()` per change.
    private struct MarkerTrigger: Equatable {
        let savedCount: Int
        let nearbyIds: [String]
        let selectedId: String?
    }

    private var markerTrigger: MarkerTrigger {
        MarkerTrigger(
            savedCount: viewModel.savedPlaces.count,
            nearbyIds: viewModel.nearbySpots.map(\.placeId),
            selectedId: viewModel.selectedSpot?.placeId
        )
    }
    
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
                    viewModel.currentCameraPosition = position
                    #if DEBUG
                    let radius = viewModel.calculateRadius(for: position.zoom)
                    print("Map zoom: \(position.zoom), calculated radius: \(radius)m")
                    #endif
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
            
            // Floating search bar overlay (slim: 38pt height, 10/8 padding, 36pt filter)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(.gray400)
                    Text("Search spots, friends...")
                        .font(.system(size: 15))
                        .foregroundColor(.gray400)
                    Spacer()
                    Button(action: {
                        showFiltersPlaceholder = true
                    }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.gray900)
                    }
                    .frame(minWidth: 36, minHeight: 36)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(height: 38)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.field, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                .contentShape(Rectangle())
                .onTapGesture {
                    showSearchView = true
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 16)
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
                .padding(.bottom, viewModel.selectedSpot != nil ? 222 : bottomSheetHeight + 70 + 16) // Above floating card or bottom sheet + tab bar
            }
            
            // Bottom sheet only when no spot selected
            if viewModel.selectedSpot == nil {
                VStack {
                    Spacer()
                    SpotsBottomSheetView(
                        sheetState: $viewModel.sheetState,
                        spots: viewModel.displayedSpots,
                        isLoading: viewModel.isLoadingNearbySpots,
                        hasMorePages: viewModel.hasMorePages,
                        errorMessage: viewModel.nearbyErrorMessage,
                        spotListTypeMap: viewModel.spotListTypeMap,
                        hasLoadedSavedPlaces: viewModel.hasLoadedSavedPlacesOnce,
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
                                await viewModel.fetchNearbySpots(refresh: true, reason: .retry)
                            }
                        },
                        onCardVisible: { spot in
                            viewModel.resolvePhotoReferenceIfNeeded(for: spot.placeId)
                        }
                    )
                    .padding(.bottom, 78) // Space for tab bar
                }
            }

            // Floating card when a pin is selected (matches List Detail map card)
            if let selected = viewModel.selectedSpot {
                VStack {
                    Spacer()
                    SpotCardView(
                        spot: selected,
                        spotListTypeMap: viewModel.spotListTypeMap,
                        hasLoadedSavedPlaces: viewModel.hasLoadedSavedPlacesOnce,
                        onBookmarkTap: { spotForSaving = selected },
                        onCardTap: { spotToOpenInMaps = selected }
                    )
                    .frame(width: SpotCardView.cardWidth(for: UIScreen.main.bounds.width))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 78 + 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
                            await viewModel.loadSavedPlaces(forceRefresh: true)
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
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.selectedSpot?.placeId)
        .onAppear {
            // Restore map to last camera only when returning from another tab in the same session (not on first open or after app was backgrounded)
            if viewModel.hasExploreAppearedBefore, let lastCamera = viewModel.currentCameraPosition {
                viewModel.cameraPosition = lastCamera
            }
            viewModel.hasExploreAppearedBefore = true
        }
        .task {
            // Load saved places and lists (staleness guard inside ViewModels avoids redundant fetches on tab re-appearance)
            await viewModel.loadSavedPlaces()
            await locationSavingVM.loadUserLists()
            updateMarkers()
        }
        .onChange(of: markerTrigger) { _, _ in
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
            .environmentObject(locationSavingVM)
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
        .environmentObject(LocationSavingViewModel())
}

