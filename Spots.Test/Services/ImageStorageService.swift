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
        ) {
            // Cache hit at save resolution: reuse Google's bytes verbatim.
            imageData = cachedBytes
            print("✅ ImageStorageService: Reusing cached \(PhotoQuality.maxWidthPx)px image for \(placeId) — skipped Google download")
        } else {
            // Cold path: fetch fresh at save resolution, then warm the cache.
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
        }
        return url
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
