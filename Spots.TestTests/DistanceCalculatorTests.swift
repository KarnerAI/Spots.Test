//
//  DistanceCalculatorTests.swift
//  Spots.TestTests
//
//  Covers locale-aware distance formatting used by the list detail view's
//  distance label and "Distance (Nearest)" sort. Pins behavior for US
//  (imperial) and a metric locale so future formatter swaps don't silently
//  change what users see.
//

import Testing
import CoreLocation
import Foundation
@testable import Spots_Test

struct DistanceCalculatorTests {

    private let us = Locale(identifier: "en_US")
    private let fr = Locale(identifier: "fr_FR")

    @Test func shortDistanceUsesFeetInUS() {
        // ~50 meters → ~164 ft, well under 0.1 mi threshold.
        let result = DistanceCalculator.formattedDistance(50, locale: us)
        #expect(result.contains("ft"))
    }

    @Test func mediumDistanceUsesMilesInUS() {
        // 800 meters ≈ 0.5 mi.
        let result = DistanceCalculator.formattedDistance(800, locale: us)
        #expect(result.contains("mi"))
        #expect(!result.contains("ft"))
    }

    @Test func longDistanceUsesMilesInUS() {
        // ~6800 km Brooklyn → Madrid, in miles ≈ 4225.
        let result = DistanceCalculator.formattedDistance(6_800_000, locale: us)
        #expect(result.contains("mi"))
    }

    @Test func shortDistanceUsesMetersInFR() {
        let result = DistanceCalculator.formattedDistance(50, locale: fr)
        // French uses "m" suffix for meters.
        #expect(result.contains("m"))
        #expect(!result.contains("km"))
    }

    @Test func mediumDistanceUsesKilometersInFR() {
        let result = DistanceCalculator.formattedDistance(1500, locale: fr)
        #expect(result.contains("km"))
    }

    @Test func distanceBetweenCoordinatesMatchesCLLocation() {
        let nyc = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let bk  = CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442)
        let computed = DistanceCalculator.distance(from: nyc, to: bk)
        // Reference: ~6 km between Manhattan and central Brooklyn.
        #expect(computed > 4_000 && computed < 10_000)
    }
}
