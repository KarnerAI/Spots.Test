//
//  NearbySpotLocalityTests.swift
//  Spots.TestTests
//
//  Covers locality extraction in NearbyPlaceResult.toNearbySpot and
//  PlaceDetailsResponse.toNearbySpot. The boundary normalizer turns
//  empty/whitespace `longText` into nil so the read-side fallback in
//  Spot.displayCity behaves correctly.
//

import Testing
import Foundation
@testable import Spots_Test

struct NearbySpotLocalityTests {

    // MARK: - Helpers

    private func decodeNearby(_ json: String) throws -> NearbySpot? {
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(NearbyPlaceResult.self, from: data)
        return response.toNearbySpot()
    }

    private func decodeDetails(_ json: String) throws -> NearbySpot? {
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(PlaceDetailsResponse.self, from: data)
        return response.toNearbySpot()
    }

    private func json(addressComponents: String) -> String {
        """
        {
          "id": "p1",
          "displayName": { "text": "Test", "languageCode": "en" },
          "shortFormattedAddress": "Somewhere",
          "location": { "latitude": 48.85, "longitude": 2.29 },
          "types": ["tourist_attraction"],
          "addressComponents": \(addressComponents)
        }
        """
    }

    // MARK: - NearbyPlaceResult

    @Test func nearbyPlaceParsesLocalityAndRegion() throws {
        let json = json(addressComponents: """
        [
          { "types": ["locality"], "longText": "Paris", "shortText": "Paris" },
          { "types": ["administrative_area_level_1"], "longText": "Île-de-France", "shortText": "IDF" },
          { "types": ["country"], "longText": "France", "shortText": "FR" }
        ]
        """)
        let spot = try #require(try decodeNearby(json))
        #expect(spot.locality == "Paris")
        #expect(spot.city == "Île-de-France")
        #expect(spot.country == "France")
        // Round-trip through toSpot to confirm displayCity surfaces Paris.
        #expect(spot.toSpot().displayCity == "Paris")
    }

    @Test func nearbyPlaceMissingLocalityIsNil() throws {
        // Remote attractions (national parks, monuments outside a city) often
        // have no `locality` component. Spot.displayCity should fall back to
        // the region label so the UI never shows blank.
        let json = json(addressComponents: """
        [
          { "types": ["administrative_area_level_1"], "longText": "Wyoming", "shortText": "WY" },
          { "types": ["country"], "longText": "United States", "shortText": "US" }
        ]
        """)
        let spot = try #require(try decodeNearby(json))
        #expect(spot.locality == nil)
        #expect(spot.city == "Wyoming")
        #expect(spot.toSpot().displayCity == "Wyoming")
    }

    @Test func nearbyPlaceEmptyLocalityNormalizesToNil() throws {
        // Edge case: Google sometimes returns longText: "". Without the
        // boundary normalizer it would land in the DB as "" and bypass the
        // `?? city` fallback in displayCity.
        let json = json(addressComponents: """
        [
          { "types": ["locality"], "longText": "", "shortText": "" },
          { "types": ["administrative_area_level_1"], "longText": "Lazio", "shortText": "Lazio" }
        ]
        """)
        let spot = try #require(try decodeNearby(json))
        #expect(spot.locality == nil)
        #expect(spot.toSpot().displayCity == "Lazio")
    }

    @Test func nearbyPlaceWhitespaceLocalityNormalizesToNil() throws {
        let json = json(addressComponents: """
        [
          { "types": ["locality"], "longText": "   ", "shortText": "   " },
          { "types": ["administrative_area_level_1"], "longText": "Lazio", "shortText": "Lazio" }
        ]
        """)
        let spot = try #require(try decodeNearby(json))
        #expect(spot.locality == nil)
        #expect(spot.toSpot().displayCity == "Lazio")
    }

    @Test func nearbyPlaceNilAddressComponentsYieldsNilLocalityAndCity() throws {
        let json = """
        {
          "id": "p1",
          "displayName": { "text": "Test", "languageCode": "en" },
          "shortFormattedAddress": "Somewhere",
          "location": { "latitude": 0, "longitude": 0 },
          "types": ["tourist_attraction"]
        }
        """
        let spot = try #require(try decodeNearby(json))
        #expect(spot.locality == nil)
        #expect(spot.city == nil)
        #expect(spot.toSpot().displayCity == nil)
    }

    // MARK: - PlaceDetailsResponse mirrors PlaceResult

    @Test func placeDetailsParsesLocalityAndRegion() throws {
        let json = json(addressComponents: """
        [
          { "types": ["locality"], "longText": "Rome", "shortText": "Rome" },
          { "types": ["administrative_area_level_1"], "longText": "Lazio", "shortText": "Lazio" },
          { "types": ["country"], "longText": "Italy", "shortText": "IT" }
        ]
        """)
        let spot = try #require(try decodeDetails(json))
        #expect(spot.locality == "Rome")
        #expect(spot.city == "Lazio")
        #expect(spot.country == "Italy")
        #expect(spot.toSpot().displayCity == "Rome")
    }

    @Test func placeDetailsEmptyLocalityNormalizesToNil() throws {
        let json = json(addressComponents: """
        [
          { "types": ["locality"], "longText": "", "shortText": "" },
          { "types": ["administrative_area_level_1"], "longText": "Lazio", "shortText": "Lazio" }
        ]
        """)
        let spot = try #require(try decodeDetails(json))
        #expect(spot.locality == nil)
        #expect(spot.toSpot().displayCity == "Lazio")
    }
}
