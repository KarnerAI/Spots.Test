//
//  PhotoQuality.swift
//  Spots.Test
//
//  Single source of truth for photo dimensions, JPEG quality, and the
//  variant-filename scheme that drives the cached-egress reduction work.
//
//  Display contexts:
//    - Full-bleed cards (Feed, Spot card hero):  ImageVariant.full   (1200px)
//    - List rows, SpotCard thumbnails:           ImageVariant.thumb  (400px)
//    - Avatars and tiny inline images:           ImageVariant.avatar (96px)
//
//  Storage layout: variants live alongside the canonical file in the
//  `spot-images` bucket. For an un-versioned spot the canonical object is
//  `{placeId}.jpg`; its variants are `{placeId}_w400.jpg` and `{placeId}_w96.jpg`.
//  For a backfilled (versioned) spot the canonical object is
//  `{placeId}_v{n}.jpg` and its variants are `{placeId}_v{n}_w400.jpg` etc.
//
//  Callers derive a variant URL from a spot's existing `photo_url` via
//  `ImageStorageService.variantURL(...)` — no DB migration required.
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

/// A size-classed variant of a stored spot image.
///
/// Variants are pre-generated at upload (and backfill) time and uploaded as
/// sibling objects in Supabase Storage. Callers prefer the smallest variant
/// that still looks crisp at their display size; on a cold spot whose
/// variants haven't been generated yet, `CachedAsyncImage`'s fallback URL
/// transparently serves the canonical full-size image.
enum ImageVariant: String, CaseIterable {
    /// 1200px-wide JPEG — canonical, used for full-screen views.
    case full
    /// 400px-wide JPEG — feed cards, list thumbnails, spot grid tiles.
    case thumb
    /// 96px-wide JPEG — avatars and other tiny inline thumbnails.
    case avatar

    /// Target max-width in pixels for re-encoding.
    var maxWidthPx: Int {
        switch self {
        case .full:   return PhotoQuality.maxWidthPx
        case .thumb:  return 400
        case .avatar: return 96
        }
    }

    /// Suffix inserted before `.jpg` in the storage filename.
    /// `.full` has no suffix — the canonical filename is unchanged so existing
    /// `spots.photo_url` values keep working without backfill.
    var filenameSuffix: String {
        switch self {
        case .full:   return ""
        case .thumb:  return "_w400"
        case .avatar: return "_w96"
        }
    }

    /// All non-`.full` variants. Used by upload / backfill to enumerate the
    /// sibling files to generate.
    static let sized: [ImageVariant] = [.thumb, .avatar]
}
