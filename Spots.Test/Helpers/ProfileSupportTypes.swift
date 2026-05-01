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
    /// Accepts both current titles (Top Spots / Want to Go) and legacy titles
    /// (Starred / Bucket List) so cached `CachedListTile` rows from before the
    /// rename still resolve to the correct color instead of the gray default.
    static func color(forTitle title: String) -> Color {
        switch title {
        case "Top Spots", "Starred":     return Color(red: 0.60, green: 0.50, blue: 0.30)
        case "Favorites":                return Color(red: 0.55, green: 0.30, blue: 0.30)
        case "Want to Go", "Bucket List": return Color(red: 0.28, green: 0.45, blue: 0.60)
        default:                         return Color.gray400
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

struct CityRowData {
    let name: String
    let count: Int
}

// MARK: - List tile loading

enum ProfileTileBuilder {
    /// Build the four-tile array (All Spots + Starred + Favorites + Bucket List)
    /// for any user given their pre-fetched lists. Returns the tiles plus the
    /// total spot count across system lists (used for the "Spots" stat).
    ///
    /// Round-trips: 1 RPC for per-list summaries + 1 batch SELECT for cover
    /// spot rows = 2 total. (Was ~8 sequential round-trips pre-perf-pass.)
    static func buildTiles(from userLists: [UserList]) async throws -> (tiles: [ListTileData], totalCount: Int) {
        let configs: [(type: ListType, title: String, color: Color)] = [
            (.starred,    "Starred",     ListTileData.color(forTitle: "Starred")),
            (.favorites,  "Favorites",   ListTileData.color(forTitle: "Favorites")),
            (.bucketList, "Bucket List", ListTileData.color(forTitle: "Bucket List")),
        ]

        // Map list-type → user's owned list, if it exists.
        let resolvedConfigs: [(config: (type: ListType, title: String, color: Color), list: UserList?)] =
            configs.map { config in
                (config, userLists.first { $0.listType == config.type })
            }

        // Step 1: one RPC for tile summaries across all present system lists.
        let presentListIds = resolvedConfigs.compactMap { $0.list?.id }
        let summaries = try await LocationSavingService.shared.getListTileSummaries(listIds: presentListIds)
        let summaryByListId: [UUID: LocationSavingService.ListTileSummary] =
            Dictionary(uniqueKeysWithValues: summaries.map { ($0.listId, $0) })

        // Step 2: one batch SELECT for the (up to 4) cover spot rows.
        // - Per-list cover = summary.mostRecentSpotId for each present list
        // - All-Spots cover = the most-recent saved across all lists (pick by max savedAt)
        let perListCoverIds = summaries.compactMap { $0.mostRecentSpotId }
        let allSpotsCoverId = summaries
            .compactMap { summary -> (id: String, savedAt: Date)? in
                guard let id = summary.mostRecentSpotId,
                      let savedAt = summary.mostRecentSavedAt else { return nil }
                return (id, savedAt)
            }
            .max(by: { $0.savedAt < $1.savedAt })?
            .id

        let coverPlaceIds = Set(perListCoverIds + [allSpotsCoverId].compactMap { $0 })
        let coverSpots = try await LocationSavingService.shared.getSpotsByPlaceIds(Array(coverPlaceIds))
        let spotByPlaceId: [String: Spot] =
            Dictionary(uniqueKeysWithValues: coverSpots.map { ($0.placeId, $0) })

        // Step 3: assemble tiles in memory — no further round-trips.
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

        return ([allSpotsTile] + systemTiles, totalCount)
    }
}
