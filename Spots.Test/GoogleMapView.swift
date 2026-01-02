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
    var onMapReady: ((GMSMapView) -> Void)?
    var onCameraChanged: ((GMSCameraPosition) -> Void)?
    
    func makeUIView(context: Context) -> GMSMapView {
        // Default camera position (will be updated by parent)
        let defaultCamera = GMSCameraPosition.camera(
            withLatitude: 40.7128,
            longitude: -74.0060,
            zoom: 13.0  // Closer default zoom
        )
        
        // Use the modern initializer instead of deprecated map(withFrame:camera:)
        let mapView = GMSMapView(frame: .zero, camera: defaultCamera)
        mapView.isMyLocationEnabled = showUserLocation
        mapView.settings.myLocationButton = false // We'll use custom button
        mapView.settings.compassButton = false
        mapView.delegate = context.coordinator
        
        // Store map view reference in coordinator
        context.coordinator.mapView = mapView
        
        // Call onMapReady callback
        onMapReady?(mapView)
        
        return mapView
    }
    
    func updateUIView(_ mapView: GMSMapView, context: Context) {
        // Update camera position if changed
        if let cameraPosition = cameraPosition {
            mapView.animate(to: cameraPosition)
        }
        
        // Update user location visibility
        mapView.isMyLocationEnabled = showUserLocation
        
        // Update markers
        context.coordinator.updateMarkers(markers, on: mapView)
        
        // Update camera change handler
        context.coordinator.onCameraChanged = onCameraChanged
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, GMSMapViewDelegate {
        var mapView: GMSMapView?
        var currentMarkers: [GMSMarker] = []
        var onCameraChanged: ((GMSCameraPosition) -> Void)?
        
        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            onCameraChanged?(position)
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

