//
//  ImageStorageServiceTests.swift
//  Spots.TestTests
//
//  Pure helpers on `ImageStorageService` — filename sanitization, versioned
//  filename builder, public URL construction. The async upload/download paths
//  hit Supabase + Google and aren't exercised here.
//

import Testing
import Foundation
@testable import Spots_Test

struct ImageStorageServiceFileNameTests {

    @Test func storageFileNameForCleanPlaceId() {
        let svc = ImageStorageService.shared
        // Google Place IDs typically contain only alphanumerics and underscores,
        // but ChIJ... can contain hyphens and other URL-unsafe chars depending
        // on encoding. The sanitizer collapses anything non-alphanumeric to "_".
        #expect(svc.storageFileName(for: "ChIJabc123") == "ChIJabc123.jpg")
    }

    @Test func storageFileNameSanitizesUnsafeChars() {
        let svc = ImageStorageService.shared
        #expect(svc.storageFileName(for: "ChIJ-abc/123") == "ChIJ_abc_123.jpg")
    }

    @Test func versionedStorageFileNameV2() {
        let svc = ImageStorageService.shared
        #expect(svc.versionedStorageFileName(for: "ChIJabc", version: 2) == "ChIJabc_v2.jpg")
    }

    @Test func versionedStorageFileNameV17() {
        let svc = ImageStorageService.shared
        #expect(svc.versionedStorageFileName(for: "ChIJabc", version: 17) == "ChIJabc_v17.jpg")
    }

    @Test func publicURLContainsBucket() {
        let svc = ImageStorageService.shared
        let url = svc.publicURL(forFileName: "ChIJabc_v2.jpg")
        // Path shape, not exact host (Config.supabaseURL is environment-specific).
        #expect(url.contains("/storage/v1/object/public/spot-images/ChIJabc_v2.jpg"))
    }

    @Test func versionedFilenameRoundTripsThroughVersionParser() {
        // Whatever ImageStorageService writes, PhotoBackfillService.VersioningLogic
        // must parse back. This is the contract that makes idempotent re-runs work.
        let svc = ImageStorageService.shared
        let name = svc.versionedStorageFileName(for: "ChIJabc", version: 5)
        #expect(PhotoBackfillService.VersioningLogic.parseVersionSuffix(fileName: name) == 5)
        #expect(PhotoBackfillService.VersioningLogic.isVersionedFilename(name) == true)
    }

    @Test func freshSaveFilenameIsNotVersioned() {
        // Symmetric to the above: the un-versioned filename used by the live
        // save path must NOT match the version pattern, so the sweep skips it.
        let svc = ImageStorageService.shared
        let name = svc.storageFileName(for: "ChIJabc")
        #expect(PhotoBackfillService.VersioningLogic.isVersionedFilename(name) == false)
    }
}
