//
//  MarkerIconHelper.swift
//  Spots.Test
//
//  Shared static helpers for creating custom Google Maps marker icons.
//  Used by both MapViewModel (Explore map) and ListDetailView (list map toggle).
//

import UIKit
import GoogleMaps

// MARK: - MarkerIconHelper

enum MarkerIconHelper {

    /// Returns a custom circular marker icon for the given list membership set.
    /// Icons are looked up / stored in the provided cache to avoid repeated rendering.
    ///
    /// **Precedence (for All Spots / multi-list):** starred > favorites > bucketList.
    /// Internal enum names (and cache keys) kept stable across rename iterations;
    /// user-facing labels are Favorites (heart) / Liked (thumbs-up) / Want to Go (flag).
    /// Only spots that belong to at least one of these three list types get a custom
    /// icon; spots in no list or in other list types use the default teal pin.
    static func iconForListKinds(
        _ listKinds: Set<ListKind>,
        cache: inout [String: UIImage]
    ) -> UIImage? {
        let cacheKey: String
        let systemName: String
        let color: UIColor

        if listKinds.contains(.favorites) {
            cacheKey = "starred"
            systemName = "heart.fill"          // elite tier, displayed as "Favorites"
            color = .listStarred                // red
        } else if listKinds.contains(.liked) {
            cacheKey = "favorites"
            systemName = "hand.thumbsup.fill"  // mid tier, displayed as "Liked"
            color = .listFavorites              // blue
        } else if listKinds.contains(.wantToGo) {
            cacheKey = "bucketList"
            systemName = "flag.fill"            // wishlist, displayed as "Want to Go"
            color = .listBucketList             // emerald
        } else {
            // Default marker: spot is not in Favorites, Liked, or Want to Go.
            let tealColor = UIColor(red: 0.36, green: 0.69, blue: 0.72, alpha: 1.0)
            return GMSMarker.markerImage(with: tealColor)
        }

        if let cached = cache[cacheKey] {
            return cached
        }
        let icon = createCustomMarkerIcon(systemName: systemName, color: color)
        if let icon {
            cache[cacheKey] = icon
        }
        return icon
    }

    /// Renders a 32×32 circular icon with a colored fill, white border, and a white SF Symbol.
    static func createCustomMarkerIcon(systemName: String, color: UIColor) -> UIImage? {
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)

            // Colored circular background
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.fillEllipse(in: rect)

            // White border
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(2.0)
            context.cgContext.strokeEllipse(in: rect.insetBy(dx: 1.0, dy: 1.0))

            // White SF Symbol centered in circle
            if let icon = UIImage(systemName: systemName) {
                let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                let configuredIcon = icon.withConfiguration(config)
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                let iconSize: CGFloat = 14
                let iconRect = CGRect(
                    x: (size.width - iconSize) / 2,
                    y: (size.height - iconSize) / 2,
                    width: iconSize,
                    height: iconSize
                )
                configuredIcon.draw(in: iconRect)
            }
        }
    }

    /// Returns a new image scaled uniformly by `scale`.
    static func scaleImage(_ image: UIImage, to scale: CGFloat) -> UIImage {
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
