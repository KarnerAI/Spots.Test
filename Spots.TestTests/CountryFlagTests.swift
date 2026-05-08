//
//  CountryFlagTests.swift
//  Spots.TestTests
//
//  Verifies the runtime country-name → flag emoji lookup powering the
//  Profile Travel Map's Countries tab. We cover canonical names, common
//  aliases, whitespace tolerance, two-letter ISO inputs, and the unmapped
//  fallback path so the "globe icon" branch in ProfileView's countryRow
//  stays exercised.
//

import Testing
@testable import Spots_Test

struct CountryFlagTests {

    @Test func canonicalEnglishName() {
        #expect(CountryFlag.emoji(for: "United States") == "🇺🇸")
        #expect(CountryFlag.emoji(for: "France") == "🇫🇷")
        #expect(CountryFlag.emoji(for: "Japan") == "🇯🇵")
    }

    @Test func aliasInformalName() {
        #expect(CountryFlag.emoji(for: "USA") == "🇺🇸")
        #expect(CountryFlag.emoji(for: "UK") == "🇬🇧")
        #expect(CountryFlag.emoji(for: "South Korea") == "🇰🇷")
        #expect(CountryFlag.emoji(for: "Czech Republic") == "🇨🇿")
    }

    @Test func trimAndCaseInsensitive() {
        #expect(CountryFlag.emoji(for: "  france  ") == "🇫🇷")
        #expect(CountryFlag.emoji(for: "FRANCE") == "🇫🇷")
        #expect(CountryFlag.emoji(for: "uNiTeD sTaTeS") == "🇺🇸")
    }

    @Test func twoLetterIsoCode() {
        #expect(CountryFlag.emoji(for: "US") == "🇺🇸")
        #expect(CountryFlag.emoji(for: "fr") == "🇫🇷")
    }

    @Test func unmappedReturnsNil() {
        #expect(CountryFlag.emoji(for: "Atlantis") == nil)
        #expect(CountryFlag.emoji(for: "ZZ") == nil)
    }

    @Test func emptyAndNilReturnNil() {
        #expect(CountryFlag.emoji(for: nil) == nil)
        #expect(CountryFlag.emoji(for: "") == nil)
        #expect(CountryFlag.emoji(for: "   ") == nil)
    }

    @Test func isoCodeLookupParity() {
        #expect(CountryFlag.isoCode(for: "United States") == "US")
        #expect(CountryFlag.isoCode(for: "usa") == "US")
        #expect(CountryFlag.isoCode(for: "Atlantis") == nil)
    }
}
