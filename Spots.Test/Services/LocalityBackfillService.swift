//
//  LocalityBackfillService.swift
//  Spots.Test
//
//  One-shot backfill for spots.locality. Reads every spot with NULL locality,
//  re-fetches it from Google Places, and writes the locality value back.
//
//  Design:
//  - Throttled: ~200ms between Places lookups so we stay well under Google's
//    rate limits even if the row count grows.
//  - Resumable: the SELECT filter (locality IS NULL) is the progress marker.
//    Re-running picks up where it left off; no separate progress table.
//  - Observable: the @MainActor `Progress` struct is published so the debug
//    UI can render live counts and a per-row error list.
//
//  Triggered from BackfillDebugView. DEBUG-only screen; never ships to users.
//

import Foundation
import Supabase

@MainActor
final class LocalityBackfillService: ObservableObject {
    static let shared = LocalityBackfillService()

    struct Progress {
        var total: Int = 0
        var processed: Int = 0
        var updated: Int = 0
        var skippedNoLocality: Int = 0
        var failures: [(placeId: String, reason: String)] = []
        var isRunning: Bool = false
    }

    @Published private(set) var progress = Progress()

    /// Delay between Places lookups. 200ms gives us ~5 QPS — two orders of
    /// magnitude below Google's documented limit but enough headroom for
    /// transient network jitter without a retry loop.
    private let interRequestDelayNanos: UInt64 = 200_000_000

    private init() {}

    /// Run the backfill. Optional `limit` caps the run for a smoke test;
    /// nil processes all rows with NULL locality.
    func run(limit: Int? = nil) async {
        guard !progress.isRunning else { return }
        progress = Progress()
        progress.isRunning = true
        defer { progress.isRunning = false }

        let supabase = SupabaseManager.shared.client

        struct PendingRow: Decodable {
            let place_id: String
        }

        let pending: [PendingRow]
        do {
            var query = supabase
                .from("spots")
                .select("place_id")
                .is("locality", value: nil)
            if let limit {
                pending = try await query.limit(limit).execute().value
            } else {
                pending = try await query.execute().value
            }
        } catch {
            progress.failures.append((placeId: "<select>", reason: error.localizedDescription))
            return
        }

        progress.total = pending.count

        for row in pending {
            progress.processed += 1
            do {
                // forceNetworkFetch is critical here: most pre-backfill rows
                // already have photo/city/country/rating populated, which
                // means `fetchPlaceDetails` would short-circuit on the DB
                // cache and return a NearbySpot with `locality = nil`. We'd
                // then count every row as "skipped no locality" without ever
                // asking Google. See PlacesAPIService.fetchPlaceDetails docs.
                guard let details = try await PlacesAPIService.shared.fetchPlaceDetails(
                    placeId: row.place_id,
                    forceNetworkFetch: true
                ) else {
                    progress.skippedNoLocality += 1
                    continue
                }
                guard let locality = details.locality, !locality.isEmpty else {
                    // Google didn't return a locality for this place. Common for
                    // remote attractions (national parks, lone landmarks) that
                    // don't sit inside a named city.
                    progress.skippedNoLocality += 1
                    continue
                }
                try await supabase
                    .from("spots")
                    .update(["locality": locality])
                    .eq("place_id", value: row.place_id)
                    .execute()
                progress.updated += 1
            } catch {
                progress.failures.append((placeId: row.place_id, reason: error.localizedDescription))
            }

            // Throttle. Skip on the final iteration to avoid a needless sleep.
            if progress.processed < progress.total {
                try? await Task.sleep(nanoseconds: interRequestDelayNanos)
            }
        }
    }
}
