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
        // TODO: Replace with your Supabase project URL and anon key
        // You can find these in your Supabase Dashboard:
        // Settings → API → Project URL and anon/public key
        
        // Option 1: Direct configuration (for development)
        // Replace these with your actual values:
        let supabaseURLString = "https://dirqixrgkcdpixmriyge.supabase.co" // e.g., "https://your-project.supabase.co"
        let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRpcnFpeHJna2NkcGl4bXJpeWdlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY1NDQ5OTksImV4cCI6MjA4MjEyMDk5OX0.vi1r1eS0PqYxFHzsHOUv1_lifZgUadxklVehOtN_OMw" // Your anon/public key
        
        guard let supabaseURL = URL(string: supabaseURLString) else {
            fatalError("Invalid Supabase URL. Please check YOUR_SUPABASE_URL in SupabaseManager.swift")
        }
        
        client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey)
    }
}

