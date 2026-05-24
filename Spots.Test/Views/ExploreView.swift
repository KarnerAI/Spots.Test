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
            
            // Locate Me Button — sits just above whichever bottom UI is showing
            // (place card if a spot is selected, otherwise the bottom sheet).
            // Status text dropped: the crosshair icon implies the function and
            // "Located/Locating..." was only meaningful for the first ~second.
            VStack {
                Spacer()
                HStack {
                    Spacer()
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
                    .padding(.trailing, locateButtonTrailingPadding)
                }
                .padding(.bottom, locateButtonBottomPadding)
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
                        spotListKindMap: viewModel.spotListKindMap,
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
                }
            }

            // Floating card when a pin is selected (matches List Detail map card)
            if let selected = viewModel.selectedSpot {
                VStack {
                    Spacer()
                    SpotCardView(
                        spot: selected,
                        spotListKindMap: viewModel.spotListKindMap,
                        hasLoadedSavedPlaces: viewModel.hasLoadedSavedPlacesOnce,
                        onBookmarkTap: { spotForSaving = selected },
                        onCardTap: { spotToOpenInMaps = selected }
                    )
                    .frame(width: SpotCardView.cardWidth(for: UIScreen.main.bounds.width))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
        }
        .listPickerSheet(spot: $spotForSaving) {
            Task {
                await viewModel.loadSavedPlaces(forceRefresh: true)
                updateMarkers()
            }
        }
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
                onSelectSpot: { result in
                    // Google-Maps-style: dismiss search, pan to the place, and
                    // show its place card. Save flow happens from the card.
                    showSearchView = false
                    Task {
                        await viewModel.selectPlaceFromSearch(result: result)
                    }
                },
                onFiltersClick: {
                    print("Filters clicked")
                }
            )
            .environmentObject(locationSavingVM)
        }
        .openInGoogleMapsConfirmation(place: $spotToOpenInMaps)
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

    /// Trailing inset for the Locate Me button. When a place card is showing,
    /// match the card's right edge (the card is centered at ~94% of screen
    /// width, capped at 370pt) so the button sits on the same vertical line
    /// as the card. Otherwise fall back to a flat 16pt screen-edge inset.
    /// `max(16, …)` prevents narrow screens from pulling the button past the
    /// safe edge.
    private var locateButtonTrailingPadding: CGFloat {
        if viewModel.selectedSpot != nil {
            let screenWidth = UIScreen.main.bounds.width
            let cardWidth = SpotCardView.cardWidth(for: screenWidth)
            return max(16, (screenWidth - cardWidth) / 2)
        }
        return 16
    }

    /// Bottom inset for the Locate Me button so it sits ~12pt above whichever
    /// bottom UI is currently rendered. Place card replaces the sheet when a
    /// spot is selected — its height is 120pt + 16pt bottom padding (see
    /// `SpotCardView.cardHeight` and the `.padding(.bottom, 16)` on line 190).
    private var locateButtonBottomPadding: CGFloat {
        if viewModel.selectedSpot != nil {
            let cardHeight: CGFloat = 120
            let cardBottomPadding: CGFloat = 16
            let gap: CGFloat = 12
            return cardHeight + cardBottomPadding + gap
        }
        return bottomSheetHeight + 16
    }
    
    // MARK: - Helper Methods
    
    private func updateMarkers() {
        var next = viewModel.createMarkers()
        // Add a prominent teardrop for an unsaved selected place so the user
        // can actually see *where* their searched/tapped POI is on the map.
        if let pin = viewModel.createSelectedSpotMarker() {
            next.append(pin)
        }
        markers = next
    }
    
    private func handleMarkerTap(_ marker: GMSMarker) {
        // Check if this is a saved spot marker (custom markers have placeId in userData)
        if let placeId = marker.userData as? String,
           let spot = viewModel.findSavedPlace(byPlaceId: placeId) {
            viewModel.selectSpot(spot)
        }
    }
    
}

#Preview {
    let saving = LocationSavingViewModel()
    return ExploreView(viewModel: MapViewModel(locationSavingVM: saving))
        .environmentObject(saving)
}

