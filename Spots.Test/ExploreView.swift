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
    @StateObject private var viewModel = MapViewModel()
    @State private var mapView: GMSMapView?
    @State private var markers: [GMSMarker] = []
    
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search Bar
                Button(action: {
                    showSearchView = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundColor(.gray400)
                        
                        Text("Search for places...")
                            .font(.system(size: 16))
                            .foregroundColor(.gray400)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(24)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 0)
                
                // Google Map View
                ZStack {
                    GoogleMapView(
                        cameraPosition: $viewModel.cameraPosition,
                        markers: $markers,
                        showUserLocation: .constant(true),
                        onMapReady: { mapView in
                            self.mapView = mapView
                            viewModel.setupMap(mapView)
                        },
                        onCameraChanged: { position in
                            // Handle camera changes if needed
                            let radius = viewModel.calculateRadius(for: position.zoom)
                            print("Map zoom: \(position.zoom), calculated radius: \(radius)m")
                        }
                    )
                    .ignoresSafeArea()
                    
                    // Locate Me Button
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                viewModel.requestLocation()
                                // Wait a moment for location to update, then center
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    if let location = viewModel.currentLocation {
                                        viewModel.centerOnLocation(location)
                                    }
                                }
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
    }
    
    private func updateMarkers() {
        markers = viewModel.createMarkers()
    }
}

#Preview {
    ExploreView()
}

