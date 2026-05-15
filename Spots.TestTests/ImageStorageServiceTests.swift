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

/// Issue 6 (6A) — covers the pure variant-derivation helpers. Bugs here would
/// cause every variant URL to silently fall back to the canonical full-size
/// URL, undoing this PR's egress savings without any observable error.
struct ImageStorageServiceVariantTests {

    // MARK: - variantFileName

    @Test func variantFileNameAppendsSuffixBeforeJpg() {
        #expect(ImageStorageService.variantFileName(canonical: "foo.jpg", variant: .thumb) == "foo_w400.jpg")
        #expect(ImageStorageService.variantFileName(canonical: "foo.jpg", variant: .avatar) == "foo_w96.jpg")
    }

    @Test func variantFileNameFullIsPassthrough() {
        #expect(ImageStorageService.variantFileName(canonical: "foo.jpg", variant: .full) == "foo.jpg")
    }

    @Test func variantFileNameHandlesUppercaseExtension() {
        #expect(ImageStorageService.variantFileName(canonical: "FOO.JPEG", variant: .thumb) == "FOO_w400.JPEG")
    }

    @Test func variantFileNameHandlesVersionedCanonical() {
        // The versioning path (`foo_v2.jpg`) must compose cleanly with the variant suffix.
        #expect(ImageStorageService.variantFileName(canonical: "foo_v2.jpg", variant: .thumb) == "foo_v2_w400.jpg")
    }

    @Test func variantFileNamePassthroughOnUnknownExtension() {
        // Unknown extensions are returned unchanged so we never produce a
        // garbage filename — caller will fail the variant upload upstream.
        #expect(ImageStorageService.variantFileName(canonical: "foo.png", variant: .thumb) == "foo.png")
        #expect(ImageStorageService.variantFileName(canonical: "noext", variant: .thumb) == "noext")
    }

    @Test func variantFileNameEmptyInput() {
        #expect(ImageStorageService.variantFileName(canonical: "", variant: .thumb) == "")
    }

    // MARK: - deriveVariantURLString

    @Test func deriveVariantURLPlainPublicURL() {
        let base = "https://example.supabase.co/storage/v1/object/public/spot-images/abc123.jpg"
        let derived = ImageStorageService.deriveVariantURLString(baseURL: base, variant: .thumb)
        #expect(derived == "https://example.supabase.co/storage/v1/object/public/spot-images/abc123_w400.jpg")
    }

    @Test func deriveVariantURLVersionedFilename() {
        let base = "https://example.supabase.co/storage/v1/object/public/spot-images/abc123_v2.jpg"
        let derived = ImageStorageService.deriveVariantURLString(baseURL: base, variant: .thumb)
        #expect(derived == "https://example.supabase.co/storage/v1/object/public/spot-images/abc123_v2_w400.jpg")
    }

    @Test func deriveVariantURLWithQueryString() {
        // Future signed URLs may carry tokens; the variant-suffix must apply
        // to the FILENAME, not the entire string.
        let base = "https://example.supabase.co/storage/v1/object/public/spot-images/abc.jpg?token=xyz"
        let derived = ImageStorageService.deriveVariantURLString(baseURL: base, variant: .thumb)
        #expect(derived == "https://example.supabase.co/storage/v1/object/public/spot-images/abc_w400.jpg?token=xyz")
    }

    @Test func deriveVariantURLWithFragment() {
        let base = "https://example.supabase.co/storage/v1/object/public/spot-images/abc.jpg#section"
        let derived = ImageStorageService.deriveVariantURLString(baseURL: base, variant: .avatar)
        #expect(derived == "https://example.supabase.co/storage/v1/object/public/spot-images/abc_w96.jpg#section")
    }

    @Test func deriveVariantURLFullIsPassthrough() {
        let base = "https://example.supabase.co/storage/v1/object/public/spot-images/abc.jpg"
        #expect(ImageStorageService.deriveVariantURLString(baseURL: base, variant: .full) == base)
    }

    @Test func deriveVariantURLMalformedReturnsInput() {
        // We never produce a "more broken" URL — if URLComponents can't parse,
        // hand the input back unchanged so callers see the same fallback behavior.
        let base = "not a url at all"
        #expect(ImageStorageService.deriveVariantURLString(baseURL: base, variant: .thumb) == base)
    }

    @Test func deriveVariantURLEmptyPath() {
        // Defensive: bare host with no path should not crash.
        let base = "https://example.supabase.co"
        #expect(ImageStorageService.deriveVariantURLString(baseURL: base, variant: .thumb) == base)
    }
}
