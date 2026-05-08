//
//  PhotoQuality.swift
//  Spots.Test
//
//  Single source of truth for Google Places Photo dimensions and JPEG quality.
//  Keeps save-path resolution and feed-card display resolution aligned, so the
//  saved image is sharp at the size the feed actually renders it.
//
//  Display contexts:
//    - Full-bleed cards (Feed, Spot card hero):  PhotoQuality.maxWidthPx (1200)
//    - Small thumbnails (Profile grids 280, List 120): pass the explicit small
//      width to GooglePlacesImageView. SpotImageCache is keyed by (ref, width)
//      so small thumbnails never poison the high-res save cache.
//

import CoreGraphics

enum PhotoQuality {
    /// Width in pixels we request from Google Places Photo (New) for any image
    /// we'll persist or display full-bleed on a card. 1200 covers iPhone Pro Max
    /// (3× density) full-width cards with a small headroom and avoids stretching.
    static let maxWidthPx: Int = 1200

    /// JPEG compression quality used when we must re-encode locally (e.g., the
    /// share-extension or backfill paths that go through UIImage). Google's
    /// upstream JPEG is preserved on the primary save path, so this only kicks
    /// in on the rare cache-decoded fallback.
    static let jpegQuality: CGFloat = 0.9
}
