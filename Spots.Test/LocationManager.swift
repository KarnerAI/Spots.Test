//
//  LocationManager.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: Error?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func requestLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestLocationPermission()
            return
        }

        // Immediately publish the OS-cached location (if recent) so the map can
        // center without waiting for a fresh GPS fix.
        if let cached = locationManager.location,
           cached.horizontalAccuracy > 0,
           cached.timestamp.timeIntervalSinceNow > -60 {
            self.location = cached
        }

        // startUpdatingLocation uses cached + network + GPS progressively,
        // giving a much faster first fix than the one-shot requestLocation().
        // The delegate stops updates once an accurate-enough fix arrives.
        locationManager.startUpdatingLocation()
    }
    
    func getCurrentLocation() -> CLLocation? {
        return location
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Take the most recent fix. Reject invalid or highly inaccurate readings
        // (negative accuracy = invalid; > 100m = too coarse to be useful).
        guard let location = locations.last,
              location.horizontalAccuracy > 0,
              location.horizontalAccuracy < 100 else { return }
        self.location = location
        self.locationError = nil
        // Stop continuous updates — we only needed one good fix.
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.locationError = error
        print("Location error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            requestLocation()
        case .denied, .restricted:
            location = nil
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}

