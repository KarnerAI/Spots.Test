//
//  SupabaseManager.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation
import Supabase

class SupabaseManager {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    private init() {
        guard let supabaseURL = URL(string: Config.supabaseURL) else {
            fatalError("Invalid Supabase URL: '\(Config.supabaseURL)'. Check SupabaseURL in Info.plist.")
        }

        client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: Config.supabaseAnonKey)
    }
}

