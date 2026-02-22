//
//  SpotsBottomSheetView.swift
//  Spots.Test
//
//  Draggable bottom sheet for displaying nearby spots carousel
//

import SwiftUI

enum BottomSheetState {
    case collapsed
    case expanded
    
    var height: CGFloat {
        switch self {
        case .collapsed:
            return 110 // Just drag handle + title
        case .expanded:
            return 240 // Title + carousel
        }
    }
}

struct SpotsBottomSheetView: View {
    // State
    @Binding var sheetState: BottomSheetState
    @GestureState private var dragOffset: CGFloat = 0
    
    // Data
    let spots: [NearbySpot]
    let isLoading: Bool
    let hasMorePages: Bool
    let errorMessage: String?
    let spotListTypeMap: [String: ListType]
    let hasLoadedSavedPlaces: Bool
    
    // Callbacks
    let onBookmarkTap: (NearbySpot) -> Void
    let onCardTap: (NearbySpot) -> Void
    let onLoadMore: () -> Void
    let onRetry: () -> Void
    
    // Layout constants
    private let dragHandleWidth: CGFloat = 40
    private let dragHandleHeight: CGFloat = 4
    private let cornerRadius: CGFloat = 24
    private let horizontalPadding: CGFloat = 20
    
    // Animation
    private let springAnimation = Animation.spring(response: 0.3, dampingFraction: 0.8)
    
    // Computed height including drag offset
    private var currentHeight: CGFloat {
        let baseHeight = sheetState.height
        // When dragging up (negative offset), increase height
        // When dragging down (positive offset), decrease height
        let adjustedHeight = baseHeight - dragOffset
        // Clamp to reasonable bounds
        return max(80, min(350, adjustedHeight))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag Handle Area
            dragHandle
                .contentShape(Rectangle())
            
            // Title
            titleSection
            
            // Carousel (only in expanded state)
            if sheetState == .expanded || dragOffset < -50 {
                carouselSection
                    .transition(.opacity)
            }
            
            Spacer(minLength: 0)
        }
        .frame(height: currentHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: cornerRadius
            )
            .fill(Color.white)
            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: -4)
        )
        .gesture(dragGesture)
        .animation(springAnimation, value: sheetState)
    }
    
    // MARK: - Drag Handle
    
    private var dragHandle: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray300)
                .frame(width: dragHandleWidth, height: dragHandleHeight)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        Text("Spots Near Me")
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(.gray900)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 20)
    }
    
    // MARK: - Carousel Section
    
    private var carouselSection: some View {
        SpotsCarouselView(
            spots: spots,
            isLoading: isLoading,
            hasMorePages: hasMorePages,
            spotListTypeMap: spotListTypeMap,
            hasLoadedSavedPlaces: hasLoadedSavedPlaces,
            onBookmarkTap: onBookmarkTap,
            onCardTap: onCardTap,
            onLoadMore: onLoadMore,
            errorMessage: errorMessage,
            onRetry: onRetry
        )
    }
    
    // MARK: - Drag Gesture
    
    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let velocity = value.predictedEndLocation.y - value.location.y
                let offset = value.translation.height
                
                // Determine intent based on velocity and offset
                let isDraggingUp = velocity < -500 || offset < -100
                let isDraggingDown = velocity > 500 || offset > 100
                
                withAnimation(springAnimation) {
                    if isDraggingUp {
                        sheetState = .expanded
                    } else if isDraggingDown {
                        sheetState = .collapsed
                    }
                    // Otherwise, snap back to current state
                }
            }
    }
}

// MARK: - Preview

#Preview("Expanded") {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            SpotsBottomSheetView(
                sheetState: .constant(.expanded),
                spots: [
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
                    )
                ],
                isLoading: false,
                hasMorePages: true,
                errorMessage: nil,
                spotListTypeMap: ["1": .starred, "2": .bucketList],
                hasLoadedSavedPlaces: true,
                onBookmarkTap: { _ in },
                onCardTap: { _ in },
                onLoadMore: { },
                onRetry: { }
            )
        }
    }
}

#Preview("Collapsed") {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            SpotsBottomSheetView(
                sheetState: .constant(.collapsed),
                spots: [],
                isLoading: false,
                hasMorePages: false,
                errorMessage: nil,
                spotListTypeMap: [:],
                hasLoadedSavedPlaces: false,
                onBookmarkTap: { _ in },
                onCardTap: { _ in },
                onLoadMore: { },
                onRetry: { }
            )
        }
    }
}

#Preview("Loading") {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            SpotsBottomSheetView(
                sheetState: .constant(.expanded),
                spots: [],
                isLoading: true,
                hasMorePages: false,
                errorMessage: nil,
                spotListTypeMap: [:],
                hasLoadedSavedPlaces: false,
                onBookmarkTap: { _ in },
                onCardTap: { _ in },
                onLoadMore: { },
                onRetry: { }
            )
        }
    }
}
