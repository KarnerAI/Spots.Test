//
//  ImageStorageService.swift
//  Spots.Test
//
//  Service for handling spot image uploads to Supabase Storage
//

import Foundation
import UIKit
import Supabase

class ImageStorageService {
    static let shared = ImageStorageService()
    
    private let bucketName = "spot-images"
    private let supabaseClient = SupabaseManager.shared.client
    /// Base URL for the Supabase project (matches SupabaseManager). Used to build public Storage URLs.
    private let supabaseBaseURLString = "https://dirqixrgkcdpixmriyge.supabase.co"
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Downloads image from Google Places Photo API and uploads to Supabase Storage
    /// - Parameters:
    ///   - photoReference: The Google Places photo reference (from photos[].name)
    ///   - placeId: The Google Place ID (used as filename)
    /// - Returns: The public URL of the uploaded image in Supabase Storage, or nil if failed
    func uploadSpotImage(photoReference: String, placeId: String) async -> String? {
        // Step 1: Download image from Google Places Photo API
        guard let imageData = await downloadImageFromGoogle(photoReference: photoReference) else {
            print("❌ ImageStorageService: Failed to download image from Google")
            return nil
        }
        
        // Step 1.5: Cache the image in memory so the UI never re-downloads from Google
        if let uiImage = UIImage(data: imageData) {
            SpotImageCache.shared.store(uiImage, for: photoReference)
        }
        
        // Step 2: Upload to Supabase Storage
        return await uploadToSupabase(imageData: imageData, placeId: placeId)
    }
    
    /// Checks if an image already exists in Supabase Storage for a place
    /// - Parameter placeId: The Google Place ID
    /// - Returns: The public URL if image exists, nil otherwise
    func getExistingImageUrl(placeId: String) -> String? {
        let fileName = sanitizeFileName(placeId)
        // Public URL format: https://{project-ref}.supabase.co/storage/v1/object/public/spot-images/{fileName}
        return "\(supabaseBaseURLString)/storage/v1/object/public/\(bucketName)/\(fileName)"
    }
    
    // MARK: - Private Methods
    
    /// Downloads image data from Google Places Photo API
    private func downloadImageFromGoogle(photoReference: String) async -> Data? {
        // The photoReference from Places API (New) is in format: "places/{placeId}/photos/{photoRef}"
        // We need to use the Place Photos API with the photo name
        let photoName = photoReference // Already in correct format
        let urlString = "https://places.googleapis.com/v1/\(photoName)/media?maxWidthPx=400&key=\(Config.googlePlacesAPIKey)"
        
        guard let url = URL(string: urlString) else {
            print("❌ ImageStorageService: Invalid Google Places Photo URL")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add bundle identifier header for iOS app restrictions
        if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("❌ ImageStorageService: Google API returned error status")
                return nil
            }
            
            return data
        } catch {
            print("❌ ImageStorageService: Error downloading from Google: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Uploads image data to Supabase Storage using the Supabase client (sends session JWT so RLS allows authenticated uploads).
    private func uploadToSupabase(imageData: Data, placeId: String) async -> String? {
        let fileName = sanitizeFileName(placeId)
        
        do {
            _ = try await supabaseClient.storage
                .from(bucketName)
                .upload(
                    fileName,
                    data: imageData,
                    options: FileOptions(
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )
            
            let publicUrl = getExistingImageUrl(placeId: placeId)
            print("✅ ImageStorageService: Successfully uploaded image for \(placeId)")
            return publicUrl
        } catch {
            print("❌ ImageStorageService: Error uploading to Supabase: \(error.localizedDescription)")
            if let storageError = error as? StorageError {
                print("❌ ImageStorageService: Storage error details: \(storageError)")
            }
            return nil
        }
    }
    
    /// Sanitizes place ID to create a valid filename
    /// Google Place IDs can contain characters that need to be URL-safe
    private func sanitizeFileName(_ placeId: String) -> String {
        // Replace any non-alphanumeric characters with underscores
        let sanitized = placeId.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "_", options: .regularExpression)
        return "\(sanitized).jpg"
    }
}

// MARK: - Error Handling

enum ImageStorageError: LocalizedError {
    case downloadFailed
    case uploadFailed
    case invalidPlaceId
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "Failed to download image from Google Places"
        case .uploadFailed:
            return "Failed to upload image to Supabase Storage"
        case .invalidPlaceId:
            return "Invalid place ID provided"
        }
    }
}
