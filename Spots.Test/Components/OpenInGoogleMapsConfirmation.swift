//
//  OpenInGoogleMapsConfirmation.swift
//  Spots.Test
//
//  Reusable view modifier that presents the system "Open in Google Maps?"
//  confirmation as a native action sheet anchored to the bottom of the
//  screen. Attach to the screen root (not a child card) so the sheet
//  always covers the full screen.
//

import SwiftUI
import UIKit

extension View {
    /// Presents a native confirmation dialog when `place` becomes non-nil,
    /// offering to open the place in Google Maps. Works with any
    /// `GoogleMapsLinkable` (`Spot`, `NearbySpot`).
    func openInGoogleMapsConfirmation<Place: GoogleMapsLinkable & Equatable>(
        place: Binding<Place?>
    ) -> some View {
        modifier(OpenInGoogleMapsConfirmationModifier(place: place))
    }
}

private struct OpenInGoogleMapsConfirmationModifier<Place: GoogleMapsLinkable & Equatable>: ViewModifier {
    @Binding var place: Place?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Open in Google Maps?",
            isPresented: Binding(
                get: { place != nil },
                set: { if !$0 { place = nil } }
            ),
            titleVisibility: .visible,
            presenting: place
        ) { presented in
            Button("Open") {
                if let url = GoogleMapsLink.url(for: presented) {
                    UIApplication.shared.open(url)
                }
                place = nil
            }
            Button("Cancel", role: .cancel) { place = nil }
        } message: { presented in
            Text(presented.name)
        }
    }
}
