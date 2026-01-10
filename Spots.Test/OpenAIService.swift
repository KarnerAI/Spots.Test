//
//  OpenAIService.swift
//  Spots.Test
//
//  Created for Share Extension feature
//

import Foundation
import UIKit

/// Service for extracting place names from content (stubbed out - OpenAI integration removed)
class OpenAIService {
    static let shared = OpenAIService()
    
    private init() {}
    
    /// Extract place names from text (stubbed - returns empty array)
    /// - Parameter text: Text content to analyze
    /// - Returns: Empty array (OpenAI integration removed)
    func extractPlacesFromText(_ text: String) async throws -> [String] {
        return []
    }
    
    /// Extract place names from images (stubbed - returns empty array)
    /// - Parameter images: Images to analyze
    /// - Returns: Empty array (OpenAI integration removed)
    func extractPlacesFromImages(_ images: [UIImage]) async throws -> [String] {
        return []
    }
}


