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

    // MARK: - Text Search request body (Round 7)

    @Test func textSearch_distanceMode_includesRankPreferenceAndBias() {
        let body = PlacesAPIService.buildTextSearchRequestBody(
            query: "pizza",
            location: Self.nyc,
            rankPreference: .distance,
            radius: 50_000
        )

        #expect(body["textQuery"] as? String == "pizza")
        #expect(body["rankPreference"] as? String == "DISTANCE")

        let bias = body["locationBias"] as? [String: Any]
        #expect(bias != nil)
        let circle = bias?["circle"] as? [String: Any]
        #expect(circle?["radius"] as? Double == 50_000)
        let center = circle?["center"] as? [String: Any]
        #expect(center?["latitude"] as? Double == 40.7128)
        #expect(center?["longitude"] as? Double == -74.0060)
    }

    @Test func textSearch_relevanceMode_emitsCorrectRankString() {
        // `.relevance` and `.distance` are the only two valid rank strings.
        // Guard the raw value mapping so a future rename of the enum case
        // can't silently send Google a string it rejects with a 400.
        let body = PlacesAPIService.buildTextSearchRequestBody(
            query: "pizza",
            location: Self.nyc,
            rankPreference: .relevance,
            radius: 50_000
        )
        #expect(body["rankPreference"] as? String == "RELEVANCE")
    }

    @Test func textSearch_noLocation_omitsBiasAndRankPreference() {
        // Google rejects rankPreference=DISTANCE without a location to
        // measure from. The builder must strip BOTH fields when location
        // is nil — leaving rankPreference set would 400 the request.
        let body = PlacesAPIService.buildTextSearchRequestBody(
            query: "pizza",
            location: nil,
            rankPreference: .distance,
            radius: 50_000
        )

        #expect(body["textQuery"] as? String == "pizza")
        #expect(body["locationBias"] == nil)
        #expect(body["rankPreference"] == nil)
    }

    @Test func textSearch_useTextQueryNotInput() {
        // Text Search uses `textQuery`; Autocomplete uses `input`. If a
        // future refactor accidentally unifies these, Google's API will
        // ignore the wrong field and return unrelated results — silent
        // regression that wouldn't surface in a smoke test. Pin the key.
        let body = PlacesAPIService.buildTextSearchRequestBody(
            query: "pizza",
            location: Self.nyc,
            rankPreference: .distance,
            radius: 50_000
        )

        #expect(body["textQuery"] != nil)
        #expect(body["input"] == nil)
    }

    // MARK: - includedType detection (Round 8)

    @Test func detectIncludedType_singleKeywordMatches() {
        // Most common case: user types a single category word.
        #expect(PlacesAPIService.detectIncludedType(from: "pizza") == "restaurant")
        #expect(PlacesAPIService.detectIncludedType(from: "coffee") == "cafe")
        #expect(PlacesAPIService.detectIncludedType(from: "cocktails") == "bar")
        #expect(PlacesAPIService.detectIncludedType(from: "bakery") == "bakery")
    }

    @Test func detectIncludedType_multiWordQueryWithKeywordMatches() {
        // User types a place name that happens to contain a category word —
        // we still want to filter Google's candidate set to restaurants.
        // Filtering doesn't hurt here: a restaurant named "Joe's Pizza"
        // stays in scope; a toy store named "Pizzazzz Toyz" gets cut.
        #expect(PlacesAPIService.detectIncludedType(from: "Joe's Pizza") == "restaurant")
        #expect(PlacesAPIService.detectIncludedType(from: "pizza near me") == "restaurant")
        #expect(PlacesAPIService.detectIncludedType(from: "best coffee in soho") == "cafe")
    }

    @Test func detectIncludedType_caseInsensitive() {
        // Users mid-type with capitalization shouldn't break the mapper.
        #expect(PlacesAPIService.detectIncludedType(from: "PIZZA") == "restaurant")
        #expect(PlacesAPIService.detectIncludedType(from: "Coffee") == "cafe")
    }

    @Test func detectIncludedType_partialTypingReturnsNil() {
        // The mapper requires a whole-token match. Partial typing of a
        // keyword shouldn't trigger the filter early — that would change
        // the request shape mid-keystroke as the user types and could
        // surprise the cache.
        #expect(PlacesAPIService.detectIncludedType(from: "piz") == nil)
        #expect(PlacesAPIService.detectIncludedType(from: "coff") == nil)
    }

    @Test func detectIncludedType_unrelatedQueryReturnsNil() {
        // Free-text searches for specific places (no category signal) fall
        // through to plain Text Search without a filter.
        #expect(PlacesAPIService.detectIncludedType(from: "wework") == nil)
        #expect(PlacesAPIService.detectIncludedType(from: "Eiffel Tower") == nil)
        #expect(PlacesAPIService.detectIncludedType(from: "Central Park") == nil)
    }

    @Test func detectIncludedType_emptyOrWhitespaceReturnsNil() {
        // Defensive: empty/whitespace queries shouldn't crash or match.
        #expect(PlacesAPIService.detectIncludedType(from: "") == nil)
        #expect(PlacesAPIService.detectIncludedType(from: "   ") == nil)
    }

    @Test func textSearch_includedTypeInBodyWhenProvided() {
        // The request body builder must thread `includedType` through to
        // the API request. Without this, the mapper would compute the
        // right type and silently fail to apply it.
        let body = PlacesAPIService.buildTextSearchRequestBody(
            query: "pizza",
            location: Self.nyc,
            rankPreference: .distance,
            radius: 50_000,
            includedType: "restaurant"
        )
        #expect(body["includedType"] as? String == "restaurant")
    }

    @Test func textSearch_includedTypeOmittedWhenNil() {
        // For queries without a category match, no filter — let Google
        // do its full text matching without artificial type constraint.
        let body = PlacesAPIService.buildTextSearchRequestBody(
            query: "wework",
            location: Self.nyc,
            rankPreference: .distance,
            radius: 50_000,
            includedType: nil
        )
        #expect(body["includedType"] == nil)
    }
}
