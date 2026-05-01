//
//  Spots_TestApp.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI
import GoogleMaps

/// One-shot Google Maps SDK bootstrap. Called lazily the first time a
/// `GMSMapView` is about to be instantiated so the SDK warmup doesn't sit
/// on the cold-start main-thread path.
enum GoogleMapsBootstrap {
    private static let _initialize: Void = {
        GMSServices.provideAPIKey(Config.googlePlacesAPIKey)
    }()

    static func ensureInitialized() {
        _ = _initialize
    }
}

@main
struct Spots_TestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
