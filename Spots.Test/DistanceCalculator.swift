//
//  DistanceCalculator.swift
//  Spots.Test
//
//  Shared distance utility — single source of truth for distance calculations and formatting.
//

import Foundation
import CoreLocation

enum DistanceCalculator {

    // MARK: - Distance Calculation

    /// Returns the distance in meters between two coordinates.
    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }

    /// Returns the distance in meters from `userLocation` to the given coordinate.
    static func distance(from userLocation: CLLocation, to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return userLocation.distance(from: target)
    }

    // MARK: - Formatting

    /// Formats a distance in meters into a human-readable string (e.g., "250 ft" or "1.2 mi").
    /// Distances under 0.1 miles are shown in feet; everything else in miles with one decimal.
    static func formattedDistance(_ meters: CLLocationDistance) -> String {
        let miles = meters / 1609.34

        if miles < 0.1 {
            let feet = meters * 3.28084
            return String(format: "%.0f ft", feet)
        } else {
            return String(format: "%.1f mi", miles)
        }
    }
}
