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

    @Test func starredDisplaysAsFavorites() {
        // Iteration 2: .favorites enum case is the elite love tier.
        #expect(ListKind.favorites.displayName == "Favorites")
    }

    @Test func favoritesDisplaysAsLiked() {
        // Iteration 2: .liked enum case is the mid love tier.
        #expect(ListKind.liked.displayName == "Liked")
    }

    @Test func bucketListDisplaysAsWantToGo() {
        #expect(ListKind.wantToGo.displayName == "Want to Go")
    }
}

// MARK: - Display List Type Resolver Tests

struct DisplayListTypeResolverTests {
    
    @Test func emptySetReturnsNil() {
        let result = displayKind(for: [])
        #expect(result == nil)
    }
    
    @Test func starredOnlyReturnsStarred() {
        let result = displayKind(for: [.favorites])
        #expect(result == .favorites)
    }
    
    @Test func favoritesOnlyReturnsFavorites() {
        let result = displayKind(for: [.liked])
        #expect(result == .liked)
    }
    
    @Test func bucketListOnlyReturnsBucketList() {
        let result = displayKind(for: [.wantToGo])
        #expect(result == .wantToGo)
    }
    
    @Test func starredAndFavoritesReturnsStarred() {
        // Starred has higher priority than Favorites
        let result = displayKind(for: [.favorites, .liked])
        #expect(result == .favorites)
    }
    
    @Test func bucketListAndStarredReturnsBucketList() {
        // BucketList has highest priority
        let result = displayKind(for: [.wantToGo, .favorites])
        #expect(result == .wantToGo)
    }
    
    @Test func bucketListAndFavoritesReturnsBucketList() {
        // BucketList has highest priority
        let result = displayKind(for: [.wantToGo, .liked])
        #expect(result == .wantToGo)
    }
    
    @Test func allThreeReturnsBucketList() {
        // BucketList has highest priority even when all are present
        let result = displayKind(for: [.wantToGo, .favorites, .liked])
        #expect(result == .wantToGo)
    }
}

// MARK: - Marker Icon Helper Tests (All Spots map custom markers)

struct MarkerIconHelperTests {

    /// Empty list types → default teal pin (non-nil).
    @Test func emptyListTypesReturnsDefaultIcon() {
        var cache: [String: UIImage] = [:]
        let icon = MarkerIconHelper.iconForListKinds([], cache: &cache)
        #expect(icon != nil)
        #expect(cache.isEmpty)
    }

    /// Single list type returns custom icon and caches it.
    @Test func singleListTypeReturnsCustomIcon() {
        var cache: [String: UIImage] = [:]
        let icon = MarkerIconHelper.iconForListKinds([.favorites], cache: &cache)
        #expect(icon != nil)
        #expect(cache["starred"] != nil)
    }

    /// Precedence: starred > favorites > bucketList (multi-list uses starred).
    @Test func precedenceStarredOverFavorites() {
        var cache: [String: UIImage] = [:]
        let icon = MarkerIconHelper.iconForListKinds([.favorites, .liked], cache: &cache)
        #expect(icon != nil)
        #expect(cache["starred"] != nil)
    }

    @Test func precedenceFavoritesOverBucketList() {
        var cache: [String: UIImage] = [:]
        let icon = MarkerIconHelper.iconForListKinds([.liked, .wantToGo], cache: &cache)
        #expect(icon != nil)
        #expect(cache["favorites"] != nil)
    }

    @Test func allThreeListTypesUsesStarredPrecedence() {
        var cache: [String: UIImage] = [:]
        let icon = MarkerIconHelper.iconForListKinds([.wantToGo, .favorites, .liked], cache: &cache)
        #expect(icon != nil)
        #expect(cache["starred"] != nil)
    }

    @Test func favoritesOnlyCachesFavorites() {
        var cache: [String: UIImage] = [:]
        _ = MarkerIconHelper.iconForListKinds([.liked], cache: &cache)
        #expect(cache["favorites"] != nil)
    }

    @Test func bucketListOnlyCachesBucketList() {
        var cache: [String: UIImage] = [:]
        _ = MarkerIconHelper.iconForListKinds([.wantToGo], cache: &cache)
        #expect(cache["bucketList"] != nil)
    }
}
