//
//  PlacesAPIServiceTests.swift
//  Spots.TestTests
//
//  Guards the request-body shape for Google Places Autocomplete (New).
//  The two-tier autocomplete in PlacesAPIService relies on a hard
//  `locationRestriction` for Tier 1 and a soft `locationBias` for Tier 2 —
//  a future refactor that accidentally swaps or drops either field would
//  silently regress to the "Pizza Hut HQ instead of nearby pizza" bug
//  Round 6 was created to fix. These tests pin the body shape per mode.
//

import Testing
import Foundation
import CoreLocation
@testable import Spots_Test

struct PlacesAPIServiceTests {

    private static let nyc = CLLocation(latitude: 40.7128, longitude: -74.0060)

    @Test func restrictionModeIncludesLocationRestriction() {
        let body = PlacesAPIService.buildAutocompleteRequestBody(
            query: "pizza",
            location: Self.nyc,
            mode: .restriction(radius: 50_000)
        )

        #expect(body["input"] as? String == "pizza")
        #expect(body["includedPrimaryTypes"] as? [String] == ["establishment"])
        #expect(body["locationBias"] == nil)

        let restriction = body["locationRestriction"] as? [String: Any]
        #expect(restriction != nil)
        let circle = restriction?["circle"] as? [String: Any]
        #expect(circle?["radius"] as? Double == 50_000)
        let center = circle?["center"] as? [String: Any]
        #expect(center?["latitude"] as? Double == 40.7128)
        #expect(center?["longitude"] as? Double == -74.0060)
    }

    @Test func biasModeIncludesLocationBias() {
        let body = PlacesAPIService.buildAutocompleteRequestBody(
            query: "eiffel tower",
            location: Self.nyc,
            mode: .bias(radius: 50_000)
        )

        #expect(body["input"] as? String == "eiffel tower")
        #expect(body["includedPrimaryTypes"] as? [String] == ["establishment"])
        // Crucial: bias mode must NOT also set restriction. Earlier drafts
        // accidentally populated both, which would have rejected all
        // out-of-radius results despite the bias request.
        #expect(body["locationRestriction"] == nil)

        let bias = body["locationBias"] as? [String: Any]
        #expect(bias != nil)
        let circle = bias?["circle"] as? [String: Any]
        #expect(circle?["radius"] as? Double == 50_000)
    }

    @Test func noLocationOmitsBothBiasAndRestriction() {
        let body = PlacesAPIService.buildAutocompleteRequestBody(
            query: "pizza",
            location: nil,
            mode: .restriction(radius: 50_000)
        )

        // Even when the caller specifies a mode, a nil location must result
        // in an unconstrained query — anything else would silently turn the
        // restriction into an empty-result trap when location services
        // aren't yet available.
        #expect(body["locationRestriction"] == nil)
        #expect(body["locationBias"] == nil)
        #expect(body["input"] as? String == "pizza")
        #expect(body["includedPrimaryTypes"] as? [String] == ["establishment"])
    }

    @Test func explicitNoneModeOmitsBothEvenWithLocation() {
        // Defensive: `.none` mode is reachable from the orchestrator when
        // location is nil. With location set, it should still produce an
        // unconstrained query so this codepath stays a pure "no locality"
        // request and never silently picks one of the other modes.
        let body = PlacesAPIService.buildAutocompleteRequestBody(
            query: "pizza",
            location: Self.nyc,
            mode: .none
        )

        #expect(body["locationRestriction"] == nil)
        #expect(body["locationBias"] == nil)
        #expect(body["input"] as? String == "pizza")
    }

    @Test func allModesKeepIncludedPrimaryTypes() {
        // `includedPrimaryTypes` controls which Google Places types are
        // eligible. Dropping it has been a refactor footgun in this file
        // before — guard explicitly across all three modes so a future
        // edit can't silently remove it from one and break parity.
        for mode in [
            PlacesAPIService.AutocompleteMode.restriction(radius: 50_000),
            .bias(radius: 50_000),
            .none
        ] {
            let body = PlacesAPIService.buildAutocompleteRequestBody(
                query: "anything",
                location: Self.nyc,
                mode: mode
            )
            #expect(body["includedPrimaryTypes"] as? [String] == ["establishment"], "Missing includedPrimaryTypes for mode \(mode)")
        }
    }
}
