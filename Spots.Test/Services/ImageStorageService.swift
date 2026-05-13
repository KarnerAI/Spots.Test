//
//  ImageStorageService.swift
//  Spots.Test
//
//  Service for handling spot image uploads to Supabase Storage.
//
//  Save path:
//    1) Check SpotImageCache for raw JPEG bytes at PhotoQuality.maxWidthPx.
//       Width-keyed cache means we never inherit a low-res thumbnail from
//       another screen — only an entry already at save resolution counts as
//       a hit.
//    2) Otherwise, fetch from Google at PhotoQuality.maxWidthPx via the
//       shared GooglePlacesPhotoFetcher.
//    3) Upload Google's bytes to Supabase Storage VERBATIM (no UIImage round
//       trip, no re-encode). Google already serves JPEG; re-encoding adds
//       lossy compression for no benefit.
//

import Foundation
import UIKit
import Supabase

class ImageStorageService {
    static let shared = ImageStorageService()

    private let bucketName = "spot-images"
    private let supabaseClient = SupabaseManager.shared.client
    /// Base URL for the Supabase project. Used to build public Storage URLs.
    private var supabaseBaseURLString: String { Config.supabaseURL }

    /// Session-scoped cache of placeId → uploaded public URL. Avoids
    /// re-downloading from Google + re-uploading to Storage when the same
    /// place is hit multiple times (map pan, feed hydration, list re-open).
    /// Cleared automatically on app restart, where Storage is the source of truth.
    private let uploadedURLCache = NSCache<NSString, NSString>()

    private init() {}

    // MARK: - Public Methods

    /// Downloads image from Google Places Photo API (or reads from cache) and
    /// uploads to Supabase Storage. Always uses `PhotoQuality.maxWidthPx` so
    /// the saved image is sized for full-bleed feed cards regardless of what
    /// resolution any preview view happened to fetch first.
    /// - Parameters:
    ///   - photoReference: The Google Places photo reference (from photos[].name)
    ///   - placeId: The Google Place ID (used as filename)
    /// - Returns: The public URL of the uploaded image in Supabase Storage, or nil if failed
    func uploadSpotImage(photoReference: String, placeId: String) async -> String? {
        // Skip the entire pipeline if we already uploaded this place this session.
        if let cachedURL = uploadedURLCache.object(forKey: placeId as NSString) {
            return cachedURL as String
        }

        let imageData: Data
        if let cachedBytes = SpotImageCache.shared.data(
            for: photoReference,
            maxWidth: PhotoQuality.maxWidthPx
        ),
           // Defensive: validate the cached bytes still decode as a real image
           // before we upload them as `image/jpeg` to Supabase. Disk cache files
           // can be corrupted by partial writes (low-storage app kill, mid-write
           // crash) and we'd otherwise upload garbage that the feed renders as
           // a broken-image placeholder. Decode is ~few ms; cheap insurance.
           UIImage(data: cachedBytes) != nil {
            imageData = cachedBytes
            print("✅ ImageStorageService: Reusing cached \(PhotoQuality.maxWidthPx)px image for \(placeId) — skipped Google download")
        } else {
            // Cold path (also taken if the cached bytes failed validation above):
            // fetch fresh at save resolution, then warm the cache.
            do {
                imageData = try await GooglePlacesPhotoFetcher.fetch(
                    photoReference: photoReference,
                    maxWidth: PhotoQuality.maxWidthPx
                )
                SpotImageCache.shared.store(
                    imageData,
                    for: photoReference,
                    maxWidth: PhotoQuality.maxWidthPx
                )
            } catch {
                print("❌ ImageStorageService: Failed to download image from Google: \(error)")
                return nil
            }
        }

        let url = await uploadToSupabase(imageData: imageData, fileName: storageFileName(for: placeId))
        if let url {
            uploadedURLCache.setObject(url as NSString, forKey: placeId as NSString)
            // Fire-and-forget variant uploads. Best-effort — a failure here is
            // a missed-egress-savings opportunity, not a broken spot. The card
            // view's fallback URL keeps rendering correctly either way.
            Task.detached { [imageData] in
                await ImageStorageService.shared.uploadVariants(
                    fullImageData: imageData,
                    canonicalFileName: ImageStorageService.shared.storageFileName(for: placeId)
                )
            }
        }
        return url
    }

    /// Best-effort uploads of every sized variant (thumb, avatar) alongside
    /// the canonical full-size object. Called by both the live save path
    /// (`uploadSpotImage`) and the backfill pipeline.
    ///
    /// `canonicalFileName` is the FULL-variant filename (e.g. `foo.jpg` or
    /// `foo_v2.jpg`). Variant filenames are derived by `variantFileName(...)`.
    @discardableResult
    func uploadVariants(fullImageData: Data, canonicalFileName: String) async -> Int {
        guard let fullImage = UIImage(data: fullImageData) else {
            print("⚠️  ImageStorageService: variant upload skipped — full image failed to decode")
            return 0
        }
        var uploaded = 0
        for variant in ImageVariant.sized {
            guard let resized = Self.resizedJPEGData(
                from: fullImage,
                maxWidthPx: variant.maxWidthPx,
                quality: PhotoQuality.jpegQuality
            ) else {
                print("⚠️  ImageStorageService: failed to resize \(canonicalFileName) for \(variant.rawValue)")
                continue
            }
            let fileName = Self.variantFileName(canonical: canonicalFileName, variant: variant)
            if await uploadToSupabase(imageData: resized, fileName: fileName) != nil {
                uploaded += 1
            }
        }
        return uploaded
    }

    /// Returns the public URL for the cover image of a place if it has been
    /// uploaded under the canonical (un-versioned) filename. Used by the save
    /// path. Backfilled spots use versioned filenames and store the full URL
    /// in `spots.photo_url` directly — see `PhotoBackfillService`.
    func getExistingImageUrl(placeId: String) -> String? {
        let fileName = storageFileName(for: placeId)
        return publicURL(forFileName: fileName)
    }

    // MARK: - Storage helpers (also used by PhotoBackfillService)

    /// Canonical filename for a fresh upload (no version suffix).
    func storageFileName(for placeId: String) -> String {
        return "\(sanitize(placeId)).jpg"
    }

    /// Versioned filename used by backfill so changing image bytes also
    /// changes the public URL — forces clients and CDN caches to refetch.
    func versionedStorageFileName(for placeId: String, version: Int) -> String {
        return "\(sanitize(placeId))_v\(version).jpg"
    }

    /// Builds the Supabase Storage public URL for a given filename in the
    /// spot-images bucket. Pure string assembly — no network call.
    func publicURL(forFileName fileName: String) -> String {
        return "\(supabaseBaseURLString)/storage/v1/object/public/\(bucketName)/\(fileName)"
    }

    /// Returns the public URL of the given variant for a spot whose canonical
    /// `photo_url` is `baseURL`. Pure string manipulation — no network call.
    ///
    /// `.full` (or a malformed URL) returns the input unchanged, so callers
    /// can pass the result through unconditionally. If the derived variant
    /// object doesn't exist yet (cold spot, not backfilled), the caller's
    /// `CachedAsyncImage` falls back to `baseURL` and renders the canonical
    /// full-size image — no broken image, just a missed-egress-savings.
    func variantURL(fromBaseURL baseURL: String, variant: ImageVariant) -> String {
        guard variant != .full else { return baseURL }
        return Self.deriveVariantURLString(baseURL: baseURL, variant: variant)
    }

    /// Pure-logic variant of `variantURL(fromBaseURL:variant:)` — exposed at
    /// type level so it can be unit-tested without instantiating the service.
    static func deriveVariantURLString(baseURL: String, variant: ImageVariant) -> String {
        guard variant != .full,
              let lastSlash = baseURL.lastIndex(of: "/") else {
            return baseURL
        }
        let prefix = baseURL[..<baseURL.index(after: lastSlash)]
        let fileName = String(baseURL[baseURL.index(after: lastSlash)...])
        let variantFile = variantFileName(canonical: fileName, variant: variant)
        return String(prefix) + variantFile
    }

    /// Inserts a variant's `_w{N}` suffix between the filename stem and `.jpg`.
    /// `foo.jpg`        → `foo_w400.jpg`
    /// `foo_v2.jpg`     → `foo_v2_w400.jpg`
    /// Returns the input unchanged for `.full` or unrecognized extensions.
    static func variantFileName(canonical: String, variant: ImageVariant) -> String {
        guard variant != .full else { return canonical }
        let lower = canonical.lowercased()
        // Match `.jpg` or `.jpeg` (case-insensitive) at the very end.
        for ext in [".jpeg", ".jpg"] {
            if lower.hasSuffix(ext) {
                let stem = canonical.dropLast(ext.count)
                return "\(stem)\(variant.filenameSuffix)\(ext)"
            }
        }
        return canonical
    }

    /// Re-encodes `image` at most `maxWidthPx` wide as a JPEG. Preserves
    /// aspect ratio. Returns nil if image draws fail (extremely rare —
    /// invalid CGContext setup).
    static func resizedJPEGData(from image: UIImage, maxWidthPx: Int, quality: CGFloat) -> Data? {
        let widthPx = image.size.width * image.scale
        let heightPx = image.size.height * image.scale
        guard widthPx > 0, heightPx > 0 else { return nil }

        // Don't upscale: if already smaller, just re-encode at `quality` to
        // get JPEG bytes (a thumbnail at thumb quality is still ~30% smaller
        // than the full-size JPEG due to quality 0.9 + smaller decode tree).
        let scale = min(1.0, CGFloat(maxWidthPx) / widthPx)
        let targetSize = CGSize(width: floor(widthPx * scale), height: floor(heightPx * scale))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // we already converted to pixel dimensions
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Uploads raw image bytes to Supabase Storage at `fileName`. Sends the
    /// session JWT so RLS allows authenticated uploads. Idempotent via upsert.
    /// Used by both the live save path and the backfill service.
    func uploadToSupabase(imageData: Data, fileName: String) async -> String? {
        do {
            _ = try await supabaseClient.storage
                .from(bucketName)
                .upload(
                    fileName,
                    data: imageData,
                    options: FileOptions(
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )
            print("✅ ImageStorageService: Uploaded \(fileName) (\(imageData.count) bytes)")
            return publicURL(forFileName: fileName)
        } catch {
            print("❌ ImageStorageService: Error uploading \(fileName): \(error.localizedDescription)")
            if let storageError = error as? StorageError {
                print("❌ ImageStorageService: Storage error details: \(storageError)")
            }
            return nil
        }
    }

    /// Deletes a single object from the bucket. Used by `PhotoBackfillService.sweepOrphans()`.
    /// Returns true on success. **Destructive** — callers must use a dry-run
    /// flag for the first prod sweep.
    func deleteObject(fileName: String) async -> Bool {
        do {
            _ = try await supabaseClient.storage
                .from(bucketName)
                .remove(paths: [fileName])
            return true
        } catch {
            print("❌ ImageStorageService: deleteObject(\(fileName)) failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Lists all object names in the bucket. Used by `PhotoBackfillService.sweepOrphans()`.
    func listAllObjects() async -> [String] {
        do {
            let objects = try await supabaseClient.storage
                .from(bucketName)
                .list()
            return objects.map { $0.name }
        } catch {
            print("❌ ImageStorageService: listAllObjects failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Private Methods

    /// Sanitizes place ID to create a valid filename. Google Place IDs can
    /// contain characters that need to be URL-safe.
    private func sanitize(_ placeId: String) -> String {
        return placeId.replacingOccurrences(
            of: "[^a-zA-Z0-9]",
            with: "_",
            options: .regularExpression
        )
    }
}

// MARK: - Error Handling

enum ImageStorageError: LocalizedError {
    case downloadFailed
    case uploadFailed
    case invalidPlaceId

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "Failed to download image from Google Places"
        case .uploadFailed:
            return "Failed to upload image to Supabase Storage"
        case .invalidPlaceId:
            return "Invalid place ID provided"
        }
    }
}
