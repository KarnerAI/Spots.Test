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

    /// Formats a distance in meters into a locale-appropriate string.
    /// US locales render as "0.4 mi" / "320 ft"; metric locales as "1.2 km" / "320 m".
    /// Matches the convention used by Google Maps and Yelp — follows the device's
    /// region setting (`Locale.current.measurementSystem`).
    static func formattedDistance(_ meters: CLLocationDistance) -> String {
        formattedDistance(meters, locale: .current)
    }

    /// Locale-injectable variant for tests.
    static func formattedDistance(_ meters: CLLocationDistance, locale: Locale) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1
        formatter.numberFormatter.minimumFractionDigits = 0

        let usesImperial = locale.measurementSystem == .us
        let measurement: Measurement<UnitLength>
        if usesImperial {
            let miles = meters / 1609.344
            // Under 0.1 mi (~160m) render in feet for legibility.
            if miles < 0.1 {
                measurement = Measurement(value: meters * 3.28084, unit: .feet)
            } else {
                measurement = Measurement(value: miles, unit: .miles)
            }
        } else {
            // Under 1 km render in meters; longer in kilometers.
            if meters < 1000 {
                measurement = Measurement(value: meters, unit: .meters)
            } else {
                measurement = Measurement(value: meters / 1000, unit: .kilometers)
            }
        }
        return formatter.string(from: measurement)
    }
}
