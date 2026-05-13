//
//  GoogleMapsLink.swift
//  Spots.Test
//
//  Shared builder for the "Open in Google Maps" deep link. Centralises the
//  query construction so future tweaks (e.g. `comgooglemaps://` fallback,
//  Apple Maps option) land in one file instead of three call sites.
//

import Foundation

/// Any model carrying enough Place identity to build a Google Maps deep link.
/// `Spot` and `NearbySpot` both conform.
protocol GoogleMapsLinkable {
    var name: String { get }
    var placeId: String { get }
}

extension Spot: GoogleMapsLinkable {}
extension NearbySpot: GoogleMapsLinkable {}

enum GoogleMapsLink {
    /// Build the universal-link form used by Google Maps. Resolves in the
    /// Google Maps app if installed, otherwise opens the mobile web page.
    static func url(for place: GoogleMapsLinkable) -> URL? {
        let encodedName = place.name
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(
            string: "https://www.google.com/maps/search/?api=1&query=\(encodedName)&query_place_id=\(place.placeId)"
        )
    }
}
