//
//  AppGroupManager.swift
//  Spots.Test
//
//  Created for Share Extension feature
//

import Foundation

/// Manages data sharing between main app and share extension using App Group
class AppGroupManager {
    static let shared = AppGroupManager()
    
    private let sharedUserDefaults: UserDefaults? = UserDefaults(suiteName: Config.appGroupIdentifier)

    private init() {
        assert(sharedUserDefaults != nil,
               "App Group '\(Config.appGroupIdentifier)' not configured. Check entitlements and provisioning profile.")
    }
    
    // MARK: - Session Token Sharing
    
    /// Save Supabase session token to shared container
    func saveSessionToken(_ token: String) {
        sharedUserDefaults?.set(token, forKey: "supabase_session_token")
    }
    
    /// Retrieve Supabase session token from shared container
    func getSessionToken() -> String? {
        return sharedUserDefaults?.string(forKey: "supabase_session_token")
    }
    
    /// Clear session token from shared container
    func clearSessionToken() {
        sharedUserDefaults?.removeObject(forKey: "supabase_session_token")
    }
    
    // MARK: - Share Extension Data
    
    /// Save data to be processed by share extension
    func saveShareData(_ data: [String: Any]) {
        sharedUserDefaults?.set(data, forKey: "share_extension_data")
    }
    
    /// Retrieve share extension data
    func getShareData() -> [String: Any]? {
        return sharedUserDefaults?.dictionary(forKey: "share_extension_data")
    }
    
    /// Clear share extension data
    func clearShareData() {
        sharedUserDefaults?.removeObject(forKey: "share_extension_data")
    }
}

