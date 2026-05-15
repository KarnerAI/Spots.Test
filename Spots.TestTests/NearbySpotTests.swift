//
//  NearbySpotTests.swift
//  Spots.TestTests
//
//  Issue 6 (6A) — covers NearbySpot.photoURL(maxWidth:)'s variant selection.
//  Bugs here would silently serve the wrong-sized image (or fall back to the
//  full 1200px JPEG everywhere), undoing the egress savings without any
//  observable error.
//

import Testing
import Foundation
@testable import Spots_Test

struct NearbySpotPhotoURLTests {

    private func makeSpot(photoUrl: String?) -> NearbySpot {
        NearbySpot(
            placeId: "ChIJabc",
            name: "Test Spot",
            address: "123 Test St",
            category: "restaurant",
            photoUrl: photoUrl,
            latitude: 0,
            longitude: 0
        )
    }

    @Test func avatarWidthMapsToAvatarVariant() {
        let spot = makeSpot(photoUrl: "https://example.supabase.co/storage/v1/object/public/spot-images/abc.jpg")
        let url = spot.photoURL(maxWidth: 96)
        #expect(url?.absoluteString == "https://example.supabase.co/storage/v1/object/public/spot-images/abc_w96.jpg")
    }

    @Test func thumbWidthMapsToThumbVariant() {
        let spot = makeSpot(photoUrl: "https://example.supabase.co/storage/v1/object/public/spot-images/abc.jpg")
        let url = spot.photoURL(maxWidth: 400)
        #expect(url?.absoluteString == "https://example.supabase.co/storage/v1/object/public/spot-images/abc_w400.jpg")
    }

    @Test func widthAt100PicksThumb() {
        // Anything >96 but ≤400 should pick .thumb, not .avatar — the
        // boundary matters because a 100pt avatar slot would otherwise
        // jump to a 400px image (5× the bytes).
        let spot = makeSpot(photoUrl: "https://example.supabase.co/storage/v1/object/public/spot-images/abc.jpg")
        let url = spot.photoURL(maxWidth: 100)
        #expect(url?.absoluteString.contains("_w400.jpg") == true)
    }

    @Test func widthOver400FallsToFull() {
        // Full-bleed feed cards request 1200; should NOT get a variant suffix.
        let spot = makeSpot(photoUrl: "https://example.supabase.co/storage/v1/object/public/spot-images/abc.jpg")
        let url = spot.photoURL(maxWidth: 1200)
        #expect(url?.absoluteString.contains("_w") == false)
        #expect(url?.absoluteString == "https://example.supabase.co/storage/v1/object/public/spot-images/abc.jpg")
    }

    @Test func nilPhotoUrlReturnsNil() {
        let spot = makeSpot(photoUrl: nil)
        #expect(spot.photoURL(maxWidth: 400) == nil)
    }

    @Test func emptyPhotoUrlReturnsNil() {
        let spot = makeSpot(photoUrl: "")
        #expect(spot.photoURL(maxWidth: 400) == nil)
    }

    @Test func photoFallbackURLAlwaysReturnsCanonical() {
        let spot = makeSpot(photoUrl: "https://example.supabase.co/storage/v1/object/public/spot-images/abc.jpg")
        #expect(spot.photoFallbackURL()?.absoluteString == "https://example.supabase.co/storage/v1/object/public/spot-images/abc.jpg")
    }
}
