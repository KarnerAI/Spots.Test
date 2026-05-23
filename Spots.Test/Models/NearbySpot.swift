//
//  NearbySpot.swift
//  Spots.Test
//
//  Data model for nearby spots from Google Places Nearby Search API
//

import Foundation
import CoreLocation

struct NearbySpot: Identifiable, Equatable {
    let placeId: String
    let name: String
    let address: String
    /// administrative_area_level_1 ("Île-de-France"). Misnamed historical
    /// field, retained for region grouping. Prefer `displayCity` on the
    /// downstream `Spot` for any user-visible label.
    let city: String?
    /// Google Places `locality` ("Paris"). Authoritative for city display.
    let locality: String?
    let country: String?
    let category: String
    let rating: Double?
    var photoReference: String?
    var photoUrl: String?
    let latitude: Double
    let longitude: Double

    // Distance is computed based on user location
    var distanceMeters: Double?

    /// Explicit init. All new optional fields default to nil so older call
    /// sites that pre-date `country` and `locality` keep compiling.
    init(
        placeId: String,
        name: String,
        address: String,
        city: String? = nil,
        locality: String? = nil,
        country: String? = nil,
        category: String,
        rating: Double? = nil,
        photoReference: String? = nil,
        photoUrl: String? = nil,
        latitude: Double,
        longitude: Double,
        distanceMeters: Double? = nil
    ) {
        self.placeId = placeId
        self.name = name
        self.address = address
        self.city = city
        self.locality = locality
        self.country = country
        self.category = category
        self.rating = rating
        self.photoReference = photoReference
        self.photoUrl = photoUrl
        self.latitude = latitude
        self.longitude = longitude
        self.distanceMeters = distanceMeters
    }

    var id: String { placeId }
    
    /// Formatted distance string (e.g., "0.1 mi" or "250 ft")
    var formattedDistance: String {
        guard let meters = distanceMeters else { return "" }
        return DistanceCalculator.formattedDistance(meters)
    }
    
    /// True when this row has every field the new feed hero card needs.
    /// Used by `PlacesAPIService.fetchPlaceDetails` to decide whether the
    /// cached row is good enough or whether to round-trip to Google.
    var hasFullEnrichmentFields: Bool {
        let hasPhoto = (photoUrl?.isEmpty == false) || (photoReference?.isEmpty == false)
        let hasCity = (city?.isEmpty == false)
        let hasCountry = (country?.isEmpty == false)
        let hasRating = (rating != nil)
        return hasPhoto && hasCity && hasCountry && hasRating
    }

    /// Returns the best available photo URL (prefers Supabase cached URL),
    /// downscaled to the variant whose `maxWidthPx` is closest to `maxWidth`.
    /// Returns nil if only Google API is available (requires custom loader with headers).
    ///
    /// Pair with `photoFallbackURL()` when used in `CachedAsyncImage` so the
    /// view transparently falls back to the canonical full-size object for
    /// cold spots whose variants haven't been generated yet.
    func photoURL(maxWidth: Int = 400) -> URL? {
        guard let photoUrl = photoUrl, !photoUrl.isEmpty else {
            // Return nil for Google API — we'll use GooglePlacesImageView instead
            // (Google Places API requires headers, not query params)
            return nil
        }
        let variant = NearbySpot.variant(forMaxWidth: maxWidth)
        let derived = ImageStorageService.deriveVariantURLString(baseURL: photoUrl, variant: variant)
        return URL(string: derived)
    }

    /// Canonical full-size URL — used as the `fallbackURL:` on `CachedAsyncImage`
    /// so a missing variant doesn't render as a broken image.
    func photoFallbackURL() -> URL? {
        guard let photoUrl = photoUrl, !photoUrl.isEmpty else { return nil }
        return URL(string: photoUrl)
    }

    /// Picks the smallest variant that's at least `maxWidth` pixels wide.
    /// Anything > 400 stays at `.full` (1200px); ≤ 96 collapses to `.avatar`.
    private static func variant(forMaxWidth maxWidth: Int) -> ImageVariant {
        if maxWidth <= ImageVariant.avatar.maxWidthPx { return .avatar }
        if maxWidth <= ImageVariant.thumb.maxWidthPx  { return .thumb }
        return .full
    }
    
    /// Returns photo reference for use with GooglePlacesImageView
    func photoReferenceForGoogleAPI() -> String? {
        guard let photoReference = photoReference, !photoReference.isEmpty else {
            return nil
        }
        return photoReference
    }
    
    /// CLLocation for distance calculations
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
    
    /// Updates distance based on user location
    func withDistance(from userLocation: CLLocation) -> NearbySpot {
        var spot = self
        spot.distanceMeters = userLocation.distance(from: location)
        return spot
    }
    
    /// Converts to a `Spot`, mapping the user-friendly category back into a
    /// best-effort `types` array so downstream UI that keys off `Spot.types`
    /// still works. Used by feed enrichment to merge live Google Places data
    /// into the cached `spots` row.
    func toSpot() -> Spot {
        Spot(
            placeId: placeId,
            name: name,
            address: address,
            city: city,
            locality: locality,
            country: country,
            latitude: latitude,
            longitude: longitude,
            types: category.isEmpty ? nil : [category.lowercased().replacingOccurrences(of: " ", with: "_")],
            photoUrl: photoUrl,
            photoReference: photoReference,
            rating: rating
        )
    }

    /// Converts to PlaceAutocompleteResult for use with ListPickerView.
    /// Passes `category` through as a single-element `types` array so the
    /// save sheet's subtitle (`ListPickerView.placeSubtitle`) can render
    /// "City • Category" for spots tapped from Explore — same trick used in
    /// `toSpot()` above. Without this, Explore-tapped spots showed city only.
    func toPlaceAutocompleteResult() -> PlaceAutocompleteResult {
        PlaceAutocompleteResult(
            placeId: placeId,
            name: name,
            address: address,
            city: city,
            locality: locality,
            types: category.isEmpty ? nil : [category.lowercased().replacingOccurrences(of: " ", with: "_")],
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            photoUrl: photoUrl,
            photoReference: photoReference
        )
    }
    
    // MARK: - Category Mapping
    
    /// Maps Google Places types array to a user-friendly category string
    static func mapCategory(from types: [String]) -> String {
        // Priority order for category display
        if types.contains("restaurant") { return "Restaurant" }
        if types.contains("cafe") { return "Cafe" }
        if types.contains("bar") { return "Bar" }
        if types.contains("bakery") { return "Bakery" }
        if types.contains("food") { return "Food" }
        if types.contains("coffee_shop") || types.contains("coffee") { return "Coffee" }
        if types.contains("store") || types.contains("shopping_mall") { return "Store" }
        if types.contains("museum") { return "Museum" }
        if types.contains("park") { return "Park" }
        if types.contains("gym") || types.contains("fitness_center") { return "Gym" }
        if types.contains("spa") || types.contains("beauty_salon") { return "Spa" }
        if types.contains("hotel") || types.contains("lodging") { return "Hotel" }
        if types.contains("tourist_attraction") { return "Attraction" }
        return "Point of Interest"
    }
}

// MARK: - Google Places Nearby Search Response Models

struct NearbySearchResponse: Codable {
    let places: [NearbyPlaceResult]?
    let nextPageToken: String?
    
    enum CodingKeys: String, CodingKey {
        case places
        case nextPageToken
    }
}

struct NearbyPlaceResult: Codable {
    let id: String
    let displayName: DisplayName?
    let formattedAddress: String?
    let shortFormattedAddress: String?
    let location: PlaceLocation?
    let types: [String]?
    let rating: Double?
    let photos: [PlacePhoto]?
    let addressComponents: [AddressComponent]?
    
    struct DisplayName: Codable {
        let text: String
        let languageCode: String?
    }
    
    struct PlaceLocation: Codable {
        let latitude: Double
        let longitude: Double
    }
    
    struct PlacePhoto: Codable {
        let name: String
        let widthPx: Int?
        let heightPx: Int?
        let authorAttributions: [AuthorAttribution]?
        
        struct AuthorAttribution: Codable {
            let displayName: String?
            let uri: String?
            let photoUri: String?
        }
    }
    
    struct AddressComponent: Codable {
        let types: [String]?  // Make optional
        let longText: String?
        let shortText: String?
    }
    
    /// Converts API response to NearbySpot model
    func toNearbySpot() -> NearbySpot? {
        guard let location = location else { return nil }
        
        let name = displayName?.text ?? "Unknown"
        
        // Build street address from components (street_number + route)
        let address: String = {
            guard let components = addressComponents else {
                // Fallback to short formatted address
                return shortFormattedAddress ?? formattedAddress ?? ""
            }
            
            let streetNumber = components.first { $0.types?.contains("street_number") ?? false }?.longText
            let route = components.first { $0.types?.contains("route") ?? false }?.longText
            
            if let number = streetNumber, let street = route {
                return "\(number) \(street)"
            } else if let street = route {
                return street
            } else {
                // Fallback if components don't have street info
                return shortFormattedAddress ?? formattedAddress ?? ""
            }
        }()
        
        let category = NearbySpot.mapCategory(from: types ?? [])

        // The historical `city` field stores administrative_area_level_1
        // (state/region) and is retained for region grouping (Travel Map,
        // profile region rows) and as a back-compat fallback. The new
        // `locality` field is the true city ("Paris", "Tokyo") and is what
        // user-visible labels should prefer via `Spot.displayCity`.
        let city = NearbyPlaceResult.normalize(addressComponents?
            .first { $0.types?.contains("administrative_area_level_1") ?? false }?
            .longText)

        let locality = NearbyPlaceResult.normalize(addressComponents?
            .first { $0.types?.contains("locality") ?? false }?
            .longText)

        // Country long name (e.g. "United States", "Japan") for the subtitle.
        let country = NearbyPlaceResult.normalize(addressComponents?
            .first { $0.types?.contains("country") ?? false }?
            .longText)

        // Extract photo reference from the first photo
        // The photo name format is: "places/{placeId}/photos/{photoReference}"
        // Store the full path for the new Places API, or just the photo ID for fallback
        let photoReference = photos?.first?.name // Store full path: "places/{placeId}/photos/{photoId}"

        #if DEBUG
        if photoReference == nil {
            print("⚠️ NearbySpot: No photos found for \(name) (placeId: \(id))")
        } else {
            print("✅ NearbySpot: Found photo for \(name): \(photoReference!)")
        }
        #endif

        return NearbySpot(
            placeId: id,
            name: name,
            address: address,
            city: city,
            locality: locality,
            country: country,
            category: category,
            rating: rating,
            photoReference: photoReference,
            photoUrl: nil, // Will be populated after upload to Supabase
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    /// Trim + treat empty/whitespace-only as nil. Google occasionally
    /// returns addressComponent `longText: ""` and the downstream
    /// `?? city` fallback in `Spot.displayCity` only triggers on nil,
    /// not empty string. Normalizing at the boundary keeps bad data
    /// out of the database.
    fileprivate static func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - Place Details Response (for single place lookup)

struct PlaceDetailsResponse: Codable {
    let id: String
    let displayName: DisplayName?
    let formattedAddress: String?
    let shortFormattedAddress: String?
    let location: PlaceLocation?
    let types: [String]?
    let rating: Double?
    let photos: [PlacePhoto]?
    let addressComponents: [AddressComponent]?

    struct DisplayName: Codable {
        let text: String
        let languageCode: String?
    }

    struct PlaceLocation: Codable {
        let latitude: Double
        let longitude: Double
    }

    struct PlacePhoto: Codable {
        let name: String
        let widthPx: Int?
        let heightPx: Int?
    }

    /// Mirrors the `addressComponents` shape on `PlaceResult`. Used to derive
    /// city + country from a single Place Details lookup so feed enrichment
    /// doesn't have to make a second call.
    struct AddressComponent: Codable {
        let types: [String]?
        let longText: String?
        let shortText: String?
    }

    /// Converts API response to NearbySpot model
    func toNearbySpot() -> NearbySpot? {
        guard let location = location else { return nil }

        let name = displayName?.text ?? "Unknown"
        let address = shortFormattedAddress ?? formattedAddress ?? ""
        let category = NearbySpot.mapCategory(from: types ?? [])
        let photoReference = photos?.first?.name

        // Mirrors PlaceResult.toNearbySpot. `city` stays as
        // administrative_area_level_1 for region grouping; `locality` is the
        // true city. See `Spot.displayCity` for the read-side rule.
        let city = PlaceDetailsResponse.normalize(addressComponents?
            .first { $0.types?.contains("administrative_area_level_1") ?? false }?
            .longText)
        let locality = PlaceDetailsResponse.normalize(addressComponents?
            .first { $0.types?.contains("locality") ?? false }?
            .longText)
        let country = PlaceDetailsResponse.normalize(addressComponents?
            .first { $0.types?.contains("country") ?? false }?
            .longText)

        return NearbySpot(
            placeId: id,
            name: name,
            address: address,
            city: city,
            locality: locality,
            country: country,
            category: category,
            rating: rating,
            photoReference: photoReference,
            photoUrl: nil,
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    /// Boundary normalizer: trim + empty→nil. See identical helper on
    /// `NearbyPlaceResult` for rationale.
    fileprivate static func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
