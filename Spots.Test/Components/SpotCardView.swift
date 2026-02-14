//
//  SpotCardView.swift
//  Spots.Test
//
//  Horizontal spot card component for the bottom sheet carousel
//

import SwiftUI

struct SpotCardView: View {
    let spot: NearbySpot
    var spotListTypeMap: [String: ListType] = [:]
    var hasLoadedSavedPlaces: Bool = false
    let onBookmarkTap: () -> Void
    let onCardTap: () -> Void
    
    // Card dimensions
    private let cardHeight: CGFloat = 120
    private let imageSize: CGFloat = 120
    
    var body: some View {
        Button(action: onCardTap) {
            HStack(spacing: 0) {
                // Left: Image
                spotImage
                
                // Right: Content
                contentSection
            }
            .frame(height: cardHeight)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray200, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Image Section
    
    private var spotImage: some View {
        Group {
            // Try Supabase cached URL first (works with AsyncImage)
            if let photoURL = spot.photoURL(maxWidth: 400) {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .empty:
                        imagePlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        // Fall back to Google API if Supabase fails
                        if let photoRef = spot.photoReferenceForGoogleAPI() {
                            GooglePlacesImageView(photoReference: photoRef, maxWidth: 400)
                        } else {
                            imagePlaceholder
                        }
                    @unknown default:
                        imagePlaceholder
                    }
                }
            } else if let photoRef = spot.photoReferenceForGoogleAPI() {
                // Use custom loader for Google Places API (requires headers)
                GooglePlacesImageView(photoReference: photoRef, maxWidth: 400)
            } else {
                imagePlaceholder
            }
        }
        .frame(width: imageSize, height: imageSize)
        .clipped()
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
        )
    }
    
    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color.gray200)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundColor(.gray400)
            )
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Spot Name
            Text(spot.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.gray900)
                .lineLimit(1)
            
            Spacer()
                .frame(height: 8)
            
            // Row 2: Address + Distance
            HStack(spacing: 0) {
                Text(spot.address)
                    .lineLimit(1)
                
                if !spot.formattedDistance.isEmpty {
                    Text(" · ")
                    Text(spot.formattedDistance)
                        .layoutPriority(1) // Prevent distance from being truncated
                }
            }
            .font(.system(size: 12))
            .foregroundColor(.gray500)
            
            Spacer()
                .frame(minHeight: 12)
            
            // Row 3: Category + Rating + Bookmark
            HStack(spacing: 8) {
                // Category badge
                Text(spot.category)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray600)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray100)
                    .cornerRadius(4)
                    .lineLimit(1)
                
                // Rating (if exists)
                if let rating = spot.rating, rating > 0 {
                    Text("· \(String(format: "%.1f", rating))")
                        .font(.system(size: 14))
                        .foregroundColor(.gray600)
                }
                
                Spacer()
                
                // Bookmark button
                bookmarkButton
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Bookmark/List Icon Button
    
    private var bookmarkButton: some View {
        Button(action: {
            onBookmarkTap()
        }) {
            Group {
                if !hasLoadedSavedPlaces {
                    // Show bookmark until saved places are loaded
                    Image(systemName: "bookmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray500)
                } else if let listType = spotListTypeMap[spot.placeId] {
                    // Show list icon if spot is in a list
                    ListIconView(listType: listType)
                        .font(.system(size: 16, weight: .medium))
                } else {
                    // Show bookmark if spot is not in any list
                    Image(systemName: "bookmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray500)
                }
            }
            .frame(width: 36, height: 36)
            .background(Color.gray100)
            .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Circle())
    }
}

// MARK: - Card Width Helper

extension SpotCardView {
    /// Returns the recommended card width so the next card is barely visible (peek).
    /// Uses ~94% of screen width (max 370pt) so only a small sliver of the next card shows.
    static func cardWidth(for screenWidth: CGFloat) -> CGFloat {
        min(screenWidth * 0.94, 370)
    }
}

#Preview {
    let mockSpot = NearbySpot(
        placeId: "test123",
        name: "Prince Street Pizza",
        address: "27 Prince St",
        category: "Pizza",
        rating: 4.8,
        photoReference: nil,
        photoUrl: nil,
        latitude: 40.7234,
        longitude: -73.9945,
        distanceMeters: 160
    )
    
    return SpotCardView(
        spot: mockSpot,
        spotListTypeMap: ["test123": .starred],
        hasLoadedSavedPlaces: true,
        onBookmarkTap: { print("Bookmark tapped") },
        onCardTap: { print("Card tapped") }
    )
    .frame(width: SpotCardView.cardWidth(for: 393))
    .padding()
    .background(Color.gray.opacity(0.2))
}
