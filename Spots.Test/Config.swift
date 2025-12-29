//
//  Config.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation

struct Config {
    // MARK: - Google Places API Configuration
    // 
    // To set up your Google Places API key:
    // 1. Go to https://console.cloud.google.com/
    // 2. Create or select a project
    // 3. Enable "Places API (New)" in the API Library
    // 4. Go to Credentials and create an API key
    // 5. (Recommended) Restrict the API key to your iOS app bundle ID
    // 6. Replace the value below with your API key
    //
    // Alternatively, you can set this via environment variable or Info.plist
    // For production, consider using a secure configuration system
    
    static let googlePlacesAPIKey: String = {
        // Option 1: Check Info.plist first
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GooglePlacesAPIKey") as? String,
           !apiKey.isEmpty {
            return apiKey
        }
        
        // Option 2: Check environment variable (for CI/CD)
        if let apiKey = ProcessInfo.processInfo.environment["GOOGLE_PLACES_API_KEY"],
           !apiKey.isEmpty {
            return apiKey
        }
        
        // Option 3: Hardcoded fallback (NOT RECOMMENDED for production)
        // Replace this with your actual API key or use one of the methods above
        return "AIzaSyAK2BCSCWDS1uwAZmcG2jie4eNP8QrhGUw"
    }()
}

