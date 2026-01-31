//
//  SpotsEmptyStateView.swift
//  Spots.Test
//
//  Empty state view when no nearby spots are found
//

import SwiftUI

struct SpotsEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: "mappin.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray400)
            
            // Title
            Text("No spots nearby")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.gray900)
            
            // Subtitle
            Text("Try moving the map or changing filters")
                .font(.system(size: 14))
                .foregroundColor(.gray500)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Error State Variant

struct SpotsErrorStateView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.gray400)
            
            // Title
            Text("Something went wrong")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.gray900)
            
            // Message
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.gray500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Retry button
            Button(action: onRetry) {
                Text("Try Again")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.spotsTeal)
                    .cornerRadius(20)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Location Permission State

struct LocationPermissionStateView: View {
    let onRequestPermission: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: "location.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray400)
            
            // Title
            Text("Location access needed")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.gray900)
            
            // Subtitle
            Text("Enable location access to discover spots near you")
                .font(.system(size: 14))
                .foregroundColor(.gray500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Enable button
            Button(action: onRequestPermission) {
                Text("Enable Location")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.spotsTeal)
                    .cornerRadius(20)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

#Preview("Empty State") {
    SpotsEmptyStateView()
        .background(Color.white)
}

#Preview("Error State") {
    SpotsErrorStateView(
        message: "Failed to load nearby spots. Please check your connection.",
        onRetry: { print("Retry tapped") }
    )
    .background(Color.white)
}

#Preview("Location Permission") {
    LocationPermissionStateView(
        onRequestPermission: { print("Request permission tapped") }
    )
    .background(Color.white)
}
