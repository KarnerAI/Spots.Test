//
//  Spots_TestTests.swift
//  Spots.TestTests
//
//  Created by Hussain Alam on 12/29/25.
//

import Testing
import UIKit
@testable import Spots_Test

struct Spots_TestTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

// MARK: - List Type Display Name Tests
//
// Guards against accidental rename / typo regressions in the user-facing
// labels for the three default lists. Internal enum cases (`starred`,
// `favorites`, `bucketList`) intentionally keep their original spellings
// — only `displayName` should change here in future renames.
struct ListTypeDisplayNameTests {

    @Test func starredDisplaysAsTopSpots() {
        #expect(ListType.starred.displayName == "Top Spots")
    }

    @Test func favoritesDisplaysAsFavorites() {
        #expect(ListType.favorites.displayName == "Favorites")
    }

    @Test func bucketListDisplaysAsWantToGo() {
        #expect(ListType.bucketList.displayName == "Want to Go")
    }
}

// MARK: - Display List Type Resolver Tests

struct DisplayListTypeResolverTests {
    
    @Test func emptySetReturnsNil() {
        let result = displayListType(for: [])
        #expect(result == nil)
    }
    
    @Test func starredOnlyReturnsStarred() {
        let result = displayListType(for: [.starred])
        #expect(result == .starred)
    }
    
    @Test func favoritesOnlyReturnsFavorites() {
        let result = displayListType(for: [.favorites])
        #expect(result == .favorites)
    }
    
    @Test func bucketListOnlyReturnsBucketList() {
        let result = displayListType(for: [.bucketList])
        #expect(result == .bucketList)
    }
    
    @Test func starredAndFavoritesReturnsStarred() {
        // Starred has higher priority than Favorites
        let result = displayListType(for: [.starred, .favorites])
        #expect(result == .starred)
    }
    
    @Test func bucketListAndStarredReturnsBucketList() {
        // BucketList has highest priority
        let result = displayListType(for: [.bucketList, .starred])
        #expect(result == .bucketList)
    }
    
    @Test func bucketListAndFavoritesReturnsBucketList() {
        // BucketList has highest priority
        let result = displayListType(for: [.bucketList, .favorites])
        #expect(result == .bucketList)
    }
    
    @Test func allThreeReturnsBucketList() {
        // BucketList has highest priority even when all are present
        let result = displayListType(for: [.bucketList, .starred, .favorites])
        #expect(result == .bucketList)
    }
}

// MARK: - Marker Icon Helper Tests (All Spots map custom markers)

struct MarkerIconHelperTests {

    /// Empty list types → default teal pin (non-nil).
    @Test func emptyListTypesReturnsDefaultIcon() {
        var cache: [String: UIImage] = [:]
        let icon = MarkerIconHelper.iconForListTypes([], cache: &cache)
        #expect(icon != nil)
        #expect(cache.isEmpty)
    }

    /// Single list type returns custom icon and caches it.
    @Test func singleListTypeReturnsCustomIcon() {
        var cache: [String: UIImage] = [:]
        let icon = MarkerIconHelper.iconForListTypes([.starred], cache: &cache)
        #expect(icon != nil)
        #expect(cache["starred"] != nil)
    }

    /// Precedence: starred > favorites > bucketList (multi-list uses starred).
    @Test func precedenceStarredOverFavorites() {
        var cache: [String: UIImage] = [:]
        let icon = MarkerIconHelper.iconForListTypes([.starred, .favorites], cache: &cache)
        #expect(icon != nil)
        #expect(cache["starred"] != nil)
    }

    @Test func precedenceFavoritesOverBucketList() {
        var cache: [String: UIImage] = [:]
        let icon = MarkerIconHelper.iconForListTypes([.favorites, .bucketList], cache: &cache)
        #expect(icon != nil)
        #expect(cache["favorites"] != nil)
    }

    @Test func allThreeListTypesUsesStarredPrecedence() {
        var cache: [String: UIImage] = [:]
        let icon = MarkerIconHelper.iconForListTypes([.bucketList, .starred, .favorites], cache: &cache)
        #expect(icon != nil)
        #expect(cache["starred"] != nil)
    }

    @Test func favoritesOnlyCachesFavorites() {
        var cache: [String: UIImage] = [:]
        _ = MarkerIconHelper.iconForListTypes([.favorites], cache: &cache)
        #expect(cache["favorites"] != nil)
    }

    @Test func bucketListOnlyCachesBucketList() {
        var cache: [String: UIImage] = [:]
        _ = MarkerIconHelper.iconForListTypes([.bucketList], cache: &cache)
        #expect(cache["bucketList"] != nil)
    }
}
