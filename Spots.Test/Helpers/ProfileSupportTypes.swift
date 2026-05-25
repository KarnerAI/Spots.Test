//
//  ProfileSupportTypes.swift
//  Spots.Test
//
//  Types shared by ProfileView (own profile) and UserProfileView (other user's
//  profile) so both screens render the same list-tile and city-row UI.
//

import SwiftUI

struct ListTileData {
    let title: String
    let count: Int
    let fallbackColor: Color
    let coverImageUrl: String?
    let coverPhotoReference: String?
    let userList: UserList?
    let isAllSpots: Bool

    /// Deterministic fallback color based on tile title.
    /// Tile backgrounds are muted variants of the tier's icon color. Switch
    /// arms accept legacy titles (v1: Starred/Bucket List, v2: Top Spots) so
    /// stale `CachedListTile` rows from before each rename still resolve to
    /// the right color instead of the gray default. The cache version bump
    /// in `ProfileSnapshotCache` invalidates these on next launch, but legacy
    /// matches keep the experience clean if anything slips through.
    ///
    /// Tier mapping for current display labels (Iteration 2):
    ///   "Favorites" (elite, red heart)  → muted red
    ///   "Liked"     (mid, blue thumb)   → muted blue
    ///   "Want to Go" (wishlist, emerald flag) → muted emerald
    static func color(forTitle title: String) -> Color {
        switch title {
        // Elite tier: current "Favorites", legacy "Top Spots"/"Starred"
        case "Favorites", "Top Spots", "Starred":
            return Color(red: 0.55, green: 0.30, blue: 0.30)
        // Mid tier: current "Liked", legacy "Favorites" handled above (resolves
        // to elite-red since "Favorites" now means elite). Pre-v3 caches with
        // mid-tier titles can't be reliably distinguished from elite — they
        // get invalidated by the cache version bump.
        case "Liked":
            return Color(red: 0.28, green: 0.45, blue: 0.60)
        // Wishlist tier: current "Want to Go", legacy "Bucket List"
        case "Want to Go", "Bucket List":
            return Color(red: 0.20, green: 0.45, blue: 0.35)
        default:
            return Color.gray400
        }
    }

    init(cached: CachedListTile) {
        title = cached.title
        count = cached.count
        fallbackColor = Self.color(forTitle: cached.title)
        coverImageUrl = cached.coverImageUrl
        coverPhotoReference = cached.coverPhotoReference
        userList = cached.userList
        isAllSpots = cached.isAllSpots
    }

    init(title: String, count: Int, fallbackColor: Color, coverImageUrl: String?,
         coverPhotoReference: String?, userList: UserList?, isAllSpots: Bool) {
        self.title = title
        self.count = count
        self.fallbackColor = fallbackColor
        self.coverImageUrl = coverImageUrl
        self.coverPhotoReference = coverPhotoReference
        self.userList = userList
        self.isAllSpots = isAllSpots
    }

    func toCached() -> CachedListTile {
        CachedListTile(title: title, count: count, coverImageUrl: coverImageUrl,
                       coverPhotoReference: coverPhotoReference, userList: userList,
                       isAllSpots: isAllSpots)
    }
}

struct CityRowData: Identifiable, Hashable {
    /// Normalized (trimmed + lowercased) name; serves as the filter key.
    let id: String
    /// Display casing for the row, taken from a representative spot.
    let name: String
    let count: Int

    init(id: String, name: String, count: Int) {
        self.id = id
        self.name = name
        self.count = count
    }

    /// Convenience used by UserProfileView's placeholder list — derives the
    /// id from a normalized form of the display name.
    init(name: String, count: Int) {
        self.id = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.name = name
        self.count = count
    }
}

struct CountryRowData: Identifiable, Hashable {
    /// Normalized (trimmed + lowercased) name; serves as the filter key.
    let id: String
    let displayName: String
    /// Flag emoji, or `nil` when `CountryFlag` couldn't resolve the string.
    let flag: String?
    let count: Int
}

// MARK: - Location grouping (shared by Profile travel map + ListDetailView filter)

/// Helpers for grouping spots by city/country with consistent normalization.
/// The same `normalize` function powers both the count-by-city aggregation in
/// ProfileView and the city/country filter in ListDetailView so a row's count
/// always matches what the filtered map ends up showing.
enum LocationGrouping {
    /// Trim whitespace and lowercase; returns nil for empty/whitespace-only input.
    static func normalize(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    /// `spot.displayCity` matches `query` after normalization. Prefers the
    /// true locality ("Paris") over the misnamed region column.
    static func matchesCity(_ spot: Spot, _ query: String) -> Bool {
        guard let normSpot = normalize(spot.displayCity), let normQuery = normalize(query) else { return false }
        return normSpot == normQuery
    }

    /// `spot.country` matches `query` after normalization.
    static func matchesCountry(_ spot: Spot, _ query: String) -> Bool {
        guard let normSpot = normalize(spot.country), let normQuery = normalize(query) else { return false }
        return normSpot == normQuery
    }

    /// Group spots by normalized city, dropping empties. Sorted by count desc, name asc.
    ///
    /// Uses `Spot.displayCity` so the Travel Map (and any other consumer)
    /// groups by the true locality ("Paris", "Rome") when present, falling
    /// back to the misnamed `city` (region) for pre-backfill rows. This was
    /// the user-visible bug that motivated the locality column: tapping a
    /// region label like "Île-de-France" surprised users who expected "Paris".
    static func cityRows(from spots: [Spot]) -> [CityRowData] {
        var buckets: [String: (display: String, count: Int)] = [:]
        for spot in spots {
            guard let display = spot.displayCity,
                  let key = normalize(display)
            else { continue }
            if var existing = buckets[key] {
                existing.count += 1
                buckets[key] = existing
            } else {
                buckets[key] = (display, 1)
            }
        }
        return buckets
            .map { CityRowData(id: $0.key, name: $0.value.display, count: $0.value.count) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    /// Group spots by normalized country, dropping empties. Adds flag emoji.
    /// Sorted by count desc, name asc.
    static func countryRows(from spots: [Spot]) -> [CountryRowData] {
        var buckets: [String: (display: String, count: Int)] = [:]
        for spot in spots {
            guard let key = normalize(spot.country),
                  let display = spot.country?.trimmingCharacters(in: .whitespacesAndNewlines), !display.isEmpty
            else { continue }
            if var existing = buckets[key] {
                existing.count += 1
                buckets[key] = existing
            } else {
                buckets[key] = (display, 1)
            }
        }
        return buckets
            .map { CountryRowData(
                id: $0.key,
                displayName: $0.value.display,
                flag: CountryFlag.emoji(for: $0.value.display),
                count: $0.value.count
            ) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }
}

// MARK: - List tile loading

enum ProfileTileBuilder {
    /// Build the four-tile array (All Spots + Top Spots + Favorites + Want to Go)
    /// for any user given their pre-fetched lists. Returns the tiles plus the
    /// total spot count across system lists (used for the "Spots" stat).
    ///
    /// Round-trips: 1 RPC for per-list summaries + 1 batch SELECT for cover
    /// spot rows = 2 total. (Was ~8 sequential round-trips pre-perf-pass.)
    static func buildTiles(from userLists: [UserList]) async throws -> (tiles: [ListTileData], totalCount: Int) {
        let systemConfigs: [(type: ListKind, title: String, color: Color)] = [
            (.favorites,    ListKind.favorites.displayName,    ListTileData.color(forTitle: ListKind.favorites.displayName)),
            (.liked,  ListKind.liked.displayName,  ListTileData.color(forTitle: ListKind.liked.displayName)),
            (.wantToGo, ListKind.wantToGo.displayName, ListTileData.color(forTitle: ListKind.wantToGo.displayName)),
        ]

        // Map system-kind config → user's owned list, if it exists.
        let resolvedConfigs: [(config: (type: ListKind, title: String, color: Color), list: UserList?)] =
            systemConfigs.map { config in
                (config, userLists.first { $0.kind == config.type })
            }

        // T21.6 follow-up: custom lists (kind not in systemKinds) also belong on
        // the Profile carousel, sorted newest-first. Without this, Maya creates
        // "Mexico City 2026" and it never shows up on the profile until she
        // taps View all — which broke the discoverability we just shipped.
        let customLists: [UserList] = userLists
            .filter { !$0.kind.isSystemKind }
            .sorted { (lhs, rhs) in
                let lDate = lhs.createdAt ?? Date.distantPast
                let rDate = rhs.createdAt ?? Date.distantPast
                return lDate > rDate
            }

        // Step 1: one RPC for tile summaries across ALL present lists (system + custom).
        let presentListIds: [UUID] =
            resolvedConfigs.compactMap { $0.list?.id }
            + customLists.map { $0.id }
        let summaries = try await LocationSavingService.shared.getListTileSummaries(listIds: presentListIds)
        let summaryByListId: [UUID: LocationSavingService.ListTileSummary] =
            Dictionary(uniqueKeysWithValues: summaries.map { ($0.listId, $0) })

        // Step 2: one batch SELECT for the (up to N) cover spot rows.
        // - Per-list cover = summary.mostRecentSpotId for each present list
        // - All-Spots cover = the most-recent saved across SYSTEM lists only
        //   (custom lists don't contribute to the All Spots dedup count;
        //   they're an independent organization layer per E4)
        let perListCoverIds = summaries.compactMap { $0.mostRecentSpotId }
        let systemListIds = Set(resolvedConfigs.compactMap { $0.list?.id })
        let allSpotsCoverId = summaries
            .compactMap { summary -> (id: String, savedAt: Date)? in
                guard systemListIds.contains(summary.listId),
                      let id = summary.mostRecentSpotId,
                      let savedAt = summary.mostRecentSavedAt else { return nil }
                return (id, savedAt)
            }
            .max(by: { $0.savedAt < $1.savedAt })?
            .id

        let coverPlaceIds = Set(perListCoverIds + [allSpotsCoverId].compactMap { $0 })
        let coverSpots = try await LocationSavingService.shared.getSpotsByPlaceIds(Array(coverPlaceIds))
        let spotByPlaceId: [String: Spot] =
            Dictionary(uniqueKeysWithValues: coverSpots.map { ($0.placeId, $0) })

        // Step 3a: system tiles (Favorites / Liked / Want to go) in canonical order.
        var systemTiles: [ListTileData] = []
        var totalCount = 0

        for resolved in resolvedConfigs {
            guard let list = resolved.list else {
                systemTiles.append(ListTileData(
                    title: resolved.config.title, count: 0,
                    fallbackColor: resolved.config.color,
                    coverImageUrl: nil, coverPhotoReference: nil,
                    userList: nil, isAllSpots: false
                ))
                continue
            }

            let summary = summaryByListId[list.id]
            let count = summary?.spotCount ?? 0
            let coverSpot = summary?.mostRecentSpotId.flatMap { spotByPlaceId[$0] }
            totalCount += count

            systemTiles.append(ListTileData(
                title: resolved.config.title,
                count: count,
                fallbackColor: resolved.config.color,
                coverImageUrl: coverSpot?.photoUrl,
                coverPhotoReference: coverSpot?.photoReference,
                userList: list,
                isAllSpots: false
            ))
        }

        // Step 3b: custom tiles in newest-first order. The title comes from
        // list.displayName (which falls back to kind for system kinds but
        // returns the user-supplied name for custom kinds).
        let customTiles: [ListTileData] = customLists.map { list in
            let summary = summaryByListId[list.id]
            let count = summary?.spotCount ?? 0
            let coverSpot = summary?.mostRecentSpotId.flatMap { spotByPlaceId[$0] }
            return ListTileData(
                title: list.displayName,
                count: count,
                fallbackColor: ListTileData.color(forTitle: list.displayName),
                coverImageUrl: coverSpot?.photoUrl,
                coverPhotoReference: coverSpot?.photoReference,
                userList: list,
                isAllSpots: false
            )
        }

        let allSpotsSpot = allSpotsCoverId.flatMap { spotByPlaceId[$0] }
        let allSpotsTile = ListTileData(
            title: "All Spots",
            count: totalCount,
            fallbackColor: ListTileData.color(forTitle: "All Spots"),
            coverImageUrl: allSpotsSpot?.photoUrl,
            coverPhotoReference: allSpotsSpot?.photoReference,
            userList: nil,
            isAllSpots: true
        )

        // Order: All Spots → system lists → custom lists (newest first).
        return ([allSpotsTile] + systemTiles + customTiles, totalCount)
    }
}
