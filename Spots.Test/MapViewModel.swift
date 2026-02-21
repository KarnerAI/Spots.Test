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
import UIKit

@MainActor
class MapViewModel: ObservableObject {
    @Published var savedPlaces: [SpotWithMetadata] = []
    @Published var currentLocation: CLLocation?
    @Published var cameraPosition: GMSCameraPosition?
    @Published var currentCameraPosition: GMSCameraPosition?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var shouldCenterOnLocation: Bool = false
    @Published var forceCameraUpdate: Bool = false
    
    // MARK: - Nearby Spots State
    @Published var nearbySpots: [NearbySpot] = []
    @Published var selectedSpot: NearbySpot? = nil
    @Published var isLoadingNearbySpots: Bool = false
    @Published var nearbyErrorMessage: String? = nil
    @Published var sheetState: BottomSheetState = .expanded
    
    // MARK: - Spot List Membership State
    @Published var hasLoadedSavedPlacesOnce: Bool = false
    @Published var spotListTypeMap: [String: ListType] = [:]
    
    // Pagination state
    private var nextPageToken: String? = nil
    var hasMorePages: Bool { nextPageToken != nil }
    
    /// Returns displayed spots (selected single spot or all nearby spots)
    var displayedSpots: [NearbySpot] {
        if let selected = selectedSpot {
            return [selected]
        }
        return nearbySpots
    }
    
    private let locationManager = LocationManager()
    private let locationSavingService = LocationSavingService.shared
    private let placesAPIService = PlacesAPIService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Map view reference for future clustering support
    private var mapView: GMSMapView?

    /// Task handle for the background image upload so we can cancel on new fetch
    private var imageUploadTask: Task<Void, Never>?

    /// Cache for rendered marker icons keyed by list type (e.g. "starred", "favorites", "bucketList")
    private var cachedMarkerIcons: [String: UIImage] = [:]
    
    /// True after we've triggered the first nearby fetch when location became available (avoids refetch on every location update).
    private var hasPerformedInitialNearbyFetch = false
    
    /// True after Explore has been shown in this foreground session; used to restore last camera when returning from another tab. Reset when app enters background.
    var hasExploreAppearedBefore = false
    
    // Base radius in meters (5km)
    private let baseRadius: Double = 5000.0
    
    // Nearby search radius in meters (1km)
    private let nearbySearchRadius: Double = 1000.0
    
    // Page size for nearby spots carousel (initial load + each scroll-triggered load more)
    private let nearbyPageSize = 5
    
    init() {
        setupLocationObserver()
    }
    
    // MARK: - Location Management
    
    private func setupLocationObserver() {
        locationManager.$location
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                guard let self = self else { return }
                self.currentLocation = location
                
                if let location = location {
                    // Set initial camera position to user location if not set
                    if self.cameraPosition == nil {
                        self.centerOnLocation(location)
                        // Fetch nearby spots as soon as location is available (first-time only)
                        if !self.hasPerformedInitialNearbyFetch {
                            self.hasPerformedInitialNearbyFetch = true
                            Task { await self.fetchNearbySpots(refresh: true) }
                        }
                    }
                    // Center on location if explicitly requested (e.g., from Locate Me button)
                    else if self.shouldCenterOnLocation {
                        self.centerOnLocation(location)
                        self.shouldCenterOnLocation = false
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func requestLocation() {
        locationManager.requestLocationPermission()
        locationManager.requestLocation()
    }
    
    /// Call when app enters background so next time Explore appears we show user location (treat as first open).
    func resetExploreSession() {
        hasExploreAppearedBefore = false
    }
    
    func centerOnLocation(_ location: CLLocation) {
        // #region agent log
        print("🔴 DEBUG: centerOnLocation called for lat=\(location.coordinate.latitude), lng=\(location.coordinate.longitude)")
        // #endregion
        
        let position = GMSCameraPosition.camera(
            withLatitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            zoom: 17.0  // Building-level detail
        )
        
        // #region agent log
        print("🔴 DEBUG: About to set cameraPosition to lat=\(position.target.latitude), lng=\(position.target.longitude), zoom=\(position.zoom)")
        // #endregion
        
        // Force camera update to bypass threshold check
        forceCameraUpdate = true
        cameraPosition = position
        
        // Reset force flag after a brief delay to allow updateUIView to process it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.forceCameraUpdate = false
        }
        
        // #region agent log
        print("🔴 DEBUG: cameraPosition SET to lat=\(position.target.latitude), lng=\(position.target.longitude), zoom=\(position.zoom), forceCameraUpdate=true")
        if let camPos = cameraPosition {
            print("🔴 DEBUG: cameraPosition VERIFIED = lat=\(camPos.target.latitude), lng=\(camPos.target.longitude), zoom=\(camPos.zoom)")
        } else {
            print("🔴 DEBUG: cameraPosition is NIL after setting!")
        }
        // #endregion
    }
    
    // MARK: - Viewport and Visibility Helpers
    
    func getCurrentViewportBounds() -> GMSCoordinateBounds? {
        guard let mapView = mapView else { return nil }
        let visibleRegion = mapView.projection.visibleRegion()
        return GMSCoordinateBounds(region: visibleRegion)
    }
    
    func isLocationVisible(_ location: CLLocation, in viewport: GMSCoordinateBounds) -> Bool {
        return viewport.contains(location.coordinate)
    }
    
    func isLocationCentered(_ location: CLLocation, in camera: GMSCameraPosition, tolerance: Double = 0.0001) -> Bool {
        let latDiff = abs(camera.target.latitude - location.coordinate.latitude)
        let lngDiff = abs(camera.target.longitude - location.coordinate.longitude)
        return latDiff <= tolerance && lngDiff <= tolerance
    }
    
    func zoomToDefault(at coordinate: CLLocationCoordinate2D) {
        let position = GMSCameraPosition.camera(
            withLatitude: coordinate.latitude,
            longitude: coordinate.longitude,
            zoom: 17.0  // Building-level detail
        )
        cameraPosition = position
    }
    
    func centerOnCurrentLocation() {
        print("📍 Locate Me button clicked")
        
        // Reset selected spot when Locate Me is pressed
        selectedSpot = nil
        
        guard let location = currentLocation else {
            print("⚠️ No current location available, requesting...")
            // Request location and set flag to center when it becomes available
            shouldCenterOnLocation = true
            requestLocation()
            return
        }
        
        print("📍 Current location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        // Get current camera - use mapView?.camera as primary source since it's always up-to-date
        let currentCamera = mapView?.camera ?? currentCameraPosition
        guard let currentCamera = currentCamera else {
            print("⚠️ No camera position available, centering on location")
            // Fallback: just center on location and fetch spots
            centerOnLocation(location)
            Task { await fetchNearbySpots(refresh: true) }
            return
        }
        
        print("📷 Current camera: \(currentCamera.target.latitude), \(currentCamera.target.longitude), zoom: \(currentCamera.zoom)")
        
        // Check if location is CENTERED (not just visible)
        let isCentered = isLocationCentered(location, in: currentCamera)
        let isAtDefaultZoom = abs(currentCamera.zoom - 17.0) <= 1.0
        
        print("🎯 Location centered: \(isCentered), at default zoom: \(isAtDefaultZoom)")
        
        // If location is centered AND at default zoom → Just refresh spots
        if isCentered && isAtDefaultZoom {
            print("✅ Location already centered at default zoom, refreshing spots")
            Task { await fetchNearbySpots(refresh: true) }
            return
        }
        
        // Get viewport for visibility check (optional, for logging)
        if let viewport = getCurrentViewportBounds() {
            let isVisible = isLocationVisible(location, in: viewport)
            print("👁️ Location visible in viewport: \(isVisible)")
            
            // If location is visible but NOT centered → Always center on it
            if isVisible && !isCentered {
                print("📍 Location visible but not centered, centering...")
                centerOnLocation(location)
                Task { await fetchNearbySpots(refresh: true) }
                return
            }
            
            // If location is visible, centered, but not at default zoom → Zoom to default
            if isVisible && isCentered && !isAtDefaultZoom {
                print("🔍 Location centered but not at default zoom, zooming...")
                zoomToDefault(at: location.coordinate)
                Task { await fetchNearbySpots(refresh: true) }
                return
            }
        }
        
        // If location is NOT visible or any check failed → Center on it
        print("📍 Centering on location (not visible or checks failed)")
        centerOnLocation(location)
        Task { await fetchNearbySpots(refresh: true) }
    }
    
    // MARK: - Nearby Spots
    
    /// Fetches nearby spots from Google Places API
    /// - Parameter refresh: If true, clears existing spots and resets pagination
    func fetchNearbySpots(refresh: Bool = false) async {
        guard let location = currentLocation else {
            print("⚠️ Cannot fetch nearby spots: no current location")
            nearbyErrorMessage = "Location not available"
            return
        }
        
        // If refreshing, reset state
        if refresh {
            nearbySpots = []
            nextPageToken = nil
            selectedSpot = nil
        }
        
        // Don't fetch if already loading or no more pages
        guard !isLoadingNearbySpots else { return }
        if !refresh && nextPageToken == nil && !nearbySpots.isEmpty { return }
        
        isLoadingNearbySpots = true
        nearbyErrorMessage = nil
        
        do {
            let result = try await placesAPIService.searchNearby(
                location: location,
                radius: nearbySearchRadius,
                pageToken: nextPageToken,
                maxResults: nearbyPageSize
            )
            
            // Append new spots (for pagination) or replace (for refresh)
            if refresh {
                nearbySpots = result.spots
            } else {
                // Filter out duplicates based on placeId
                let existingIds = Set(nearbySpots.map { $0.placeId })
                let newSpots = result.spots.filter { !existingIds.contains($0.placeId) }
                nearbySpots.append(contentsOf: newSpots)
            }
            
            nextPageToken = result.nextPageToken
            isLoadingNearbySpots = false
            
            print("📍 Fetched \(result.spots.count) nearby spots. Total: \(nearbySpots.count). Has more: \(hasMorePages)")
            
            // Cache all spot metadata and images in Supabase in background.
            // 1) Bulk-upsert spot rows so future lookups (e.g. POI taps) can skip Google.
            // 2) Upload images so future renders use the free Supabase CDN path.
            let spotsToUpload = result.spots

            // Cancel any in-flight upload task from a previous fetch to avoid stale writes
            imageUploadTask?.cancel()
            imageUploadTask = Task {
                // First, ensure all spots have a row in the DB
                await placesAPIService.bulkUpsertSpots(spotsToUpload)

                guard !Task.isCancelled else { return }

                // Then upload images (checks for existing photos before downloading)
                let uploadedUrls = await placesAPIService.uploadSpotImages(spots: spotsToUpload)

                guard !Task.isCancelled else { return }

                if !uploadedUrls.isEmpty {
                    // Use placeId lookup instead of index to avoid race condition
                    for (placeId, url) in uploadedUrls {
                        if let index = nearbySpots.firstIndex(where: { $0.placeId == placeId }) {
                            nearbySpots[index].photoUrl = url
                        }
                    }
                }
            }
            
        } catch {
            isLoadingNearbySpots = false
            nearbyErrorMessage = error.localizedDescription
            print("❌ Error fetching nearby spots: \(error)")
        }
    }
    
    /// Loads more nearby spots (for pagination)
    func loadMoreNearbySpots() async {
        guard hasMorePages && !isLoadingNearbySpots else { return }
        await fetchNearbySpots(refresh: false)
    }
    
    /// Selects a spot (e.g., when user taps a marker)
    func selectSpot(_ spot: NearbySpot) {
        selectedSpot = spot
    }
    
    /// Deselects the current spot (returns to nearby mode)
    func deselectSpot() {
        selectedSpot = nil
    }
    
    /// Finds a saved place by placeId and converts to NearbySpot format
    func findSavedPlace(byPlaceId placeId: String) -> NearbySpot? {
        guard let savedPlace = savedPlaces.first(where: { $0.spot.placeId == placeId }) else {
            return nil
        }
        let spot = savedPlace.spot
        return NearbySpot(
            placeId: spot.placeId,
            name: spot.name,
            address: spot.address ?? "",
            category: spot.types?.first?.capitalized ?? "Place",
            rating: nil,
            photoReference: spot.photoReference,
            photoUrl: spot.photoUrl,
            latitude: spot.latitude ?? 0,
            longitude: spot.longitude ?? 0,
            distanceMeters: calculateDistance(to: spot)
        )
    }
    
    /// Calculates distance from user location to a spot
    private func calculateDistance(to spot: Spot) -> Double? {
        guard let userLoc = currentLocation,
              let lat = spot.latitude,
              let lng = spot.longitude else { return nil }
        return DistanceCalculator.distance(from: userLoc, to: CLLocationCoordinate2D(latitude: lat, longitude: lng))
    }

    /// Calculates distance from user location to a coordinate
    private func calculateDistanceToCoordinate(_ coord: CLLocationCoordinate2D) -> Double? {
        guard let userLoc = currentLocation else { return nil }
        return DistanceCalculator.distance(from: userLoc, to: coord)
    }
    
    /// Fetches POI details and selects it as the current spot.
    /// Checks Supabase cache first to avoid a Google API call for known spots.
    func fetchAndSelectPOI(placeId: String, name: String, location: CLLocationCoordinate2D) async {
        // 1) Check in-memory data for a cached photo URL (free, no API call)
        let cachedPhotoUrl: String? = {
            if let existing = nearbySpots.first(where: { $0.placeId == placeId }), let url = existing.photoUrl, !url.isEmpty {
                return url
            }
            if let saved = savedPlaces.first(where: { $0.spot.placeId == placeId }), let url = saved.spot.photoUrl, !url.isEmpty {
                return url
            }
            return nil
        }()
        
        // Show loading state with basic info first
        let basicSpot = NearbySpot(
            placeId: placeId,
            name: name,
            address: "",
            category: "Place",
            rating: nil,
            photoReference: nil,
            photoUrl: cachedPhotoUrl,
            latitude: location.latitude,
            longitude: location.longitude,
            distanceMeters: calculateDistanceToCoordinate(location)
        )
        selectedSpot = basicSpot
        
        // 2) Check Supabase DB cache for full spot data (avoids Google API call)
        if let cachedSpot = await placesAPIService.getCachedSpot(placeId: placeId) {
            var spot = cachedSpot
            spot.distanceMeters = calculateDistanceToCoordinate(location)
            // Prefer in-memory photo URL if we have one
            if let url = cachedPhotoUrl {
                spot.photoUrl = url
            }
            // Sync tap location to DB so list markers align with Google's POI (skip if already very close)
            let cachedLocation = CLLocation(latitude: cachedSpot.latitude, longitude: cachedSpot.longitude)
            let tapLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            if cachedLocation.distance(from: tapLocation) >= 2.0 {
                do {
                    try await locationSavingService.updateSpotLocation(placeId: placeId, latitude: location.latitude, longitude: location.longitude)
                    await loadSavedPlaces()
                } catch {
                    print("⚠️ MapViewModel: Failed to sync POI tap location for \(placeId): \(error.localizedDescription)")
                }
            }
            selectedSpot = spot
            print("✅ MapViewModel: Used cached spot data for \(placeId) — no Google API call")
            return
        }
        
        // 3) Not in cache — fetch full details from Google Places API
        do {
            if let detailedSpot = try await placesAPIService.fetchPlaceDetails(placeId: placeId) {
                var spot = detailedSpot
                spot.distanceMeters = calculateDistanceToCoordinate(location)
                
                // Prefer cached Supabase URL to avoid a paid Google Photo API call.
                // Check in-memory first, then DB.
                if let url = cachedPhotoUrl {
                    spot.photoUrl = url
                } else if let dbUrl = await placesAPIService.getCachedPhotoUrl(placeId: placeId) {
                    spot.photoUrl = dbUrl
                }
                
                selectedSpot = spot
                
                // 4) Save the result to Supabase so future taps use the cache
                await placesAPIService.bulkUpsertSpots([spot])
            }
        } catch {
            print("Failed to fetch POI details: \(error)")
            // Keep showing basic info
        }
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
            
            // Fetch places from each list with their list type
            if let starredId = starredList?.id {
                let starredPlaces = try await locationSavingService.getSpotsInList(listId: starredId, listType: .starred)
                allPlaces.append(contentsOf: starredPlaces)
            }
            
            if let favoritesId = favoritesList?.id {
                let favoritesPlaces = try await locationSavingService.getSpotsInList(listId: favoritesId, listType: .favorites)
                allPlaces.append(contentsOf: favoritesPlaces)
            }
            
            if let bucketId = bucketList?.id {
                let bucketPlaces = try await locationSavingService.getSpotsInList(listId: bucketId, listType: .bucketList)
                allPlaces.append(contentsOf: bucketPlaces)
            }
            
            // Aggregate by placeId - merge listTypes sets and keep most recent savedAt
            var uniquePlaces: [String: SpotWithMetadata] = [:]
            for place in allPlaces {
                if let existing = uniquePlaces[place.spot.placeId] {
                    // Merge the listTypes sets
                    let mergedListTypes = existing.listTypes.union(place.listTypes)
                    // Keep the most recent savedAt
                    let mostRecentSavedAt = max(existing.savedAt, place.savedAt)
                    uniquePlaces[place.spot.placeId] = SpotWithMetadata(
                        spot: existing.spot,
                        savedAt: mostRecentSavedAt,
                        listTypes: mergedListTypes
                    )
                } else {
                    uniquePlaces[place.spot.placeId] = place
                }
            }
            
            savedPlaces = Array(uniquePlaces.values)
            
            // Precompute display list type map for efficient O(1) lookups in cards
            spotListTypeMap = Dictionary(uniqueKeysWithValues:
                savedPlaces.compactMap { spot in
                    guard let listType = displayListType(for: spot.listTypes) else { return nil }
                    return (spot.spot.placeId, listType)
                }
            )
            
            hasLoadedSavedPlacesOnce = true
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
            // Place marker directly on POI to cover it
            marker.position = CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )
            marker.title = placeWithMetadata.spot.name
            marker.snippet = placeWithMetadata.spot.address
            marker.userData = placeWithMetadata.spot.placeId  // Store placeId for tap handling
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)  // Center icon on coordinate so it overlays POI
            
            // Get base icon
            var icon = iconForListTypes(placeWithMetadata.listTypes)
            
            // Scale up if this marker is selected
            if let selectedSpot = selectedSpot,
               selectedSpot.placeId == placeWithMetadata.spot.placeId,
               let baseIcon = icon {
                icon = scaleImage(baseIcon, to: 1.4)  // 40% larger
                marker.zIndex = 1  // Bring to front
            } else {
                marker.zIndex = 0
            }
            
            marker.icon = icon
            
            return marker
        }
    }
    
    /// Returns the appropriate icon based on list membership with priority: starred > favorites > bucket list.
    /// Icons are cached after first render to avoid repeated UIGraphicsImageRenderer work on map redraws.
    private func iconForListTypes(_ listTypes: Set<ListType>) -> UIImage? {
        // Priority order: starred (yellow) > favorites (red) > bucket list (blue)
        let cacheKey: String
        let systemName: String
        let color: UIColor

        if listTypes.contains(.starred) {
            cacheKey = "starred"
            systemName = "star.fill"
            color = .listStarred
        } else if listTypes.contains(.favorites) {
            cacheKey = "favorites"
            systemName = "heart.fill"
            color = .listFavorites
        } else if listTypes.contains(.bucketList) {
            cacheKey = "bucketList"
            systemName = "flag.fill"
            color = .listBucketList
        } else {
            // Fallback - should not happen if spot is in at least one list
            let tealColor = UIColor(red: 0.36, green: 0.69, blue: 0.72, alpha: 1.0)
            return GMSMarker.markerImage(with: tealColor)
        }

        if let cached = cachedMarkerIcons[cacheKey] {
            return cached
        }
        let icon = createCustomMarkerIcon(systemName: systemName, color: color)
        if let icon = icon {
            cachedMarkerIcons[cacheKey] = icon
        }
        return icon
    }
    
    private func createCustomMarkerIcon(systemName: String, color: UIColor) -> UIImage? {
        // Create a circular background - sized to match Google Maps default markers
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Draw circular background
            let rect = CGRect(origin: .zero, size: size)
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.fillEllipse(in: rect)
            
            // Draw white border
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(1.5)
            context.cgContext.strokeEllipse(in: rect.insetBy(dx: 0.75, dy: 0.75))
            
            // Draw white icon in center
            if let icon = UIImage(systemName: systemName) {
                let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                let configuredIcon = icon.withConfiguration(config)
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                let iconSize: CGFloat = 13
                let iconRect = CGRect(
                    x: (size.width - iconSize) / 2,
                    y: (size.height - iconSize) / 2,
                    width: iconSize,
                    height: iconSize
                )
                configuredIcon.draw(in: iconRect)
            }
        }
    }
    
    /// Scales an image by the given scale factor
    private func scaleImage(_ image: UIImage, to scale: CGFloat) -> UIImage {
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
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

// MARK: - UIColor Extension for List Colors
extension UIColor {
    /// Yellow color for starred list (matches the star icon)
    static let listStarred = UIColor(red: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)  // Gold/Yellow
    
    /// Red color for favorites list (matches the heart icon)
    static let listFavorites = UIColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1.0)  // Red
    
    /// Blue color for bucket list (matches the flag icon)
    static let listBucketList = UIColor(red: 0.29, green: 0.56, blue: 0.89, alpha: 1.0)  // Blue
}

