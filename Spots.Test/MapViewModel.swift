//
//  MapViewModel.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation
import GoogleMaps
import CoreLocation
import Combine

@MainActor
class MapViewModel: ObservableObject {
    @Published var savedPlaces: [SpotWithMetadata] = []
    @Published var currentLocation: CLLocation?
    @Published var cameraPosition: GMSCameraPosition?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let locationManager = LocationManager()
    private let locationSavingService = LocationSavingService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Map view reference for future clustering support
    private var mapView: GMSMapView?
    
    // Base radius in meters (5km)
    private let baseRadius: Double = 5000.0
    
    init() {
        setupLocationObserver()
    }
    
    // MARK: - Location Management
    
    private func setupLocationObserver() {
        locationManager.$location
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.currentLocation = location
                if let location = location, self?.cameraPosition == nil {
                    // Set initial camera position to user location
                    self?.centerOnLocation(location)
                }
            }
            .store(in: &cancellables)
    }
    
    func requestLocation() {
        locationManager.requestLocationPermission()
        locationManager.requestLocation()
    }
    
    func centerOnLocation(_ location: CLLocation) {
        let position = GMSCameraPosition.camera(
            withLatitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            zoom: 15.0  // Closer zoom for better detail when locating user
        )
        cameraPosition = position
    }
    
    // MARK: - Saved Places
    
    func loadSavedPlaces() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Get all three lists
            let starredList = try await locationSavingService.getListByType(.starred)
            let favoritesList = try await locationSavingService.getListByType(.favorites)
            let bucketList = try await locationSavingService.getListByType(.bucketList)
            
            var allPlaces: [SpotWithMetadata] = []
            
            // Fetch places from each list
            if let starredId = starredList?.id {
                let starredPlaces = try await locationSavingService.getSpotsInList(listId: starredId)
                allPlaces.append(contentsOf: starredPlaces)
            }
            
            if let favoritesId = favoritesList?.id {
                let favoritesPlaces = try await locationSavingService.getSpotsInList(listId: favoritesId)
                allPlaces.append(contentsOf: favoritesPlaces)
            }
            
            if let bucketId = bucketList?.id {
                let bucketPlaces = try await locationSavingService.getSpotsInList(listId: bucketId)
                allPlaces.append(contentsOf: bucketPlaces)
            }
            
            // Remove duplicates (same placeId) - keep the most recent savedAt
            var uniquePlaces: [String: SpotWithMetadata] = [:]
            for place in allPlaces {
                if let existing = uniquePlaces[place.spot.placeId] {
                    if place.savedAt > existing.savedAt {
                        uniquePlaces[place.spot.placeId] = place
                    }
                } else {
                    uniquePlaces[place.spot.placeId] = place
                }
            }
            
            savedPlaces = Array(uniquePlaces.values)
            isLoading = false
            
        } catch {
            errorMessage = "Failed to load saved places: \(error.localizedDescription)"
            isLoading = false
            print("Error loading saved places: \(error)")
        }
    }
    
    // MARK: - Map Markers
    
    func createMarkers() -> [GMSMarker] {
        return savedPlaces.compactMap { placeWithMetadata in
            guard let latitude = placeWithMetadata.spot.latitude,
                  let longitude = placeWithMetadata.spot.longitude else {
                return nil
            }
            
            let marker = GMSMarker()
            marker.position = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            marker.title = placeWithMetadata.spot.name
            marker.snippet = placeWithMetadata.spot.address
            marker.icon = iconForPlaceType(placeWithMetadata.spot.types)
            
            return marker
        }
    }
    
    private func iconForPlaceType(_ types: [String]?) -> UIImage? {
        let tealColor = UIColor(red: 0.36, green: 0.69, blue: 0.72, alpha: 1.0)
        
        guard let types = types else {
            return GMSMarker.markerImage(with: tealColor)
        }
        
        // Check for restaurant
        if types.contains(where: { $0.lowercased().contains("restaurant") || $0.lowercased().contains("food") }) {
            // Create custom marker with fork/knife icon
            return createCustomMarkerIcon(systemName: "fork.knife", color: tealColor)
        }
        
        // Check for cafe
        if types.contains(where: { $0.lowercased().contains("cafe") || $0.lowercased().contains("coffee") }) {
            return createCustomMarkerIcon(systemName: "cup.and.saucer.fill", color: tealColor)
        }
        
        // Default teal marker
        return GMSMarker.markerImage(with: tealColor)
    }
    
    private func createCustomMarkerIcon(systemName: String, color: UIColor) -> UIImage? {
        // Create a circular background
        let size = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Draw circular background
            let rect = CGRect(origin: .zero, size: size)
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.fillEllipse(in: rect)
            
            // Draw white border
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(2.0)
            context.cgContext.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
            
            // Draw icon in center
            if let icon = UIImage(systemName: systemName) {
                let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
                let configuredIcon = icon.withConfiguration(config)
                let iconSize: CGFloat = 18
                let iconRect = CGRect(
                    x: (size.width - iconSize) / 2,
                    y: (size.height - iconSize) / 2,
                    width: iconSize,
                    height: iconSize
                )
                configuredIcon.withTintColor(.white, renderingMode: .alwaysTemplate)
                    .draw(in: iconRect, blendMode: .normal, alpha: 1.0)
            }
        }
    }
    
    // MARK: - Dynamic Radius
    
    func calculateRadius(for zoom: Float) -> Double {
        // Base zoom level (14.0)
        let baseZoom: Float = 14.0
        let zoomDifference = zoom - baseZoom
        
        // Calculate radius: baseRadius * 2^(zoomDifference)
        // As zoom increases (zooming in), radius decreases
        // As zoom decreases (zooming out), radius increases
        let multiplier = pow(2.0, Double(-zoomDifference))
        return baseRadius * multiplier
    }
    
    // MARK: - Map Setup
    
    func setupMap(_ mapView: GMSMapView) {
        self.mapView = mapView
        // Clustering can be added here later with Google Maps Utility Library
    }
    
    func refreshMarkers() {
        // This will be called when saved places are updated
        // Markers are created on-demand via createMarkers()
    }
}

