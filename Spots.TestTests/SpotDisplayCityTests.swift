//
//  SpotDisplayCityTests.swift
//  Spots.TestTests
//
//  Covers `Spot.displayCity` — the property that masks the misnamed `city`
//  column (which actually stores administrative_area_level_1) by preferring
//  the true `locality` value. The fallback rule + empty-string handling are
//  what every user-facing city label depends on.
//

import Testing
import Foundation
@testable import Spots_Test

struct SpotDisplayCityTests {

    private func makeSpot(city: String? = nil, locality: String? = nil) -> Spot {
        Spot(placeId: "p", name: "n", city: city, locality: locality)
    }

    @Test func localityWinsWhenBothPresent() {
        let spot = makeSpot(city: "Île-de-France", locality: "Paris")
        #expect(spot.displayCity == "Paris")
    }

    @Test func fallsBackToCityWhenLocalityNil() {
        let spot = makeSpot(city: "Île-de-France", locality: nil)
        #expect(spot.displayCity == "Île-de-France")
    }

    @Test func fallsBackToCityWhenLocalityEmpty() {
        // Empty string is the edge case that motivated normalizing in the
        // computed property. Google occasionally returns locality longText: "".
        let spot = makeSpot(city: "Lazio", locality: "")
        #expect(spot.displayCity == "Lazio")
    }

    @Test func fallsBackToCityWhenLocalityWhitespace() {
        let spot = makeSpot(city: "Lazio", locality: "   ")
        #expect(spot.displayCity == "Lazio")
    }

    @Test func returnsNilWhenBothMissing() {
        let spot = makeSpot(city: nil, locality: nil)
        #expect(spot.displayCity == nil)
    }

    @Test func returnsNilWhenBothEmpty() {
        let spot = makeSpot(city: "", locality: "")
        #expect(spot.displayCity == nil)
    }

    @Test func trimsLocalityWhitespace() {
        let spot = makeSpot(city: "Île-de-France", locality: "  Paris  ")
        #expect(spot.displayCity == "Paris")
    }

    @Test func trimsCityWhitespaceOnFallback() {
        let spot = makeSpot(city: "  Île-de-France  ", locality: nil)
        #expect(spot.displayCity == "Île-de-France")
    }

    /// Regression for the bug that motivated this change: a saved Eiffel
    /// Tower stored "Île-de-France" in `city` and now stores "Paris" in
    /// `locality`. The user-visible label must be "Paris".
    @Test func regression_eiffelTowerShowsParis() {
        let eiffel = Spot(
            placeId: "ChIJLU7jZClu5kcR4PcOOO6p3I0",
            name: "Eiffel Tower",
            city: "Île-de-France",
            locality: "Paris",
            country: "France"
        )
        #expect(eiffel.displayCity == "Paris")
    }
}
