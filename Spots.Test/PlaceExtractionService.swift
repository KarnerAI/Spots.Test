//
//  PlaceExtractionService.swift
//  Spots.Test
//
//  Created for Share Extension feature
//

import Foundation
import CoreLocation
import UIKit

/// Orchestrates the extraction of places from shared content
class PlaceExtractionService {
    static let shared = PlaceExtractionService()
    
    private let openAIService = OpenAIService.shared
    private let placesAPIService = PlacesAPIService.shared
    
    private init() {}
    
    /// Extract places from shared content (text and images)
    /// - Parameters:
    ///   - text: Extracted text content
    ///   - images: Extracted images
    ///   - userLocation: Optional user location for better place matching
    /// - Returns: Array of place results with full details
    func extractPlaces(
        fromText text: String,
        images: [UIImage],
        userLocation: CLLocation? = nil
    ) async throws -> [PlaceAutocompleteResult] {
        var allPlaceNames: [String] = []
        
        // Extract from text if available
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let textPlaces = try await openAIService.extractPlacesFromText(text)
                allPlaceNames.append(contentsOf: textPlaces)
            } catch {
                print("Error extracting places from text: \(error)")
                // Continue with images even if text extraction fails
            }
        }
        
        // Extract from images if available
        if !images.isEmpty {
            do {
                let imagePlaces = try await openAIService.extractPlacesFromImages(images)
                allPlaceNames.append(contentsOf: imagePlaces)
            } catch {
                print("Error extracting places from images: \(error)")
                // Continue even if image extraction fails
            }
        }
        
        // Remove duplicates (case-insensitive)
        let uniquePlaceNames = Array(Set(allPlaceNames.map { $0.lowercased() }))
            .map { name in
                // Find original casing from allPlaceNames
                allPlaceNames.first { $0.lowercased() == name } ?? name.capitalized
            }
        
        guard !uniquePlaceNames.isEmpty else {
            return []
        }
        
        // Search Google Places API for each place name
        var placeResults: [PlaceAutocompleteResult] = []
        
        // Process in batches to avoid overwhelming the API
        let batchSize = 5
        for i in stride(from: 0, to: uniquePlaceNames.count, by: batchSize) {
            let batch = Array(uniquePlaceNames[i..<min(i + batchSize, uniquePlaceNames.count)])
            
            await withTaskGroup(of: PlaceAutocompleteResult?.self) { group in
                for placeName in batch {
                    group.addTask {
                        do {
                            let results = try await withCheckedThrowingContinuation { continuation in
                                self.placesAPIService.autocomplete(
                                    query: placeName,
                                    location: userLocation
                                ) { result in
                                    continuation.resume(with: result)
                                }
                            }
                            // Take the first/best match
                            return results.first
                        } catch {
                            print("Error searching for place '\(placeName)': \(error)")
                            return nil
                        }
                    }
                }
                
                for await result in group {
                    if let result = result {
                        placeResults.append(result)
                    }
                }
            }
        }
        
        // Remove duplicates by placeId
        var uniqueResults: [PlaceAutocompleteResult] = []
        var seenPlaceIds = Set<String>()
        
        for result in placeResults {
            if !seenPlaceIds.contains(result.placeId) {
                seenPlaceIds.insert(result.placeId)
                uniqueResults.append(result)
            }
        }
        
        return uniqueResults
    }
}

