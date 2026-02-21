//
//  GoogleMapView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI
import GoogleMaps
import CoreLocation

struct GoogleMapView: UIViewRepresentable {
    @Binding var cameraPosition: GMSCameraPosition?
    @Binding var markers: [GMSMarker]
    @Binding var showUserLocation: Bool
    @Binding var forceCameraUpdate: Bool
    var onMapReady: ((GMSMapView) -> Void)?
    var onCameraChanged: ((GMSCameraPosition) -> Void)?
    var onMarkerTapped: ((GMSMarker) -> Void)?
    var onPOITapped: ((String, String, CLLocationCoordinate2D) -> Void)?
    var onMapTapped: (() -> Void)?
    
    func makeUIView(context: Context) -> GMSMapView {
        // Use the OS-cached location if available so the map opens near the user.
        // Falls back to a neutral world-level view if no cached fix exists yet.
        let cachedCoord = CLLocationManager().location?.coordinate
        let initialCamera: GMSCameraPosition
        if let coord = cachedCoord {
            initialCamera = GMSCameraPosition.camera(
                withLatitude: coord.latitude,
                longitude: coord.longitude,
                zoom: 17.0
            )
        } else {
            // Fallback: zoom out to world level so no single city is implied
            initialCamera = GMSCameraPosition.camera(
                withLatitude: 0,
                longitude: 0,
                zoom: 2.0
            )
        }
        let defaultCamera = initialCamera
        
        // Use the modern initializer
        let mapView = GMSMapView()
        mapView.camera = defaultCamera
        mapView.isMyLocationEnabled = showUserLocation
        mapView.settings.myLocationButton = false // We'll use custom button
        mapView.settings.compassButton = false
        mapView.delegate = context.coordinator
        
        // Store map view reference in coordinator
        context.coordinator.mapView = mapView
        
        // Call onMapReady callback
        onMapReady?(mapView)
        
        // Report initial camera position
        DispatchQueue.main.async {
            context.coordinator.onCameraChanged?(defaultCamera)
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: GMSMapView, context: Context) {
        // #region agent log
        print("🟢 DEBUG: updateUIView called")
        if let camPos = cameraPosition {
            print("🟢 DEBUG: cameraPosition = lat=\(camPos.target.latitude), lng=\(camPos.target.longitude), zoom=\(camPos.zoom)")
        } else {
            print("🟢 DEBUG: cameraPosition is NIL")
        }
        if let lastPos = context.coordinator.lastCameraPosition {
            print("🟢 DEBUG: lastCameraPosition = lat=\(lastPos.target.latitude), lng=\(lastPos.target.longitude), zoom=\(lastPos.zoom)")
        } else {
            print("🟢 DEBUG: lastCameraPosition is NIL")
        }
        // #endregion
        
        // Update camera position if changed
        if let cameraPosition = cameraPosition {
            // If forceCameraUpdate is true, always animate (bypass threshold check)
            if forceCameraUpdate {
                // #region agent log
                print("🟣 DEBUG: FORCE ANIMATING (forceCameraUpdate=true) to lat=\(cameraPosition.target.latitude), lng=\(cameraPosition.target.longitude), zoom=\(cameraPosition.zoom)")
                // #endregion
                
                mapView.animate(to: cameraPosition)
                context.coordinator.lastCameraPosition = cameraPosition
            } else if let lastPosition = context.coordinator.lastCameraPosition {
                // Check if position has changed (using small threshold to account for floating point precision)
                let latDiff = abs(lastPosition.target.latitude - cameraPosition.target.latitude)
                let lngDiff = abs(lastPosition.target.longitude - cameraPosition.target.longitude)
                let zoomDiff = abs(lastPosition.zoom - cameraPosition.zoom)
                
                let hasChanged = latDiff > 0.0001 || lngDiff > 0.0001 || zoomDiff > 0.1
                
                // #region agent log
                print("🟡 DEBUG: Threshold check - latDiff=\(latDiff), lngDiff=\(lngDiff), zoomDiff=\(zoomDiff), hasChanged=\(hasChanged)")
                // #endregion
                
                if hasChanged {
                    // #region agent log
                    print("🟣 DEBUG: ANIMATING to lat=\(cameraPosition.target.latitude), lng=\(cameraPosition.target.longitude), zoom=\(cameraPosition.zoom)")
                    // #endregion
                    
                    mapView.animate(to: cameraPosition)
                    context.coordinator.lastCameraPosition = cameraPosition
                } else {
                    // #region agent log
                    print("⚫ DEBUG: Skipping animation - hasChanged is false")
                    // #endregion
                }
            } else {
                // #region agent log
                print("🔵 DEBUG: First time setting position - lat=\(cameraPosition.target.latitude), lng=\(cameraPosition.target.longitude), zoom=\(cameraPosition.zoom)")
                // #endregion
                
                // First time setting position - use direct camera assignment for instant positioning without animation
                mapView.camera = cameraPosition
                context.coordinator.lastCameraPosition = cameraPosition
            }
        } else {
            // #region agent log
            print("⚪ DEBUG: cameraPosition is NIL in updateUIView")
            // #endregion
        }
        
        // Update user location visibility
        mapView.isMyLocationEnabled = showUserLocation
        
        // Update markers
        context.coordinator.updateMarkers(markers, on: mapView)
        
        // Update camera change handler
        context.coordinator.onCameraChanged = onCameraChanged
        
        // Update marker tap handler
        context.coordinator.onMarkerTapped = onMarkerTapped
        
        // Update POI tap handler
        context.coordinator.onPOITapped = onPOITapped
        
        // Update map tap handler
        context.coordinator.onMapTapped = onMapTapped
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, GMSMapViewDelegate {
        var mapView: GMSMapView?
        var currentMarkers: [GMSMarker] = []
        var onCameraChanged: ((GMSCameraPosition) -> Void)?
        var onMarkerTapped: ((GMSMarker) -> Void)?
        var onPOITapped: ((String, String, CLLocationCoordinate2D) -> Void)?
        var onMapTapped: (() -> Void)?
        var lastCameraPosition: GMSCameraPosition?
        
        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            onCameraChanged?(position)
        }
        
        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            onMarkerTapped?(marker)
            // Return true to indicate we handled the tap (prevents default info window)
            return true
        }
        
        func mapView(_ mapView: GMSMapView, didTapPOIWithPlaceID placeID: String, name: String, location: CLLocationCoordinate2D) {
            onPOITapped?(placeID, name, location)
        }
        
        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            onMapTapped?()
        }
        
        func updateMarkers(_ newMarkers: [GMSMarker], on mapView: GMSMapView) {
            // Remove old markers
            for marker in currentMarkers {
                marker.map = nil
            }
            
            // Add new markers
            currentMarkers = newMarkers
            for marker in newMarkers {
                marker.map = mapView
            }
        }
    }
}

