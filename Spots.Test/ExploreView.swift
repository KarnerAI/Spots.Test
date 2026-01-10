//
//  ExploreView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI
import GoogleMaps

struct ExploreView: View {
    @State private var showSearchView = false
    @State private var showFiltersPlaceholder = false
    @StateObject private var viewModel = MapViewModel()
    @State private var mapView: GMSMapView?
    @State private var markers: [GMSMarker] = []
    
    var body: some View {
        ZStack {
            // Full screen map
            GoogleMapView(
                cameraPosition: $viewModel.cameraPosition,
                markers: $markers,
                showUserLocation: .constant(true),
                forceCameraUpdate: $viewModel.forceCameraUpdate,
                onMapReady: { mapView in
                    self.mapView = mapView
                    viewModel.setupMap(mapView)
                    // Track initial camera position
                    viewModel.currentCameraPosition = mapView.camera
                },
                onCameraChanged: { position in
                    // Update current camera position in ViewModel
                    viewModel.currentCameraPosition = position
                    // Handle camera changes if needed
                    let radius = viewModel.calculateRadius(for: position.zoom)
                    print("Map zoom: \(position.zoom), calculated radius: \(radius)m")
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
            
            // Locate Me Button
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
                    .padding(.trailing, 16)
                    .padding(.bottom, 120) // Positioned higher above bottom navigation bar
                }
            }
        }
        .onAppear {
            // Request location permission and load saved places
            viewModel.requestLocation()
            Task {
                await viewModel.loadSavedPlaces()
                updateMarkers()
            }
        }
        .onChange(of: viewModel.savedPlaces.count) { oldValue, newValue in
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
        .alert("Filters Coming Soon", isPresented: $showFiltersPlaceholder) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Filter functionality will be available in a future update.")
        }
    }
    
    private func updateMarkers() {
        markers = viewModel.createMarkers()
    }
}

#Preview {
    ExploreView()
}

