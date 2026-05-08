//
//  PhotoBackfillServiceTests.swift
//  Spots.TestTests
//
//  Pure-logic tests for the filename versioning + URL parsing rules used by
//  PhotoBackfillService. The actor's network paths (Google fetch, Supabase
//  upload, Supabase query, sweep deletion) are integration concerns and are
//  not exercised here — they require mocked clients and real fixtures.
//
//  Why this test file exists per the eng review's regression rule: the orphan
//  sweep is destructive (deletes Supabase Storage objects). Anything that
//  decides which keys are "orphaned" must have unit-level coverage so the
//  first prod sweep can't accidentally delete a referenced object.
//

import Testing
import Foundation
@testable import Spots_Test

struct PhotoBackfillVersioningLogicTests {

    typealias VL = PhotoBackfillService.VersioningLogic

    // MARK: - extractFileName

    @Test func extractFileNameFromSupabaseURL() {
        let url = "https://example.supabase.co/storage/v1/object/public/spot-images/abc123.jpg"
        #expect(VL.extractFileName(from: url) == "abc123.jpg")
    }

    @Test func extractFileNameVersionedURL() {
        let url = "https://example.supabase.co/storage/v1/object/public/spot-images/abc123_v2.jpg"
        #expect(VL.extractFileName(from: url) == "abc123_v2.jpg")
    }

    @Test func extractFileNameFromMalformedURL() {
        #expect(VL.extractFileName(from: "not a url") == "not a url")
        #expect(VL.extractFileName(from: "") == nil)
    }

    // MARK: - parseVersionSuffix

    @Test func parseVersionSuffixUnversioned() {
        #expect(VL.parseVersionSuffix(fileName: "ChIJabc.jpg") == nil)
        #expect(VL.parseVersionSuffix(fileName: "place_id_with_underscores.jpg") == nil)
    }

    @Test func parseVersionSuffixV2() {
        #expect(VL.parseVersionSuffix(fileName: "ChIJabc_v2.jpg") == 2)
    }

    @Test func parseVersionSuffixV10() {
        #expect(VL.parseVersionSuffix(fileName: "ChIJabc_v10.jpg") == 10)
    }

    @Test func parseVersionSuffixHandlesPlaceIdWithEmbeddedV() {
        // place IDs can have arbitrary characters (already sanitized to a-z0-9_)
        // so a name like "v8_place_v3.jpg" should parse the TRAILING version.
        #expect(VL.parseVersionSuffix(fileName: "v8_place_v3.jpg") == 3)
    }

    @Test func parseVersionSuffixIgnoresJpegCase() {
        #expect(VL.parseVersionSuffix(fileName: "ChIJabc_v2.JPG") == 2)
    }

    @Test func parseVersionSuffixRejectsNonNumericTail() {
        // "_vfoo.jpg" must not match — only digits qualify.
        #expect(VL.parseVersionSuffix(fileName: "ChIJabc_vfoo.jpg") == nil)
    }

    // MARK: - isVersionedFilename — protects the sweep from deleting fresh saves

    @Test func freshSaveIsNotVersioned() {
        // Critical: the sweep MUST never delete unversioned filenames written
        // by the live save path. They are out of its scope.
        #expect(VL.isVersionedFilename("ChIJabc.jpg") == false)
        #expect(VL.isVersionedFilename("placeWithoutVersion.jpg") == false)
    }

    @Test func versionedSaveIsVersioned() {
        #expect(VL.isVersionedFilename("ChIJabc_v2.jpg") == true)
        #expect(VL.isVersionedFilename("ChIJabc_v17.jpg") == true)
    }

    // MARK: - nextVersion

    @Test func nextVersionFromUnversionedURLIsTwo() {
        let url = "https://example.supabase.co/storage/v1/object/public/spot-images/place.jpg"
        #expect(VL.nextVersion(currentURL: url) == 2)
    }

    @Test func nextVersionFromV2IsThree() {
        let url = "https://example.supabase.co/storage/v1/object/public/spot-images/place_v2.jpg"
        #expect(VL.nextVersion(currentURL: url) == 3)
    }

    @Test func nextVersionFromV9IsTen() {
        let url = "https://example.supabase.co/storage/v1/object/public/spot-images/place_v9.jpg"
        #expect(VL.nextVersion(currentURL: url) == 10)
    }

    @Test func nextVersionFromNilIsTwo() {
        // Spots saved before this PR may have a null photo_url if the upload
        // failed. Treat them as needing a fresh v2 just like an unversioned URL.
        #expect(VL.nextVersion(currentURL: nil) == 2)
    }
}

// MARK: - PhotoQuality pin

struct PhotoQualityConstantsTests {
    @Test func maxWidthIsTwelveHundred() {
        // Pin so any future tweak forces an explicit decision (and a test edit).
        #expect(PhotoQuality.maxWidthPx == 1200)
    }

    @Test func jpegQualityIsNinetyPercent() {
        #expect(PhotoQuality.jpegQuality == 0.9)
    }
}
