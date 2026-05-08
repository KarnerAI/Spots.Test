//
//  GooglePlacesImageView.swift
//  Spots.Test
//
//  Custom image view that loads images from Google Places API with required headers.
//  Uses ImageDownloadCoordinator to deduplicate in-flight requests for the same
//  (photoReference, maxWidth) tuple, so two views asking for the same place at
//  the same width share a single network call.
//
//  Cache strategy: bytes go through SpotImageCache keyed by (ref, width). A
//  280px thumbnail entry never serves a 1200px request and vice versa — fixes
//  prior cross-pollution where the save path inherited a low-res preview.
//

import SwiftUI

/// Deduplicates concurrent Google Places Photo requests so multiple views
/// asking for the same (photoReference, width) share one network call.
actor ImageDownloadCoordinator {
    static let shared = ImageDownloadCoordinator()

    private struct InFlightKey: Hashable {
        let photoReference: String
        let maxWidth: Int
    }

    private var inFlight: [InFlightKey: Task<UIImage?, Never>] = [:]
    private var failedRefs: Set<InFlightKey> = []
    private(set) var googlePhotoRequests = 0
    private(set) var dedupedRequests = 0

    func image(for photoReference: String, maxWidth: Int) async -> UIImage? {
        let key = InFlightKey(photoReference: photoReference, maxWidth: maxWidth)
        if failedRefs.contains(key) { return nil }

        if let cached = SpotImageCache.shared.image(for: photoReference, maxWidth: maxWidth) {
            return cached
        }

        if let existingTask = inFlight[key] {
            dedupedRequests += 1
            return await existingTask.value
        }

        googlePhotoRequests += 1
        let task = Task<UIImage?, Never> {
            do {
                let data = try await GooglePlacesPhotoFetcher.fetch(
                    photoReference: photoReference,
                    maxWidth: maxWidth
                )
                // Cache the raw bytes (not the decoded UIImage) so the save
                // path can reuse them without a UIImage→JPEG re-encode loss.
                SpotImageCache.shared.store(data, for: photoReference, maxWidth: maxWidth)
                return UIImage(data: data)
            } catch {
                print("❌ ImageDownloadCoordinator: fetch failed for \(photoReference) @ \(maxWidth)px: \(error)")
                return nil
            }
        }

        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil

        if result == nil {
            failedRefs.insert(key)
        }

        return result
    }

    func logStats() {
        print("📊 ImageDownloadCoordinator: googleRequests=\(googlePhotoRequests) deduped=\(dedupedRequests) failedRefs=\(failedRefs.count)")
    }
}

struct GooglePlacesImageView: View {
    let photoReference: String
    let maxWidth: Int
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray200)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            } else {
                Rectangle()
                    .fill(Color.gray200)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(.gray400)
                    )
            }
        }
        .task(id: photoReference) {
            guard image == nil else {
                isLoading = false
                return
            }
            let loaded = await ImageDownloadCoordinator.shared.image(for: photoReference, maxWidth: maxWidth)
            image = loaded
            isLoading = false
        }
    }
}
