//
//  LocationGroupingTests.swift
//  Spots.TestTests
//
//  Verifies the spot → CityRowData / CountryRowData aggregation that drives
//  the Profile Travel Map. The same `LocationGrouping.matchesCity/Country`
//  helpers are reused by `ListDetailView.allSpotsInCity/.allSpotsInCountry`,
//  so a row's count is guaranteed to equal the marker count on the filtered
//  map — these tests pin that invariant.
//

import Testing
import Foundation
@testable import Spots_Test

struct LocationGroupingTests {

    private func spot(
        id: String,
        city: String? = nil,
        locality: String? = nil,
        country: String? = nil
    ) -> Spot {
        Spot(placeId: id, name: "Spot \(id)", city: city, locality: locality, country: country)
    }

    // MARK: - cityRows

    @Test func emptyInputProducesEmptyRows() {
        #expect(LocationGrouping.cityRows(from: []).isEmpty)
        #expect(LocationGrouping.countryRows(from: []).isEmpty)
    }

    @Test func citiesNormalizeWhitespaceAndCase() {
        let spots = [
            spot(id: "1", city: "New York"),
            spot(id: "2", city: "new york"),
            spot(id: "3", city: "  NEW YORK  "),
        ]
        let rows = LocationGrouping.cityRows(from: spots)
        #expect(rows.count == 1)
        #expect(rows[0].count == 3)
        #expect(rows[0].id == "new york")
    }

    @Test func citiesDropEmptyAndNil() {
        let spots = [
            spot(id: "1", city: "Paris"),
            spot(id: "2", city: ""),
            spot(id: "3", city: "   "),
            spot(id: "4", city: nil),
        ]
        let rows = LocationGrouping.cityRows(from: spots)
        #expect(rows.count == 1)
        #expect(rows[0].name == "Paris")
        #expect(rows[0].count == 1)
    }

    @Test func citiesSortByCountDescThenAlpha() {
        let spots = [
            spot(id: "1", city: "Boston"),
            spot(id: "2", city: "Austin"),
            spot(id: "3", city: "Austin"),
            spot(id: "4", city: "Chicago"),
            spot(id: "5", city: "Chicago"),
            spot(id: "6", city: "Chicago"),
        ]
        let rows = LocationGrouping.cityRows(from: spots)
        #expect(rows.map(\.name) == ["Chicago", "Austin", "Boston"])
        #expect(rows.map(\.count) == [3, 2, 1])
    }

    @Test func citiesAlphaTieBreak() {
        let spots = [
            spot(id: "1", city: "Boston"),
            spot(id: "2", city: "Austin"),
        ]
        let rows = LocationGrouping.cityRows(from: spots)
        #expect(rows.map(\.name) == ["Austin", "Boston"])
    }

    // MARK: - countryRows

    @Test func countriesIncludeFlag() {
        let spots = [
            spot(id: "1", country: "France"),
            spot(id: "2", country: "France"),
            spot(id: "3", country: "Japan"),
        ]
        let rows = LocationGrouping.countryRows(from: spots)
        #expect(rows.count == 2)
        let france = rows.first(where: { $0.id == "france" })
        let japan  = rows.first(where: { $0.id == "japan" })
        #expect(france?.flag == "🇫🇷")
        #expect(france?.count == 2)
        #expect(japan?.flag == "🇯🇵")
        #expect(japan?.count == 1)
    }

    @Test func unmappedCountryGetsNilFlag() {
        let rows = LocationGrouping.countryRows(from: [spot(id: "1", country: "Atlantis")])
        #expect(rows.count == 1)
        #expect(rows[0].flag == nil)
        #expect(rows[0].displayName == "Atlantis")
    }

    @Test func citySpotsStillCountInCountryWhenCityMissing() {
        let spots = [
            spot(id: "1", city: nil, country: "France"),
            spot(id: "2", city: "Paris", country: "France"),
        ]
        let cityRows = LocationGrouping.cityRows(from: spots)
        let countryRows = LocationGrouping.countryRows(from: spots)
        #expect(cityRows.count == 1)              // only spot 2
        #expect(cityRows[0].count == 1)
        #expect(countryRows.count == 1)
        #expect(countryRows[0].count == 2)        // both spots
    }

    // MARK: - matchesCity / matchesCountry

    @Test func matchesCityIsTrimmedAndCaseInsensitive() {
        let s = spot(id: "1", city: "New York")
        #expect(LocationGrouping.matchesCity(s, "new york"))
        #expect(LocationGrouping.matchesCity(s, "  NEW YORK "))
        #expect(!LocationGrouping.matchesCity(s, "newark"))
    }

    @Test func matchesCountrySymmetric() {
        let s = spot(id: "1", country: "Japan")
        #expect(LocationGrouping.matchesCountry(s, "japan"))
        #expect(LocationGrouping.matchesCountry(s, "JAPAN"))
        #expect(!LocationGrouping.matchesCountry(s, "Korea"))
    }

    @Test func matchesReturnsFalseForEmptySides() {
        #expect(!LocationGrouping.matchesCity(spot(id: "1", city: nil), "Paris"))
        #expect(!LocationGrouping.matchesCity(spot(id: "1", city: "Paris"), ""))
    }

    @Test func filterCountEqualsRowCount() {
        // Invariant: the number of spots that pass `matchesCity` must equal the
        // count shown on the corresponding CityRowData. ListDetailView's
        // filtered marker count therefore matches what the Profile row promised.
        let spots = [
            spot(id: "1", city: "Tokyo"),
            spot(id: "2", city: "tokyo"),
            spot(id: "3", city: "Osaka"),
            spot(id: "4", city: " TOKYO"),
        ]
        let rows = LocationGrouping.cityRows(from: spots)
        for row in rows {
            let matched = spots.filter { LocationGrouping.matchesCity($0, row.name) }.count
            #expect(matched == row.count)
        }
    }

    // MARK: - locality-aware grouping (regression: Île-de-France → Paris)

    /// Regression for the user-visible bug that motivated the locality column.
    /// Saved spots in Paris used to group under "Île-de-France" because the
    /// `city` column actually stored administrative_area_level_1. With the
    /// locality column populated, the same spots now group under "Paris".
    @Test func regression_groupsByLocalityWhenPresent() {
        let spots = [
            spot(id: "1", city: "Île-de-France", locality: "Paris"),
            spot(id: "2", city: "Île-de-France", locality: "Paris"),
            spot(id: "3", city: "Île-de-France", locality: "Versailles"),
        ]
        let rows = LocationGrouping.cityRows(from: spots)
        #expect(rows.map(\.name).sorted() == ["Paris", "Versailles"])
        #expect(rows.first(where: { $0.name == "Paris" })?.count == 2)
    }

    /// Pre-backfill rows (no locality) fall back to the region label so they
    /// keep grouping somewhere instead of dropping out of the Travel Map.
    @Test func fallsBackToCityWhenLocalityNil() {
        let spots = [
            spot(id: "1", city: "Île-de-France", locality: nil),
            spot(id: "2", city: "Île-de-France", locality: nil),
        ]
        let rows = LocationGrouping.cityRows(from: spots)
        #expect(rows.count == 1)
        #expect(rows[0].name == "Île-de-France")
        #expect(rows[0].count == 2)
    }

    /// Mixed-state: some rows backfilled, some not. They should NOT collapse
    /// into one bucket — "Paris" and "Île-de-France" are different display
    /// keys until backfill finishes the migration.
    @Test func mixedPreAndPostBackfillStaySeparate() {
        let spots = [
            spot(id: "1", city: "Île-de-France", locality: "Paris"),
            spot(id: "2", city: "Île-de-France", locality: nil),
        ]
        let rows = LocationGrouping.cityRows(from: spots)
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.name)) == ["Paris", "Île-de-France"])
    }

    @Test func matchesCityPrefersLocality() {
        let s = spot(id: "1", city: "Île-de-France", locality: "Paris")
        #expect(LocationGrouping.matchesCity(s, "Paris"))
        // The region label no longer matches when locality is present —
        // matches the new display behavior.
        #expect(!LocationGrouping.matchesCity(s, "Île-de-France"))
    }
}
