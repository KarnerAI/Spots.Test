//
//  CountryFlag.swift
//  Spots.Test
//
//  Maps a free-text country string (e.g. "United States", "USA", "south korea")
//  to an ISO 3166-1 alpha-2 code and a flag emoji. Pure runtime lookup; the
//  `spots` schema only stores the country name as a string, so we resolve the
//  flag at display time rather than during save/migration.
//

import Foundation

enum CountryFlag {
    /// Flag emoji for a free-text country name, or `nil` if it can't be resolved.
    static func emoji(for country: String?) -> String? {
        guard let code = isoCode(for: country) else { return nil }
        return flagEmoji(for: code)
    }

    /// ISO 3166-1 alpha-2 code (uppercase) for a free-text country name, or `nil`.
    static func isoCode(for country: String?) -> String? {
        guard let raw = country?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let key = raw.lowercased()

        // Direct alias hit (handles informal names + common abbreviations).
        if let aliased = aliases[key] { return aliased }

        // Two-letter input that's already a valid region code.
        if raw.count == 2, validIsoCodes.contains(raw.uppercased()) {
            return raw.uppercased()
        }

        // Localized-name lookup (e.g. "United States" → "US"). Built once.
        if let code = localizedNameToIsoCode[key] { return code }

        return nil
    }

    // MARK: - Internals

    /// Convert ISO alpha-2 to the regional indicator flag emoji.
    /// "US" → 🇺🇸 via 0x1F1E6 + (letter - "A").
    private static func flagEmoji(for isoCode: String) -> String? {
        let upper = isoCode.uppercased()
        guard upper.count == 2,
              upper.unicodeScalars.allSatisfy({ ("A"..."Z").contains(Character($0)) })
        else { return nil }

        let base: UInt32 = 0x1F1E6
        let aValue = UnicodeScalar("A").value
        var result = ""
        for ch in upper.unicodeScalars {
            guard let scalar = UnicodeScalar(base + (ch.value - aValue)) else { return nil }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    /// Common informal names / abbreviations Locale doesn't resolve on its own.
    private static let aliases: [String: String] = [
        "usa": "US",
        "u.s.": "US",
        "u.s.a.": "US",
        "united states of america": "US",
        "america": "US",
        "uk": "GB",
        "u.k.": "GB",
        "great britain": "GB",
        "britain": "GB",
        "england": "GB",
        "scotland": "GB",
        "wales": "GB",
        "northern ireland": "GB",
        "south korea": "KR",
        "north korea": "KP",
        "russia": "RU",
        "vietnam": "VN",
        "iran": "IR",
        "syria": "SY",
        "laos": "LA",
        "moldova": "MD",
        "tanzania": "TZ",
        "venezuela": "VE",
        "bolivia": "BO",
        "taiwan": "TW",
        "macau": "MO",
        "hong kong": "HK",
        "uae": "AE",
        "u.a.e.": "AE",
        "ivory coast": "CI",
        "cape verde": "CV",
        "czech republic": "CZ",
        "czechia": "CZ",
        "burma": "MM",
        "swaziland": "SZ",
    ]

    /// Set of valid ISO alpha-2 region codes per the current runtime.
    private static let validIsoCodes: Set<String> = {
        if #available(iOS 16, *) {
            return Set(Locale.Region.isoRegions.map { $0.identifier })
        } else {
            return Set(Locale.isoRegionCodes)
        }
    }()

    /// "united states" → "US", "france" → "FR", etc. Built once from the
    /// system locale's localized region names. Lower-cased keys for tolerant
    /// lookup against arbitrary user-facing strings.
    private static let localizedNameToIsoCode: [String: String] = {
        var map: [String: String] = [:]
        let referenceLocale = Locale(identifier: "en_US_POSIX")
        for code in validIsoCodes {
            if let name = referenceLocale.localizedString(forRegionCode: code) {
                map[name.lowercased()] = code
            }
            // Also include the device's current localization so a user whose
            // device language writes "Estados Unidos" still resolves to US.
            if let localizedName = Locale.current.localizedString(forRegionCode: code) {
                map[localizedName.lowercased()] = code
            }
        }
        return map
    }()
}
