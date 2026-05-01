//
//  CachedAsyncImage.swift
//  Spots.Test
//
//  Drop-in replacement for SwiftUI's AsyncImage(url:) that caches decoded
//  UIImage objects in memory keyed by URL. Re-renders during scrolling /
//  carousel paging hit the cache synchronously instead of triggering a
//  fresh URLSession download + image decode each time.
//
//  Underlying transport is still URLSession.shared, so URLCache.shared
//  provides on-disk HTTP caching across app launches. This adds in-memory
//  decoded-image caching on top of that.
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
/// On a cache hit, `phase` is `.success` synchronously so there's no flash.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
        // Initialize phase synchronously from cache so first render shows the
        // image without an .empty flash when we already have it.
        if let url, let cached = AsyncImageCache.shared.image(for: url) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            await MainActor.run { phase = .empty }
            return
        }

        // Synchronous cache hit — already set in init; nothing to do.
        if let cached = AsyncImageCache.shared.image(for: url) {
            await MainActor.run { phase = .success(Image(uiImage: cached)) }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            guard let ui = UIImage(data: data) else {
                await MainActor.run {
                    phase = .failure(URLError(.cannotDecodeContentData))
                }
                return
            }
            AsyncImageCache.shared.set(ui, for: url)
            await MainActor.run { phase = .success(Image(uiImage: ui)) }
        } catch is CancellationError {
            // View went away mid-load. Don't touch state.
        } catch {
            await MainActor.run { phase = .failure(error) }
        }
    }
}
