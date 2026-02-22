//
//  SpotsCarouselView.swift
//  Spots.Test
//
//  Horizontal scrolling carousel of spot cards with pagination support
//

import SwiftUI

struct SpotsCarouselView: View {
    let spots: [NearbySpot]
    let isLoading: Bool
    let hasMorePages: Bool
    let spotListTypeMap: [String: ListType]
    let hasLoadedSavedPlaces: Bool
    let onBookmarkTap: (NearbySpot) -> Void
    let onCardTap: (NearbySpot) -> Void
    let onLoadMore: () -> Void
    
    // Optional error state
    var errorMessage: String?
    var onRetry: (() -> Void)?
    
    // Layout constants
    private let cardSpacing: CGFloat = 12
    private let horizontalPadding: CGFloat = 20
    private let skeletonCount = 3
    
    var body: some View {
        GeometryReader { geometry in
            let cardWidth = SpotCardView.cardWidth(for: geometry.size.width)
            
            Group {
                if isLoading && spots.isEmpty {
                    // Initial loading state - show skeletons
                    skeletonCarousel(cardWidth: cardWidth)
                } else if let error = errorMessage, spots.isEmpty {
                    // Error state
                    SpotsErrorStateView(
                        message: error,
                        onRetry: { onRetry?() }
                    )
                } else if spots.isEmpty {
                    // Empty state
                    SpotsEmptyStateView()
                } else {
                    // Spots carousel
                    spotsCarousel(cardWidth: cardWidth)
                }
            }
        }
        .frame(height: 140) // Card height (120) + vertical padding
    }
    
    // MARK: - Skeleton Carousel
    
    private func skeletonCarousel(cardWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: cardSpacing) {
                ForEach(0..<skeletonCount, id: \.self) { _ in
                    SkeletonSpotCard()
                        .frame(width: cardWidth, height: 120)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .scrollDisabled(true)
    }
    
    // MARK: - Spots Carousel
    
    private func spotsCarousel(cardWidth: CGFloat) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: cardSpacing) {
                    ForEach(Array(spots.enumerated()), id: \.element.id) { index, spot in
                        SpotCardView(
                            spot: spot,
                            spotListTypeMap: spotListTypeMap,
                            hasLoadedSavedPlaces: hasLoadedSavedPlaces,
                            onBookmarkTap: { onBookmarkTap(spot) },
                            onCardTap: { onCardTap(spot) }
                        )
                        .frame(width: cardWidth, height: 120)
                        .id(spot.id)
                        .onAppear {
                            // Trigger load more when approaching end
                            if index >= spots.count - 2 && hasMorePages && !isLoading {
                                onLoadMore()
                            }
                        }
                    }
                    
                    // Loading indicator for pagination
                    if isLoading && !spots.isEmpty {
                        SkeletonSpotCard()
                            .frame(width: cardWidth, height: 120)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned) // Snap to cards
    }
}

// MARK: - Preview

#Preview("With Spots") {
    let mockSpots = [
        NearbySpot(
            placeId: "1",
            name: "Prince Street Pizza",
            address: "27 Prince St",
            city: nil,
            category: "Pizza",
            rating: 4.8,
            photoReference: nil,
            photoUrl: nil,
            latitude: 40.7234,
            longitude: -73.9945,
            distanceMeters: 160
        ),
        NearbySpot(
            placeId: "2",
            name: "Bowery Kitchen East",
            address: "193 Bowery",
            city: nil,
            category: "Restaurant",
            rating: 4.6,
            photoReference: nil,
            photoUrl: nil,
            latitude: 40.7220,
            longitude: -73.9930,
            distanceMeters: 250
        ),
        NearbySpot(
            placeId: "3",
            name: "Hester St. Market",
            address: "72 Hester St",
            city: nil,
            category: "Point of Interest",
            rating: nil,
            photoReference: nil,
            photoUrl: nil,
            latitude: 40.7180,
            longitude: -73.9920,
            distanceMeters: 400
        )
    ]
    
    VStack {
        Text("Spots Near Me")
            .font(.system(size: 24, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        
        SpotsCarouselView(
            spots: mockSpots,
            isLoading: false,
            hasMorePages: true,
            spotListTypeMap: ["1": .starred, "2": .favorites, "3": .bucketList],
            hasLoadedSavedPlaces: true,
            onBookmarkTap: { spot in print("Bookmark: \(spot.name)") },
            onCardTap: { spot in print("Card: \(spot.name)") },
            onLoadMore: { print("Load more") }
        )
    }
    .background(Color.white)
}

#Preview("Loading") {
    SpotsCarouselView(
        spots: [],
        isLoading: true,
        hasMorePages: false,
        spotListTypeMap: [:],
        hasLoadedSavedPlaces: false,
        onBookmarkTap: { _ in },
        onCardTap: { _ in },
        onLoadMore: { }
    )
    .background(Color.white)
}

#Preview("Empty") {
    SpotsCarouselView(
        spots: [],
        isLoading: false,
        hasMorePages: false,
        spotListTypeMap: [:],
        hasLoadedSavedPlaces: true,
        onBookmarkTap: { _ in },
        onCardTap: { _ in },
        onLoadMore: { }
    )
    .background(Color.white)
}

#Preview("Error") {
    SpotsCarouselView(
        spots: [],
        isLoading: false,
        hasMorePages: false,
        spotListTypeMap: [:],
        hasLoadedSavedPlaces: false,
        onBookmarkTap: { _ in },
        onCardTap: { _ in },
        onLoadMore: { },
        errorMessage: "Failed to load nearby spots",
        onRetry: { print("Retry") }
    )
    .background(Color.white)
}
