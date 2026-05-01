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
    static func color(forTitle title: String) -> Color {
        switch title {
        case "Starred":     return Color(red: 0.60, green: 0.50, blue: 0.30)
        case "Favorites":   return Color(red: 0.55, green: 0.30, blue: 0.30)
        case "Bucket List": return Color(red: 0.28, green: 0.45, blue: 0.60)
        default:            return Color.gray400
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
    static func buildTiles(from userLists: [UserList]) async throws -> (tiles: [ListTileData], totalCount: Int) {
        let configs: [(type: ListType, title: String, color: Color)] = [
            (.starred,    "Starred",     ListTileData.color(forTitle: "Starred")),
            (.favorites,  "Favorites",   ListTileData.color(forTitle: "Favorites")),
            (.bucketList, "Bucket List", ListTileData.color(forTitle: "Bucket List")),
        ]

        var systemTiles: [ListTileData] = []
        var totalCount = 0
        var allListIds: [UUID] = []

        for config in configs {
            guard let list = userLists.first(where: { $0.listType == config.type }) else {
                systemTiles.append(ListTileData(
                    title: config.title, count: 0,
                    fallbackColor: config.color,
                    coverImageUrl: nil, coverPhotoReference: nil,
                    userList: nil, isAllSpots: false
                ))
                continue
            }

            allListIds.append(list.id)

            async let count = LocationSavingService.shared.getSpotCount(listId: list.id)
            async let recentSpot = LocationSavingService.shared.getMostRecentSpotInList(listId: list.id)
            let (resolvedCount, resolvedSpot) = try await (count, recentSpot)
            totalCount += resolvedCount

            systemTiles.append(ListTileData(
                title: config.title,
                count: resolvedCount,
                fallbackColor: config.color,
                coverImageUrl: resolvedSpot?.photoUrl,
                coverPhotoReference: resolvedSpot?.photoReference,
                userList: list,
                isAllSpots: false
            ))
        }

        let allSpotsSpot = try await LocationSavingService.shared.getMostRecentSpotAcrossLists(listIds: allListIds)
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
