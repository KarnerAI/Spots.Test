//
//  AnalyticsServiceTests.swift
//  Spots.TestTests
//
//  Decode-shape tests for SaveVelocitySnapshot — the row returned by the
//  saves_per_user_7d view. The Supabase client is exercised by integration,
//  not unit tests; what the unit layer can guard is that the snake_case
//  column names + nullable percentile aggregates decode correctly. A
//  silent zero on decode failure would hide a regression in the Phase 2
//  readiness signal.
//

import Testing
import Foundation
@testable import Spots_Test

struct AnalyticsServiceTests {

    // MARK: - Happy path

    @Test func decodesPopulatedSnapshot() throws {
        let json = #"""
        {
          "active_users": 42,
          "median": 12.5,
          "p10": 2.0,
          "p90": 28.0
        }
        """#.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(SaveVelocitySnapshot.self, from: json)

        #expect(snapshot.activeUsers == 42)
        #expect(snapshot.median == 12.5)
        #expect(snapshot.p10 == 2.0)
        #expect(snapshot.p90 == 28.0)
    }

    // MARK: - Failure mode 1: empty window (percentile_cont returns NULL)

    @Test func decodesEmptyWindowWithNullAggregates() throws {
        // When no user has saved in the last 7 days, percentile_cont returns
        // NULL for median/p10/p90 while active_users is 0. The model must
        // represent this distinctly from "median is 0", which would falsely
        // signal the readiness bar is met at zero.
        let json = #"""
        {
          "active_users": 0,
          "median": null,
          "p10": null,
          "p90": null
        }
        """#.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(SaveVelocitySnapshot.self, from: json)

        #expect(snapshot.activeUsers == 0)
        #expect(snapshot.median == nil)
        #expect(snapshot.p10 == nil)
        #expect(snapshot.p90 == nil)
    }

    // MARK: - Failure mode 2: malformed payload

    @Test func malformedPayloadThrows() {
        // active_users is required and non-null. Missing it must throw, not
        // silently produce a zero snapshot.
        let json = #"""
        {
          "median": 5.0,
          "p10": 1.0,
          "p90": 9.0
        }
        """#.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SaveVelocitySnapshot.self, from: json)
        }
    }

    // MARK: - Mock conformance — guards the protocol shape

    @Test func mockConformsToProtocol() async throws {
        // Pins AnalyticsServiceProtocol so future callers can inject a mock.
        // If the protocol method signature changes, this fails to compile.
        let mock = MockAnalyticsService()
        mock.snapshotResult = SaveVelocitySnapshot(
            activeUsers: 7,
            median: 15.0,
            p10: 3.0,
            p90: 30.0
        )

        let snapshot = try await mock.getSavesPerUser7d()

        #expect(snapshot.activeUsers == 7)
        #expect(snapshot.median == 15.0)
    }
}

// MARK: - Mock

final class MockAnalyticsService: AnalyticsServiceProtocol, @unchecked Sendable {
    var snapshotResult: SaveVelocitySnapshot?
    var shouldThrow: Error?

    func getSavesPerUser7d() async throws -> SaveVelocitySnapshot {
        if let err = shouldThrow { throw err }
        guard let result = snapshotResult else {
            throw NSError(domain: "MockAnalyticsService", code: -1)
        }
        return result
    }
}
