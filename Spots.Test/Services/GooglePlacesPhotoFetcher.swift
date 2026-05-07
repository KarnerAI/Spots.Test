//
//  GooglePlacesPhotoFetcher.swift
//  Spots.Test
//
//  Single source of truth for downloading a Google Places (New) photo by
//  photoReference. Both the live preview path (ImageDownloadCoordinator) and
//  the save path (ImageStorageService) call this. Standardizes on the
//  X-Goog-Api-Key header, never the URL query string, so the key never leaks
//  in logs, referers, or NSURLSession trace dumps.
//
//  Returns raw response Data (already JPEG from Google) so callers can either
//  store/upload the bytes verbatim (no lossy re-encode) or decode to UIImage
//  on demand.
//

import Foundation

enum GooglePlacesPhotoFetcher {
    enum FetchError: Error {
        case invalidURL
        case http(status: Int)
        case transport(underlying: Error)
    }

    /// Fetches photo bytes from the Google Places Photo (New) media endpoint.
    /// - Parameters:
    ///   - photoReference: The photo resource name, e.g. "places/{placeId}/photos/{photoId}".
    ///   - maxWidth: Pixel width to request from Google. Caller decides; for
    ///               persisted/full-bleed images use `PhotoQuality.maxWidthPx`.
    /// - Returns: Raw JPEG bytes from Google's response, or throws FetchError.
    static func fetch(photoReference: String, maxWidth: Int) async throws -> Data {
        let urlString = "https://places.googleapis.com/v1/\(photoReference)/media?maxWidthPx=\(maxWidth)"
        guard let url = URL(string: urlString) else {
            throw FetchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Config.googlePlacesAPIKey, forHTTPHeaderField: "X-Goog-Api-Key")
        if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FetchError.http(status: -1)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw FetchError.http(status: httpResponse.statusCode)
            }
            return data
        } catch let error as FetchError {
            throw error
        } catch {
            throw FetchError.transport(underlying: error)
        }
    }
}
