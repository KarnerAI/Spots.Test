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
    // 5. (Recommended) Restrict the API key to your iOS app bundle ID and API restrictions
    // 6. Add the key to Info.plist as "GooglePlacesAPIKey" (String type)
    //
    // Alternatively, you can set this via environment variable GOOGLE_PLACES_API_KEY (for CI/CD)
    
    static let googlePlacesAPIKey: String = {
        // Option 1: Check Info.plist first (RECOMMENDED)
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GooglePlacesAPIKey") as? String,
           !apiKey.isEmpty {
            // Debug logging: Show source and first few characters
            let keyPrefix = String(apiKey.prefix(8))
            print("✅ Google Places API key loaded from Info.plist (starts with: \(keyPrefix)...)")
            
            // Validate key format (Google API keys start with "AIza")
            if !apiKey.hasPrefix("AIza") {
                print("⚠️ WARNING: API key format may be incorrect. Google API keys typically start with 'AIza'")
            }
            
            return apiKey
        }
        
        // Option 2: Check environment variable (for CI/CD)
        if let apiKey = ProcessInfo.processInfo.environment["GOOGLE_PLACES_API_KEY"],
           !apiKey.isEmpty {
            // Debug logging: Show source and first few characters
            let keyPrefix = String(apiKey.prefix(8))
            print("✅ Google Places API key loaded from environment variable (starts with: \(keyPrefix)...)")
            
            // Validate key format
            if !apiKey.hasPrefix("AIza") {
                print("⚠️ WARNING: API key format may be incorrect. Google API keys typically start with 'AIza'")
            }
            
            return apiKey
        }
        
        // No API key found - fail explicitly with helpful error message
        print("❌ ERROR: Google Places API key not found in Info.plist or environment variables")
        fatalError("Google Places API key is not configured. Please add it to Info.plist as 'GooglePlacesAPIKey' or set the GOOGLE_PLACES_API_KEY environment variable.")
    }()
    
    // MARK: - Unsplash API Configuration
    //
    // To set up your Unsplash Access Key:
    // 1. Go to https://unsplash.com/developers and create a free account
    // 2. Create a new application to get your Access Key
    // 3. Add the key to Info.plist as "UnsplashAccessKey" (String type)
    //
    // Free tier: 50 requests/hour — sufficient for profile cover photo loading.
    static let unsplashAccessKey: String = {
        if let key = Bundle.main.object(forInfoDictionaryKey: "UnsplashAccessKey") as? String,
           !key.isEmpty {
            print("✅ Unsplash Access Key loaded from Info.plist")
            return key
        }
        if let key = ProcessInfo.processInfo.environment["UNSPLASH_ACCESS_KEY"],
           !key.isEmpty {
            print("✅ Unsplash Access Key loaded from environment variable")
            return key
        }
        print("⚠️ Unsplash Access Key not configured — cover photos will use gradient placeholder")
        return ""
    }()

    // MARK: - App Group Configuration
    // App Group identifier for sharing data between main app and share extension
    // This must match the App Group identifier configured in Xcode project settings
    static let appGroupIdentifier = "group.com.karnerblu.Spots-Test"
}

