//
//  Spots_TestApp.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI
import GoogleMaps

@main
struct Spots_TestApp: App {
    init() {
        // Initialize Google Maps with API key
        GMSServices.provideAPIKey(Config.googlePlacesAPIKey)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
