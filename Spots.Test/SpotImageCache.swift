//
//  SpotImageCache.swift
//  Spots.Test
//
//  In-memory image cache to avoid redundant Google Places Photo API calls.
//  Keyed by photoReference (e.g. "places/{placeId}/photos/{photoId}").
//

import UIKit

final class SpotImageCache {
    static let shared = SpotImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100 // keep at most 100 images in memory
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB byte limit
    }

    func image(for photoReference: String) -> UIImage? {
        cache.object(forKey: photoReference as NSString)
    }

    func store(_ image: UIImage, for photoReference: String) {
        let cost = image.pngData()?.count ?? 0
        cache.setObject(image, forKey: photoReference as NSString, cost: cost)
    }
}
