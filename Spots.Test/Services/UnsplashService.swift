//
//  UnsplashService.swift
//  Spots.Test
//
//  Fetches landscape city cover photos from the Unsplash API.
//  Results are cached in memory (SpotImageCache) keyed by city name
//  to avoid redundant network requests across profile opens.
//

import UIKit

// MARK: - Response Models

private struct UnsplashSearchResponse: Codable {
    let results: [UnsplashPhoto]
}

private struct UnsplashPhoto: Codable {
    let urls: UnsplashURLs
}

private struct UnsplashURLs: Codable {
    let regular: String
}

// MARK: - Service

final class UnsplashService {
    static let shared = UnsplashService()

    private init() {}

    // MARK: - Public API

    /// Fetches a cover image for the given city name.
    /// Returns a cached image immediately if available.
    /// Returns nil if the key is not configured or any network step fails.
    func fetchCoverImage(for city: String) async -> UIImage? {
        let cacheKey = "cover_\(city.lowercased())"

        // Return from cache if available
        if let cached = SpotImageCache.shared.image(for: cacheKey) {
            print("🖼️ UnsplashService: Serving cached cover for '\(city)'")
            return cached
        }

        guard !Config.unsplashAccessKey.isEmpty else {
            print("⚠️ UnsplashService: No access key configured — skipping cover fetch")
            return nil
        }

        // 1. Search for city photos
        guard let photoURL = await searchPhotoURL(for: city) else { return nil }

        // 2. Download the image data
        guard let image = await downloadImage(from: photoURL) else { return nil }

        // 3. Cache and return
        SpotImageCache.shared.store(image, for: cacheKey)
        print("✅ UnsplashService: Fetched and cached cover for '\(city)'")
        return image
    }

    // MARK: - Public API (multi-result / URL-based)

    /// Returns up to `count` Unsplash photo URLs for the given city without downloading images.
    /// Used by the cover photo picker so the user can preview and choose.
    func fetchCoverPhotoURLs(for city: String, count: Int = 3) async -> [String] {
        guard !Config.unsplashAccessKey.isEmpty else {
            print("⚠️ UnsplashService: No access key configured — skipping cover URL fetch")
            return []
        }
        guard var components = URLComponents(string: "https://api.unsplash.com/search/photos") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "query", value: city),
            URLQueryItem(name: "orientation", value: "landscape"),
            URLQueryItem(name: "per_page", value: "\(count)"),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Client-ID \(Config.unsplashAccessKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("⚠️ UnsplashService: Non-200 response fetching URLs for '\(city)'")
                return []
            }
            let decoded = try JSONDecoder().decode(UnsplashSearchResponse.self, from: data)
            return decoded.results.map { $0.urls.regular }
        } catch {
            print("❌ UnsplashService: URL fetch error for '\(city)': \(error.localizedDescription)")
            return []
        }
    }

    /// Downloads an image from an arbitrary Unsplash URL.
    /// Result is cached in SpotImageCache keyed by the URL string.
    func fetchCoverImageFromURL(_ urlString: String) async -> UIImage? {
        if let cached = SpotImageCache.shared.image(for: urlString) {
            return cached
        }
        guard let image = await downloadImage(from: urlString) else { return nil }
        SpotImageCache.shared.store(image, for: urlString)
        return image
    }

    // MARK: - Private Helpers

    private func searchPhotoURL(for city: String) async -> String? {
        guard var components = URLComponents(string: "https://api.unsplash.com/search/photos") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "query", value: city),
            URLQueryItem(name: "orientation", value: "landscape"),
            URLQueryItem(name: "per_page", value: "3"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Client-ID \(Config.unsplashAccessKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("⚠️ UnsplashService: Non-200 search response for '\(city)'")
                return nil
            }
            let decoded = try JSONDecoder().decode(UnsplashSearchResponse.self, from: data)
            guard !decoded.results.isEmpty else {
                print("⚠️ UnsplashService: No results for '\(city)'")
                return nil
            }
            // Pick a random result from the top 3 for variety
            let pick = decoded.results[Int.random(in: 0..<decoded.results.count)]
            return pick.urls.regular
        } catch {
            print("❌ UnsplashService: Search error for '\(city)': \(error.localizedDescription)")
            return nil
        }
    }

    private func downloadImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            print("❌ UnsplashService: Download error: \(error.localizedDescription)")
            return nil
        }
    }
}
