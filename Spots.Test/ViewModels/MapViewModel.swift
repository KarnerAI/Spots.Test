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
    private var savedPlacesLastLoadedAt: Date?
    private let savedPlacesStaleInterval: TimeInterval = 30
    
    // Pagination state
    private var nextPageToken: String? = nil
    var hasMorePages: Bool { nextPageToken != nil }
    
    // MARK: - Nearby Refresh Throttling
    private var lastNearbyFetchAt: Date?
    private var lastNearbyFetchLocation: CLLocation?
    private let nearbyRefreshCooldown: TimeInterval = 30
    private let nearbyRefreshCooldownFastMoving: TimeInterval = 60
    private let nearbyRefreshMinDistance: CLLocationDistance = 200
    private let fastMovingSpeedThreshold: CLLocationSpeed = 10 // ~22 mph
    
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

    /// Tracks place IDs with in-flight photo resolution to avoid duplicate requests
    private var photoResolutionInFlight: Set<String> = []

    /// Place IDs whose photo reference has already been resolved (prefetch path).
    /// Persists across `fetchNearbySpots` calls so panning back over the same
    /// region doesn't re-issue Places-detail lookups whose results are already
    /// cached locally.
    private var resolvedPhotoRefIds: Set<String> = []

    /// Place IDs whose image has already been uploaded to Storage this session.
    /// Avoids re-uploading the same Google Places photo every time the user
    /// pans the map across the same spots.
    private var uploadedImageSpotIds: Set<String> = []

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
    
    enum NearbyRefreshReason {
        case initial
        case locateMe
        case retry
        case pagination
    }
    
    /// Decides whether a nearby refresh should proceed based on time, distance, and movement speed.
    private func shouldAllowNearbyRefresh(reason: NearbyRefreshReason) -> Bool {
        switch reason {
        case .initial, .retry, .pagination:
            return true
        case .locateMe:
            break
        }
        
        guard let lastFetchTime = lastNearbyFetchAt else { return true }
        
        let elapsed = Date().timeIntervalSince(lastFetchTime)
        let distanceMoved: CLLocationDistance
        if let lastLoc = lastNearbyFetchLocation, let currentLoc = currentLocation {
            distanceMoved = currentLoc.distance(from: lastLoc)
        } else {
            distanceMoved = .greatestFiniteMagnitude
        }
        
        // Infer speed to detect fast movement (driving)
        let inferredSpeed = elapsed > 0 ? distanceMoved / elapsed : 0
        let cooldown = inferredSpeed > fastMovingSpeedThreshold
            ? nearbyRefreshCooldownFastMoving
            : nearbyRefreshCooldown
        
        let allowed = elapsed >= cooldown || distanceMoved >= nearbyRefreshMinDistance
        if !allowed {
            print("🚦 Nearby refresh blocked: elapsed=\(String(format: "%.0f", elapsed))s, moved=\(String(format: "%.0f", distanceMoved))m, speed=\(String(format: "%.1f", inferredSpeed))m/s, cooldown=\(String(format: "%.0f", cooldown))s")
        }
        return allowed
    }
    
    /// Records that a nearby refresh just completed so the throttle gate can track intervals.
    private func recordNearbyFetch() {
        lastNearbyFetchAt = Date()
        lastNearbyFetchLocation = currentLocation
    }
    
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
                            Task { await self.fetchNearbySpots(refresh: true, reason: .initial) }
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
        let position = GMSCameraPosition.camera(
            withLatitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            zoom: 17.0  // Building-level detail
        )

        // Force camera update to bypass threshold check
        forceCameraUpdate = true
        cameraPosition = position

        // Reset force flag after a brief delay to allow updateUIView to process it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.forceCameraUpdate = false
        }
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
        
        selectedSpot = nil
        
        guard let location = currentLocation else {
            print("⚠️ No current location available, requesting...")
            shouldCenterOnLocation = true
            requestLocation()
            return
        }
        
        print("📍 Current location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        let currentCamera = mapView?.camera ?? currentCameraPosition
        guard let currentCamera = currentCamera else {
            print("⚠️ No camera position available, centering on location")
            centerOnLocation(location)
            Task { await fetchNearbySpots(refresh: true, reason: .locateMe) }
            return
        }
        
        print("📷 Current camera: \(currentCamera.target.latitude), \(currentCamera.target.longitude), zoom: \(currentCamera.zoom)")
        
        let isCentered = isLocationCentered(location, in: currentCamera)
        let isAtDefaultZoom = abs(currentCamera.zoom - 17.0) <= 1.0
        
        print("🎯 Location centered: \(isCentered), at default zoom: \(isAtDefaultZoom)")
        
        // Adjust camera as needed (but only refresh spots once at the end)
        if !(isCentered && isAtDefaultZoom) {
            if let viewport = getCurrentViewportBounds() {
                let isVisible = isLocationVisible(location, in: viewport)
                print("👁️ Location visible in viewport: \(isVisible)")
                
                if isVisible && isCentered && !isAtDefaultZoom {
                    print("🔍 Location centered but not at default zoom, zooming...")
                    zoomToDefault(at: location.coordinate)
                } else if !isCentered {
                    print("📍 Centering on location...")
                    centerOnLocation(location)
                }
            } else {
                print("📍 Centering on location (no viewport available)")
                centerOnLocation(location)
            }
        }
        
        Task { await fetchNearbySpots(refresh: true, reason: .locateMe) }
    }
    
    // MARK: - Nearby Spots
    
    /// Fetches nearby spots from Google Places API
    /// - Parameters:
    ///   - refresh: If true, resets pagination and replaces existing spots on success
    ///   - reason: Why the refresh was requested (used by throttle gate)
    func fetchNearbySpots(refresh: Bool = false, reason: NearbyRefreshReason = .pagination) async {
        guard let location = currentLocation else {
            print("⚠️ Cannot fetch nearby spots: no current location")
            nearbyErrorMessage = "Location not available"
            return
        }
        
        // Apply throttle gate for non-pagination refreshes
        if refresh && !shouldAllowNearbyRefresh(reason: reason) {
            return
        }
        
        // If refreshing, reset pagination but keep existing cards visible
        if refresh {
            nextPageToken = nil
            selectedSpot = nil
        }
        
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
            
            // Build lookup maps from in-memory spots for carry-forward
            let existingPhotoUrls = Dictionary(
                uniqueKeysWithValues: nearbySpots.compactMap { spot -> (String, String)? in
                    guard let url = spot.photoUrl, !url.isEmpty else { return nil }
                    return (spot.placeId, url)
                }
            )
            let existingPhotoRefs = Dictionary(
                uniqueKeysWithValues: nearbySpots.compactMap { spot -> (String, String)? in
                    guard let ref = spot.photoReference, !ref.isEmpty else { return nil }
                    return (spot.placeId, ref)
                }
            )
            
            // Batch-fetch cached data from Supabase for spots not already hydrated
            let allNewPlaceIds = result.spots.map { $0.placeId }
            let dbPhotoUrls = await placesAPIService.getCachedPhotoUrls(placeIds: allNewPlaceIds)
            
            // Also fetch cached photo references since the Nearby Search field mask
            // no longer includes places.photos to stay on the cheaper billing SKU
            let idsNeedingRef = result.spots
                .filter { $0.photoReference == nil && existingPhotoRefs[$0.placeId] == nil }
                .map { $0.placeId }
            let dbPhotoRefs = await placesAPIService.getCachedPhotoReferences(placeIds: idsNeedingRef)
            
            var hydratedSpots = result.spots
            for i in hydratedSpots.indices {
                let pid = hydratedSpots[i].placeId
                
                // Hydrate photoUrl
                if hydratedSpots[i].photoUrl == nil {
                    if let cachedUrl = existingPhotoUrls[pid] {
                        hydratedSpots[i].photoUrl = cachedUrl
                    } else if let dbUrl = dbPhotoUrls[pid] {
                        hydratedSpots[i].photoUrl = dbUrl
                    }
                }
                
                // Hydrate photoReference from in-memory or DB cache
                if hydratedSpots[i].photoReference == nil {
                    if let cachedRef = existingPhotoRefs[pid] {
                        hydratedSpots[i].photoReference = cachedRef
                    } else if let dbRef = dbPhotoRefs[pid] {
                        hydratedSpots[i].photoReference = dbRef
                    }
                }
            }
            
            if refresh {
                nearbySpots = hydratedSpots
            } else {
                let existingIds = Set(nearbySpots.map { $0.placeId })
                let newSpots = hydratedSpots.filter { !existingIds.contains($0.placeId) }
                nearbySpots.append(contentsOf: newSpots)
            }
            
            nextPageToken = result.nextPageToken
            isLoadingNearbySpots = false
            recordNearbyFetch()
            
            let spotsWithPhoto = nearbySpots.filter { $0.photoUrl != nil || $0.photoReference != nil }.count
            print("📍 Fetched \(result.spots.count) nearby spots. Total: \(nearbySpots.count). With photo data: \(spotsWithPhoto). Has more: \(hasMorePages)")
            SpotImageCache.shared.logCacheStats()
            await ImageDownloadCoordinator.shared.logStats()
            
            let spotsToUpload = hydratedSpots

            imageUploadTask?.cancel()
            imageUploadTask = Task {
                await placesAPIService.bulkUpsertSpots(spotsToUpload)

                guard !Task.isCancelled else { return }

                // Resolve photo references only for the first few visible spots upfront.
                // Remaining spots are resolved on-demand via resolvePhotoReferenceIfNeeded()
                // when the user scrolls to them in the carousel.
                let prefetchCount = 3
                var resolvedSpots = spotsToUpload
                // Skip ids we already resolved this session — panning the map
                // over the same area shouldn't re-fetch Places details.
                let unresolvedIds = Array(resolvedSpots.enumerated()
                    .filter { $0.element.photoReference == nil
                        && !self.resolvedPhotoRefIds.contains($0.element.placeId) }
                    .prefix(prefetchCount)
                    .map { $0.offset })

                // Accumulate resolved refs locally (no @Published mutations yet)
                var resolvedRefs: [String: String] = [:]
                for idx in unresolvedIds {
                    guard !Task.isCancelled else { return }
                    let placeId = resolvedSpots[idx].placeId
                    if let details = try? await placesAPIService.fetchPlaceDetails(placeId: placeId),
                       let ref = details.photoReference {
                        resolvedSpots[idx].photoReference = ref
                        resolvedRefs[placeId] = ref
                    }
                    self.resolvedPhotoRefIds.insert(placeId)
                }

                guard !Task.isCancelled else { return }

                // Persist resolved photo references to Supabase
                let spotsWithNewRefs = resolvedSpots.filter { resolvedRefs[$0.placeId] != nil }
                if !spotsWithNewRefs.isEmpty {
                    await placesAPIService.bulkUpsertSpots(spotsWithNewRefs)
                }

                // Only upload images for spots that have a photo reference (prefetched ones)
                // and that we haven't already uploaded this session.
                let spotsForImageUpload = resolvedSpots.filter {
                    ($0.photoReference != nil || $0.photoUrl != nil)
                        && !self.uploadedImageSpotIds.contains($0.placeId)
                }
                let uploadedUrls = await placesAPIService.uploadSpotImages(spots: spotsForImageUpload)
                for spot in spotsForImageUpload {
                    self.uploadedImageSpotIds.insert(spot.placeId)
                }

                guard !Task.isCancelled else { return }

                // Surgical per-spot updates to avoid clobbering newer fetches
                if !resolvedRefs.isEmpty || !uploadedUrls.isEmpty {
                    for (pid, ref) in resolvedRefs {
                        if let idx = nearbySpots.firstIndex(where: { $0.placeId == pid }) {
                            nearbySpots[idx].photoReference = ref
                        }
                    }
                    for (pid, url) in uploadedUrls {
                        if let idx = nearbySpots.firstIndex(where: { $0.placeId == pid }) {
                            nearbySpots[idx].photoUrl = url
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
    
    /// Resolves photo reference for a single spot on-demand (called when a carousel card scrolls into view).
    /// Skips if the spot already has photo data or if a resolution is already in-flight.
    func resolvePhotoReferenceIfNeeded(for placeId: String) {
        guard let idx = nearbySpots.firstIndex(where: { $0.placeId == placeId }),
              nearbySpots[idx].photoReference == nil,
              nearbySpots[idx].photoUrl == nil,
              !photoResolutionInFlight.contains(placeId) else { return }

        photoResolutionInFlight.insert(placeId)

        Task { [weak self] in
            defer { self?.photoResolutionInFlight.remove(placeId) }
            guard let self else { return }

            guard let details = try? await placesAPIService.fetchPlaceDetails(placeId: placeId),
                  let ref = details.photoReference else { return }

            // Update the spot with the resolved reference
            if let liveIdx = nearbySpots.firstIndex(where: { $0.placeId == placeId }) {
                nearbySpots[liveIdx].photoReference = ref
            }

            // Persist to Supabase so future sessions don't re-fetch
            if let spot = nearbySpots.first(where: { $0.placeId == placeId }) {
                await placesAPIService.bulkUpsertSpots([spot])
            }

            // Upload the image and update the photo URL
            if let spot = nearbySpots.first(where: { $0.placeId == placeId }) {
                let urls = await placesAPIService.uploadSpotImages(spots: [spot])
                if let url = urls[placeId],
                   let finalIdx = nearbySpots.firstIndex(where: { $0.placeId == placeId }) {
                    nearbySpots[finalIdx].photoUrl = url
                }
            }
        }
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
            city: spot.city,
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
            city: nil,
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
    
    func loadSavedPlaces(forceRefresh: Bool = false) async {
        if !forceRefresh, hasLoadedSavedPlacesOnce, let last = savedPlacesLastLoadedAt,
           Date().timeIntervalSince(last) < savedPlacesStaleInterval {
            return
        }
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
            savedPlacesLastLoadedAt = Date()
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
            // Bias anchor slightly downward so the larger circular icon covers the underlying POI pin head.
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.6)
            
            // Get base icon
            var icon = iconForListTypes(placeWithMetadata.listTypes)
            
            // Scale up if this marker is selected
            if let selectedSpot = selectedSpot,
               selectedSpot.placeId == placeWithMetadata.spot.placeId,
               let baseIcon = icon {
                icon = scaleImage(baseIcon, to: 1.3)  // Slightly larger for selection emphasis
                marker.zIndex = 20  // Bring to front above other saved markers
            } else {
                // Ensure saved markers sit above any non-list markers that might be added in future.
                marker.zIndex = 10
            }
            
            marker.icon = icon
            
            return marker
        }
    }
    
    /// Returns the appropriate icon based on list membership. Delegates to MarkerIconHelper.
    private func iconForListTypes(_ listTypes: Set<ListType>) -> UIImage? {
        MarkerIconHelper.iconForListTypes(listTypes, cache: &cachedMarkerIcons)
    }

    private func createCustomMarkerIcon(systemName: String, color: UIColor) -> UIImage? {
        MarkerIconHelper.createCustomMarkerIcon(systemName: systemName, color: color)
    }

    /// Scales an image by the given scale factor
    private func scaleImage(_ image: UIImage, to scale: CGFloat) -> UIImage {
        MarkerIconHelper.scaleImage(image, to: scale)
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

