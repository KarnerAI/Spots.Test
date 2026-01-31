//
//  GooglePlacesImageView.swift
//  Spots.Test
//
//  Custom image view that loads images from Google Places API with required headers
//

import SwiftUI

struct GooglePlacesImageView: View {
    let photoReference: String
    let maxWidth: Int
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadError: Error?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                // Loading placeholder
                Rectangle()
                    .fill(Color.gray200)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            } else {
                // Error placeholder
                Rectangle()
                    .fill(Color.gray200)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(.gray400)
                    )
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        // Construct URL (API key will be in header, not query param)
        let urlString = "https://places.googleapis.com/v1/\(photoReference)/media?maxWidthPx=\(maxWidth)"
        guard let url = URL(string: urlString) else {
            print("❌ GooglePlacesImageView: Invalid URL: \(urlString)")
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add required headers for Google Places API (New)
        request.setValue(Config.googlePlacesAPIKey, forHTTPHeaderField: "X-Goog-Api-Key")
        
        // Add bundle identifier header for iOS app restrictions
        if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ GooglePlacesImageView: Invalid response")
                isLoading = false
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ GooglePlacesImageView: HTTP \(httpResponse.statusCode): \(errorMessage)")
                isLoading = false
                return
            }
            
            guard let loadedImage = UIImage(data: data) else {
                print("❌ GooglePlacesImageView: Failed to create UIImage from data")
                isLoading = false
                return
            }
            
            await MainActor.run {
                self.image = loadedImage
                self.isLoading = false
            }
            
        } catch {
            print("❌ GooglePlacesImageView: Error loading image: \(error.localizedDescription)")
            await MainActor.run {
                self.loadError = error
                self.isLoading = false
            }
        }
    }
}
