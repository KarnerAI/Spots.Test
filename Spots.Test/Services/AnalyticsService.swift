//
//  AnalyticsService.swift
//  Spots.Test
//
//  Read-side client for save-velocity instrumentation (T1, Phase 1 Lane D).
//  Event emission is fully server-side via the `emit_save_event` trigger on
//  `spot_list_items` — there is no client write path. This service exposes
//  the rolling 7d aggregation view so callers can read median/p10/p90.
//

import Foundation
import Supabase

/// Rolling 7-day save-velocity snapshot. Mirrors the `saves_per_user_7d` view.
///
/// `median`, `p10`, and `p90` are nullable because `percentile_cont` returns
/// NULL when no users have saved in the last 7 days. Callers should treat
/// `nil` as "no data yet," not as zero.
struct SaveVelocitySnapshot: Codable, Equatable {
    let activeUsers: Int
    let median: Double?
    let p10: Double?
    let p90: Double?

    enum CodingKeys: String, CodingKey {
        case activeUsers = "active_users"
        case median
        case p10
        case p90
    }
}

/// Surface area used by future analytics callers. Extracted as a protocol so
/// the read path can be mocked in tests without standing up a Supabase client.
protocol AnalyticsServiceProtocol: AnyObject {
    func getSavesPerUser7d() async throws -> SaveVelocitySnapshot
}

final class AnalyticsService: AnalyticsServiceProtocol {
    static let shared = AnalyticsService()

    private let supabase = SupabaseManager.shared.client

    private init() {}

    func getSavesPerUser7d() async throws -> SaveVelocitySnapshot {
        try await supabase
            .from("saves_per_user_7d")
            .select()
            .single()
            .execute()
            .value
    }
}
