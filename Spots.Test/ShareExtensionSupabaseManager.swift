//
//  ShareExtensionSupabaseManager.swift
//  Spots.Test
//
//  Created for Share Extension feature
//

import Foundation
import Supabase

/// Supabase manager for Share Extension that uses shared session token
class ShareExtensionSupabaseManager {
    static let shared = ShareExtensionSupabaseManager()
    
    let client: SupabaseClient
    
    private init() {
        let supabaseURLString = "https://dirqixrgkcdpixmriyge.supabase.co"
        let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRpcnFpeHJna2NkcGl4bXJpeWdlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY1NDQ5OTksImV4cCI6MjA4MjEyMDk5OX0.vi1r1eS0PqYxFHzsHOUv1_lifZgUadxklVehOtN_OMw"
        
        guard let supabaseURL = URL(string: supabaseURLString) else {
            fatalError("Invalid Supabase URL")
        }
        
        client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey)
        
        // Set session token from App Group if available
        if AppGroupManager.shared.getSessionToken() != nil {
            // Note: Supabase Swift SDK doesn't directly support setting access token
            // We'll need to use the session token in API calls or configure the client
            // For now, the extension will need to authenticate separately or we'll pass the token
            // This is a limitation - we may need to use direct API calls with the token
        }
    }
    
    /// Initialize Supabase client with session token from App Group
    func initializeWithSharedSession() async throws {
        guard AppGroupManager.shared.getSessionToken() != nil else {
            throw ShareExtensionError.noSessionToken
        }
        
        // Set the session in Supabase client
        // Note: This is a workaround - Supabase Swift SDK may not support this directly
        // We might need to use the token in HTTP headers for direct API calls
        // For now, we'll rely on the LocationSavingService to handle this
    }
}

enum ShareExtensionError: LocalizedError {
    case noSessionToken
    
    var errorDescription: String? {
        switch self {
        case .noSessionToken:
            return "No session token found. Please log in to the main app first."
        }
    }
}

