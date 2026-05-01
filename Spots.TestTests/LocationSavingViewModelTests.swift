//
//  LocationSavingViewModelTests.swift
//  Spots.TestTests
//
//  Unit tests for LocationSavingViewModel.ListSaveDiff — the pure diff math
//  that powers saveSpotToLists. The full save flow can't be unit-tested
//  without injecting a service mock; the diff logic is the part with branches
//  worth covering, so we exercise it directly.
//

import Testing
import Foundation
@testable import Spots_Test

struct ListSaveDiffTests {

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    @Test func allAddFromEmptyOriginal() {
        let diff = LocationSavingViewModel.ListSaveDiff(selected: [a, b], original: [])
        #expect(diff.toAdd == [a, b])
        #expect(diff.toRemove.isEmpty)
    }

    @Test func allRemoveWhenSelectionCleared() {
        let diff = LocationSavingViewModel.ListSaveDiff(selected: [], original: [a, b])
        #expect(diff.toAdd.isEmpty)
        #expect(diff.toRemove == [a, b])
    }

    @Test func mixedAddAndRemove() {
        let diff = LocationSavingViewModel.ListSaveDiff(selected: [b, c], original: [a, b])
        #expect(diff.toAdd == [c])
        #expect(diff.toRemove == [a])
    }

    @Test func noOpWhenSelectionMatchesOriginal() {
        let diff = LocationSavingViewModel.ListSaveDiff(selected: [a, b], original: [a, b])
        #expect(diff.toAdd.isEmpty)
        #expect(diff.toRemove.isEmpty)
    }

    @Test func bothEmpty() {
        let diff = LocationSavingViewModel.ListSaveDiff(selected: [], original: [])
        #expect(diff.toAdd.isEmpty)
        #expect(diff.toRemove.isEmpty)
    }
}
