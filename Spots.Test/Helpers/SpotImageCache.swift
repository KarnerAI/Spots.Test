//
//  SpotImageCache.swift
//  Spots.Test
//
//  Two-tier image cache (memory + disk) for Google Places Photo bytes.
//  Keyed by (photoReference, maxWidth) so a 280px thumbnail entry never
//  cross-pollutes the 1200px save path or vice versa. Stores raw Data — the
//  bytes Google returned to us — so callers that need to upload back to
//  Supabase don't pay a UIImage→JPEG lossy round-trip. Callers that need to
//  paint pixels decode UIImage from Data on demand.
//
//  Disk filename: SHA256(photoReference)_{maxWidth}.jpg (first 16 bytes hex).
//  Old entries (pre-width-keyed cache) become misses naturally — no migration
//  needed; they age out via the LRU eviction.
//

import UIKit
import CryptoKit

final class SpotImageCache {
    static let shared = SpotImageCache()

    /// Cost-bounded memory cache of raw JPEG bytes wrapped in NSData (so NSCache
    /// can evict by byte count). 50 MB cap.
    private let memoryCache = NSCache<NSString, NSData>()
    private let diskCacheURL: URL
    private let diskQueue = DispatchQueue(label: "com.spots.imageDiskCache", qos: .utility)
    private let maxDiskItems = 200

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = caches.appendingPathComponent("SpotImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    // MARK: - Metrics
    private(set) var memoryHits = 0
    private(set) var diskHits = 0
    private(set) var misses = 0

    // MARK: - Public API (Data)

    /// Returns the raw JPEG bytes for `(photoReference, maxWidth)` if present
    /// in memory or on disk, nil otherwise. Width is part of the key — fetching
    /// 280px does NOT serve a previously cached 1200px entry, and vice versa.
    func data(for photoReference: String, maxWidth: Int) -> Data? {
        let key = cacheKey(photoReference: photoReference, maxWidth: maxWidth)

        if let memHit = memoryCache.object(forKey: key as NSString) {
            memoryHits += 1
            return memHit as Data
        }

        let fileURL = diskFileURL(photoReference: photoReference, maxWidth: maxWidth)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            misses += 1
            return nil
        }

        diskHits += 1
        memoryCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        return data
    }

    /// Stores raw JPEG bytes (typically the unchanged response from Google's
    /// Places Photo endpoint). Persists to disk async; memory cache is sync.
    func store(_ data: Data, for photoReference: String, maxWidth: Int) {
        let key = cacheKey(photoReference: photoReference, maxWidth: maxWidth)
        memoryCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)

        let fileURL = diskFileURL(photoReference: photoReference, maxWidth: maxWidth)
        diskQueue.async { [weak self] in
            try? data.write(to: fileURL, options: .atomic)
            self?.evictOldDiskEntriesIfNeeded()
        }
    }

    // MARK: - Public API (UIImage convenience)

    /// Returns a decoded UIImage for `(photoReference, maxWidth)` if cached.
    /// Decodes from cached Data on demand; does not re-cache the decoded
    /// image, since callers may want different decoded variants.
    func image(for photoReference: String, maxWidth: Int) -> UIImage? {
        guard let data = data(for: photoReference, maxWidth: maxWidth) else {
            return nil
        }
        return UIImage(data: data)
    }

    // MARK: - Legacy API (no width — used by UnsplashService for URL-keyed cache)

    /// Legacy single-key UIImage API. Used by callers that don't have a
    /// "width" concept (e.g. `UnsplashService` caches by URL string). These
    /// entries live in their own namespace (width = 0) and never collide with
    /// width-keyed Google Places entries. Persists via UIImage→JPEG at
    /// `PhotoQuality.jpegQuality` since no upstream JPEG bytes are available.
    func image(for key: String) -> UIImage? {
        return image(for: key, maxWidth: 0)
    }

    /// Legacy store-by-UIImage API for UnsplashService. Encodes to JPEG so it
    /// fits the `Data`-based memory/disk cache.
    func store(_ image: UIImage, for key: String) {
        guard let data = image.jpegData(compressionQuality: PhotoQuality.jpegQuality) else { return }
        store(data, for: key, maxWidth: 0)
    }

    func logCacheStats() {
        let total = memoryHits + diskHits + misses
        guard total > 0 else { return }
        print("📊 SpotImageCache: memory=\(memoryHits) disk=\(diskHits) miss=\(misses) hitRate=\(String(format: "%.0f", Double(memoryHits + diskHits) / Double(total) * 100))%")
    }

    // MARK: - Disk Helpers

    private func cacheKey(photoReference: String, maxWidth: Int) -> String {
        // Plain string key for NSCache. Disk uses a separate hashed filename.
        return "\(photoReference)#\(maxWidth)"
    }

    private func diskFileURL(photoReference: String, maxWidth: Int) -> URL {
        // Hash the photoReference (it can contain slashes), suffix with width
        // so cache entries at different widths get distinct files.
        let hash = SHA256.hash(data: Data(photoReference.utf8))
        let hex = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
        return diskCacheURL
            .appendingPathComponent("\(hex)_\(maxWidth)")
            .appendingPathExtension("jpg")
    }

    private func evictOldDiskEntriesIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: diskCacheURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        guard files.count > maxDiskItems else { return }

        let sorted = files.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d1 < d2
        }
        let toRemove = sorted.prefix(files.count - maxDiskItems)
        for url in toRemove {
            try? fm.removeItem(at: url)
        }
    }
}
