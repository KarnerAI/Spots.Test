//
//  GooglePlacesImageView.swift
//  Spots.Test
//
//  Custom image view that loads images from Google Places API with required headers.
//  Uses ImageDownloadCoordinator to deduplicate in-flight requests for the same photo.
//

import SwiftUI

/// Deduplicates concurrent Google Places Photo requests so multiple views
/// requesting the same photoReference share a single network call.
actor ImageDownloadCoordinator {
    static let shared = ImageDownloadCoordinator()
    
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var failedRefs: Set<String> = []
    private(set) var googlePhotoRequests = 0
    private(set) var dedupedRequests = 0
    
    func image(for photoReference: String, maxWidth: Int) async -> UIImage? {
        if failedRefs.contains(photoReference) { return nil }
        
        if let cached = SpotImageCache.shared.image(for: photoReference) {
            return cached
        }
        
        if let existingTask = inFlight[photoReference] {
            dedupedRequests += 1
            return await existingTask.value
        }
        
        googlePhotoRequests += 1
        let task = Task<UIImage?, Never> {
            let result = await Self.downloadFromGoogle(photoReference: photoReference, maxWidth: maxWidth)
            if let img = result {
                SpotImageCache.shared.store(img, for: photoReference)
            }
            return result
        }
        
        inFlight[photoReference] = task
        let result = await task.value
        inFlight[photoReference] = nil
        
        if result == nil {
            failedRefs.insert(photoReference)
        }
        
        return result
    }
    
    func logStats() {
        print("📊 ImageDownloadCoordinator: googleRequests=\(googlePhotoRequests) deduped=\(dedupedRequests) failedRefs=\(failedRefs.count)")
    }
    
    private static func downloadFromGoogle(photoReference: String, maxWidth: Int) async -> UIImage? {
        let urlString = "https://places.googleapis.com/v1/\(photoReference)/media?maxWidthPx=\(maxWidth)"
        guard let url = URL(string: urlString) else {
            print("❌ ImageDownloadCoordinator: Invalid URL: \(urlString)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Config.googlePlacesAPIKey, forHTTPHeaderField: "X-Goog-Api-Key")
        if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("❌ ImageDownloadCoordinator: HTTP \(statusCode) for \(photoReference)")
                return nil
            }
            
            guard let loadedImage = UIImage(data: data) else {
                print("❌ ImageDownloadCoordinator: Failed to create UIImage for \(photoReference)")
                return nil
            }
            
            return loadedImage
        } catch {
            print("❌ ImageDownloadCoordinator: Error loading \(photoReference): \(error.localizedDescription)")
            return nil
        }
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
