//
//  SkeletonSpotCard.swift
//  Spots.Test
//
//  Skeleton loading placeholder for SpotCardView
//

import SwiftUI

struct SkeletonSpotCard: View {
    @State private var isAnimating = false
    
    // Card dimensions (matching SpotCardView)
    private let cardHeight: CGFloat = 120
    private let imageSize: CGFloat = 120
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: Image placeholder
            Rectangle()
                .fill(shimmerGradient)
                .frame(width: imageSize, height: imageSize)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 16,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
            
            // Right: Content placeholders
            VStack(alignment: .leading, spacing: 0) {
                // Row 1: Name placeholder
                Rectangle()
                    .fill(shimmerGradient)
                    .frame(height: 18)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(4)
                
                Spacer()
                    .frame(height: 8)
                
                // Row 2: Address placeholder
                Rectangle()
                    .fill(shimmerGradient)
                    .frame(width: 140, height: 12)
                    .cornerRadius(4)
                
                Spacer()
                
                // Row 3: Category + bookmark placeholder
                HStack {
                    // Category badge placeholder
                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(width: 80, height: 24)
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    // Bookmark button placeholder
                    Circle()
                        .fill(shimmerGradient)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: cardHeight)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        .onAppear {
            withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
    
    // MARK: - Shimmer Gradient
    
    private var shimmerGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.gray200,
                Color.gray200.opacity(0.5),
                Color.gray200
            ]),
            startPoint: isAnimating ? .trailing : .leading,
            endPoint: isAnimating ? .leading : .trailing
        )
    }
}

// MARK: - Shimmer Modifier (Alternative approach)

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.white.opacity(0.4), location: 0.5),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

#Preview {
    VStack(spacing: 12) {
        SkeletonSpotCard()
            .frame(width: SpotCardView.cardWidth(for: 393))
        
        SkeletonSpotCard()
            .frame(width: SpotCardView.cardWidth(for: 393))
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
