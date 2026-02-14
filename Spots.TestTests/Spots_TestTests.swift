//
//  Spots_TestTests.swift
//  Spots.TestTests
//
//  Created by Hussain Alam on 12/29/25.
//

import Testing
@testable import Spots_Test

struct Spots_TestTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
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
