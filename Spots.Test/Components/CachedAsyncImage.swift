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
        // Approximate in-memory pixel bytes: (w_pt * scale) * (h_pt * scale) * 4
        // (RGBA). UIImage.size is in POINTS, not pixels — a 400pt image on a
        // 3× Retina device occupies 9× the memory implied by size alone. Cost
        // is the signal NSCache uses to decide when to evict; under-counting
        // by 9× meant our 50MB budget was effectively ~5.5MB on Pro Max
        // devices. Issue 7 (7A): account for scale so eviction matches the
        // configured budget.
        let scaledWidth = image.size.width * image.scale
        let scaledHeight = image.size.height * image.scale
        let cost = Int(scaledWidth * scaledHeight * 4)
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
        if let url, await tryLoadAndApply(url) {
            return
        }
        if let fb = fallbackURL, await tryLoadAndApply(fb) {
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

    /// Loads `url` via `AsyncImageLoader.load` (the testable seam) and applies
    /// the result to `@State phase`. Returns true if loading succeeded.
    private func tryLoadAndApply(_ url: URL) async -> Bool {
        do {
            let result = try await AsyncImageLoader.load(url: url, session: ImageHTTPSession.shared)
            guard let ui = result else { return false }
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

/// Pure-async loader that fetches an image by URL through any URLSession,
/// returning the decoded UIImage or nil on any non-success outcome. Lifted
/// out of `CachedAsyncImage.tryLoad` so unit tests can drive it with a stub
/// `URLProtocol` without instantiating a SwiftUI view.
///
/// The in-memory `AsyncImageCache` lookup is intentionally OUTSIDE this
/// loader so tests can exercise the network path deterministically; the
/// view's `tryLoadAndApply` consults the cache before calling here.
enum AsyncImageLoader {
    /// - Returns: decoded `UIImage` on 2xx + decodable bytes; nil on non-2xx
    ///   or decode failure. Throws `CancellationError` if the task was
    ///   cancelled mid-flight.
    static func load(url: URL, session: URLSession) async throws -> UIImage? {
        // Consult the process-wide decoded-image cache first. A hit is
        // synchronous and avoids the network round-trip.
        if let cached = AsyncImageCache.shared.image(for: url) {
            return cached
        }
        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Issue 3 (3A) — evict non-2xx so a 404 doesn't stick for the
            // Cache-Control TTL after the variant later becomes available.
            session.configuration.urlCache?.removeCachedResponse(for: request)
            return nil
        }
        return UIImage(data: data)
    }
}
