//
//  CachedAsyncImage.swift
//  Spots.Test
//
//  Drop-in replacement for SwiftUI's AsyncImage(url:) that:
//    1. Caches decoded UIImage objects in memory keyed by URL (50MB NSCache).
//    2. Goes through a process-wide URLSession backed by a 200MB on-disk
//       URLCache so cold app launches don't re-download images we already had.
//    3. Optionally falls back to a second URL on HTTP error or decode failure
//       — used so callers can request a small variant first
//       (`{placeId}_w400.jpg`) and transparently fall back to the canonical
//       full-size object when the variant hasn't been generated yet
//       (cold-spot, not yet backfilled).
//

import SwiftUI
import UIKit

/// Process-wide decoded-image cache. NSCache evicts under memory pressure
/// so we don't have to worry about unbounded growth.
final class AsyncImageCache {
    static let shared = AsyncImageCache()

    private let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        // ~50MB worth of decoded images. NSCache evicts as needed.
        c.totalCostLimit = 50 * 1024 * 1024
        return c
    }()

    private init() {}

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: UIImage, for url: URL) {
        // Approximate bytes: w * h * 4 (RGBA). Drives NSCache eviction order.
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

/// Process-wide URLSession with a generous on-disk URLCache. Configured once
/// at first use. Swapping in a configured session (instead of using
/// `URLSession.shared`) lets us guarantee the disk cache size — the system's
/// default `URLCache.shared` is small (~20MB) and per-object capped, so
/// 300KB JPEGs were being re-downloaded on every cold launch even though
/// they "should" have cached.
enum ImageHTTPSession {
    /// 50MB memory + 200MB disk. Disk capacity is the important number —
    /// it's what survives app suspension and reboot, and the bottleneck
    /// driving Supabase "Cached Egress" bills.
    static let shared: URLSession = {
        let memoryCapacity = 50 * 1024 * 1024
        let diskCapacity = 200 * 1024 * 1024
        let cache: URLCache
        if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let directory = cachesDir.appendingPathComponent("SpotsImageURLCache", isDirectory: true)
            cache = URLCache(
                memoryCapacity: memoryCapacity,
                diskCapacity: diskCapacity,
                directory: directory
            )
        } else {
            cache = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: nil)
        }
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        // Use the response's Cache-Control headers (Supabase Storage sends a
        // reasonable max-age). Avoid `.returnCacheDataElseLoad` because that
        // would serve stale bytes after a backfill rewrite under a new
        // versioned filename — versioning relies on revalidation working.
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()
}

/// Phase-API drop-in replacement for SwiftUI's AsyncImage. Same call shape:
///
///     CachedAsyncImage(url: someURL) { phase in
///         switch phase {
///         case .success(let img): img.resizable()...
///         case .empty:            placeholder
///         case .failure:          fallback
///         @unknown default:       fallback
///         }
///     }
///
/// Or with a fallback URL (e.g., request a small variant, fall back to full
/// size if the variant 404s):
///
///     CachedAsyncImage(url: variantURL, fallbackURL: fullURL) { phase in ... }
///
/// On a cache hit, `phase` is `.success` synchronously so there's no flash.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    let fallbackURL: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(
        url: URL?,
        fallbackURL: URL? = nil,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.content = content
        // Initialize phase synchronously from cache so first render shows the
        // image without an .empty flash when we already have it. Check the
        // primary URL first, then the fallback — either is acceptable.
        if let url, let cached = AsyncImageCache.shared.image(for: url) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
        } else if let fb = fallbackURL, let cached = AsyncImageCache.shared.image(for: fb) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
        }
    }

    var body: some View {
        content(phase)
            .task(id: taskID) { await load() }
    }

    /// Identity for `.task(id:)`. Includes both URLs so changing either one
    /// kicks off a fresh load.
    private var taskID: String {
        "\(url?.absoluteString ?? "_")|\(fallbackURL?.absoluteString ?? "_")"
    }

    private func load() async {
        // Try the primary URL; on HTTP failure or decode failure, try the
        // fallback. This is what makes "variant URL + canonical URL"
        // transparent for callers — we never show a broken image just
        // because a variant hasn't been backfilled yet.
        if let url, await tryLoad(url) {
            return
        }
        if let fb = fallbackURL, await tryLoad(fb) {
            return
        }
        // Both attempts failed (or primary URL was nil and there was no
        // fallback). Surface a generic failure to the caller.
        if url == nil && fallbackURL == nil {
            await MainActor.run { phase = .empty }
        } else {
            await MainActor.run { phase = .failure(URLError(.resourceUnavailable)) }
        }
    }

    /// Attempts to load and render `url`. Returns true on success. On any
    /// failure (network, non-2xx, decode), returns false so the caller can
    /// try the fallback URL.
    private func tryLoad(_ url: URL) async -> Bool {
        if let cached = AsyncImageCache.shared.image(for: url) {
            await MainActor.run { phase = .success(Image(uiImage: cached)) }
            return true
        }

        do {
            let (data, response) = try await ImageHTTPSession.shared.data(from: url)
            try Task.checkCancellation()
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return false
            }
            guard let ui = UIImage(data: data) else {
                return false
            }
            AsyncImageCache.shared.set(ui, for: url)
            await MainActor.run { phase = .success(Image(uiImage: ui)) }
            return true
        } catch is CancellationError {
            // View went away mid-load. Don't touch state.
            return true
        } catch {
            return false
        }
    }
}
