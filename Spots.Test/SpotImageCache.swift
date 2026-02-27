//
//  SpotImageCache.swift
//  Spots.Test
//
//  Two-tier image cache (memory + disk) to avoid redundant Google Places Photo API calls.
//  Keyed by photoReference (e.g. "places/{placeId}/photos/{photoId}").
//

import UIKit
import CryptoKit

final class SpotImageCache {
    static let shared = SpotImageCache()
    private let memoryCache = NSCache<NSString, UIImage>()
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
    
    func image(for photoReference: String) -> UIImage? {
        if let memHit = memoryCache.object(forKey: photoReference as NSString) {
            memoryHits += 1
            return memHit
        }
        
        let fileURL = diskFileURL(for: photoReference)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let diskImage = UIImage(data: data) else {
            misses += 1
            return nil
        }
        
        diskHits += 1
        let cost = data.count
        memoryCache.setObject(diskImage, forKey: photoReference as NSString, cost: cost)
        return diskImage
    }
    
    func logCacheStats() {
        let total = memoryHits + diskHits + misses
        guard total > 0 else { return }
        print("📊 SpotImageCache: memory=\(memoryHits) disk=\(diskHits) miss=\(misses) hitRate=\(String(format: "%.0f", Double(memoryHits + diskHits) / Double(total) * 100))%")
    }

    func store(_ image: UIImage, for photoReference: String) {
        let data = image.jpegData(compressionQuality: 0.85)
        let cost = data?.count ?? 0
        memoryCache.setObject(image, forKey: photoReference as NSString, cost: cost)
        
        guard let jpegData = data else { return }
        let fileURL = diskFileURL(for: photoReference)
        diskQueue.async { [weak self] in
            try? jpegData.write(to: fileURL, options: .atomic)
            self?.evictOldDiskEntriesIfNeeded()
        }
    }
    
    // MARK: - Disk Helpers

    private func diskFileURL(for photoReference: String) -> URL {
        let hash = SHA256.hash(data: Data(photoReference.utf8))
        let hex = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
        return diskCacheURL.appendingPathComponent(hex).appendingPathExtension("jpg")
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
