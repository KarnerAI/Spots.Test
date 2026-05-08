//
//  PhotoBackfillService.swift
//  Spots.Test
//
//  One-shot backfill that re-fetches spot cover images at PhotoQuality.maxWidthPx
//  and rewrites them under VERSIONED filenames (`{placeId}_v{n}.jpg`) so client
//  and CDN caches actually invalidate. Without versioned URLs, overwriting the
//  same Supabase Storage path leaves CachedAsyncImage on every device serving
//  the old 400px bytes — backfill would silently appear to do nothing.
//
//  Pipeline per spot:
//
//      ┌──────────────────────────┐
//      │  spots.photo_reference?  │── nil ──> skip (logged)
//      └──────────┬───────────────┘
//                 │
//                 ▼
//      ┌──────────────────────────┐
//      │  Google fetch @ 1200px   │── 404 ──> stale-ref list (logged)
//      └──────────┬───────────────┘
//                 │
//                 ▼
//      ┌──────────────────────────┐
//      │  Upload {placeId}_v{n}   │── err ──> failed list (logged)
//      └──────────┬───────────────┘
//                 │
//                 ▼
//      ┌──────────────────────────┐
//      │  UPDATE spots.photo_url  │── err ──> orphan, swept later
//      └──────────────────────────┘
//
//  After the loop, `sweepOrphans()` lists every `_v*.jpg` in the bucket, diffs
//  against `spots.photo_url`, and deletes anything not referenced. **Sweep is
//  destructive** — first prod run MUST use `dryRun: true`.
//
//  Foreground constraint: runs in the main app process. iOS suspends the app
//  ~30 sec after backgrounding; backfill is interrupted but RE-RUNNABLE
//  (idempotent). Document: keep app foregrounded until the run completes.
//

import Foundation

actor PhotoBackfillService {
    static let shared = PhotoBackfillService()

    private let supabase = SupabaseManager.shared.client
    private let storage = ImageStorageService.shared

    /// Throttle: at most this many Google Place Photo requests per second.
    /// Google's New Places API quota is typically 600/min = 10/sec; staying
    /// at 5/sec leaves headroom for any other traffic the app makes.
    private let maxRequestsPerSecond: Double = 5.0

    // MARK: - DTOs

    /// Row shape we read from the spots table. `place_id` is the primary key
    /// (Google Place ID — see `create_location_saving_schema.sql`); there is
    /// no separate UUID `id` column.
    struct SpotRow: Codable {
        let place_id: String
        let photo_url: String?
        let photo_reference: String?
    }

    /// A spot that failed because Google returned 404 — likely a stale or
    /// rotated photo_reference. A follow-up pass can re-fetch Place Details
    /// for these to refresh `photo_reference`. Not part of this PR.
    struct StaleReference {
        let spotId: String
        let placeId: String
        let photoReference: String
    }

    /// Aggregate results for UI display + logging.
    struct BackfillReport {
        var total: Int = 0
        var succeeded: Int = 0
        var skippedNoReference: Int = 0
        var staleReferences: [StaleReference] = []
        var failedUploads: [String] = []      // spot ids
        var failedDBUpdates: [String] = []    // spot ids (orphan candidates)
        var orphansDeleted: Int = 0
        var orphansFoundDryRun: [String] = [] // populated only on dryRun
    }

    private init() {}

    // MARK: - Public API

    /// Runs the full backfill: per-spot rewrite + orphan sweep.
    /// - Parameters:
    ///   - limit: optional cap for testing. nil = all eligible spots.
    ///   - dryRunSweep: if true, sweep only logs candidates without deleting.
    ///                  **Always pass true for the first prod run.**
    /// - Returns: a structured report.
    func run(limit: Int? = nil, dryRunSweep: Bool = true) async -> BackfillReport {
        var report = BackfillReport()

        let spots = await fetchSpotsNeedingBackfill(limit: limit)
        report.total = spots.count
        print("📦 PhotoBackfillService: starting backfill, \(spots.count) spot(s) eligible")

        let intervalNanos = UInt64(1_000_000_000.0 / maxRequestsPerSecond)

        for spot in spots {
            let outcome = await backfillOne(spot: spot)
            switch outcome {
            case .succeeded:
                report.succeeded += 1
            case .skippedNoReference:
                report.skippedNoReference += 1
            case .staleReference(let stale):
                report.staleReferences.append(stale)
            case .failedUpload:
                report.failedUploads.append(spot.place_id)
            case .failedDBUpdate:
                report.failedDBUpdates.append(spot.place_id)
            }
            // Polite throttle — sleep once between iterations.
            try? await Task.sleep(nanoseconds: intervalNanos)
        }

        // Orphan sweep runs unconditionally — its job is to clean up debris
        // from THIS run's failed-DB-update cases AND from any prior partial run.
        let sweepResult = await sweepOrphans(dryRun: dryRunSweep)
        if dryRunSweep {
            report.orphansFoundDryRun = sweepResult
        } else {
            report.orphansDeleted = sweepResult.count
        }

        printSummary(report, dryRun: dryRunSweep)
        return report
    }

    /// User-facing upgrade entry point. Takes a caller-supplied list of spots
    /// (so the caller can scope to e.g. just the current user's saves) and
    /// runs the per-spot upgrade pipeline: fetch at 1200px, upload at a
    /// versioned filename, rewrite `spots.photo_url`. Throttled identically
    /// to `run(...)`.
    ///
    /// **Does NOT run `sweepOrphans()`.** Sweep is a global destructive op
    /// that touches storage objects across all users; it stays gated to
    /// `BackfillDebugView` (developer use only). If a per-spot UPDATE fails
    /// here, the orphaned object is recoverable via the dev-only sweep.
    ///
    /// Wired to `LocationSavingService.backfillMissingImages()` for the
    /// "Refresh Photos" button in Settings.
    func upgradeSpots(_ spots: [SpotRow]) async -> BackfillReport {
        var report = BackfillReport()
        report.total = spots.count

        guard !spots.isEmpty else { return report }

        let intervalNanos = UInt64(1_000_000_000.0 / maxRequestsPerSecond)

        for spot in spots {
            let outcome = await backfillOne(spot: spot)
            switch outcome {
            case .succeeded:
                report.succeeded += 1
            case .skippedNoReference:
                report.skippedNoReference += 1
            case .staleReference(let stale):
                report.staleReferences.append(stale)
            case .failedUpload:
                report.failedUploads.append(spot.place_id)
            case .failedDBUpdate:
                report.failedDBUpdates.append(spot.place_id)
            }
            try? await Task.sleep(nanoseconds: intervalNanos)
        }

        return report
    }

    /// Lists every `_v*.jpg` object in the bucket and deletes any whose public
    /// URL is not referenced by any `spots.photo_url`. **Destructive** when
    /// `dryRun == false`. Use `dryRun: true` for the first prod sweep.
    /// - Returns: filenames that were (or would be) deleted.
    func sweepOrphans(dryRun: Bool) async -> [String] {
        let allObjects = await storage.listAllObjects()

        // Only consider versioned objects; un-versioned `{placeId}.jpg` files
        // belong to fresh saves and must never be touched here.
        let versioned = allObjects.filter { isVersionedFilename($0) }
        guard !versioned.isEmpty else { return [] }

        // Build the set of every photo_url currently referenced by spots.
        let referencedURLs = await fetchAllReferencedPhotoURLs()
        let referencedFilenames = Set(referencedURLs.compactMap { extractFileName(from: $0) })

        let orphans = versioned.filter { !referencedFilenames.contains($0) }

        if dryRun {
            print("🔍 PhotoBackfillService: sweep dry-run found \(orphans.count) orphan(s):")
            orphans.forEach { print("   - \($0)") }
            return orphans
        }

        print("🧹 PhotoBackfillService: sweep deleting \(orphans.count) orphan(s)")
        var deleted: [String] = []
        for name in orphans {
            if await storage.deleteObject(fileName: name) {
                deleted.append(name)
            }
        }
        return deleted
    }

    // MARK: - Per-spot pipeline

    private enum SpotOutcome {
        case succeeded
        case skippedNoReference
        case staleReference(StaleReference)
        case failedUpload
        case failedDBUpdate
    }

    private func backfillOne(spot: SpotRow) async -> SpotOutcome {
        guard let photoReference = spot.photo_reference, !photoReference.isEmpty else {
            return .skippedNoReference
        }

        // Decide next version. Spots without any version go to v2; spots
        // already at _v{n} go to _v{n+1}. This keeps subsequent runs idempotent
        // — re-running won't smash existing v2 data, it'll move them to v3.
        let nextVersion = self.nextVersion(currentURL: spot.photo_url)
        let newFileName = storage.versionedStorageFileName(
            for: spot.place_id,
            version: nextVersion
        )

        // Fetch from Google at save resolution.
        let imageData: Data
        do {
            imageData = try await GooglePlacesPhotoFetcher.fetch(
                photoReference: photoReference,
                maxWidth: PhotoQuality.maxWidthPx
            )
        } catch GooglePlacesPhotoFetcher.FetchError.http(let status) where status == 404 {
            return .staleReference(StaleReference(
                spotId: spot.place_id,
                placeId: spot.place_id,
                photoReference: photoReference
            ))
        } catch {
            print("⚠️  PhotoBackfillService: Google fetch failed for \(spot.place_id): \(error)")
            return .failedUpload
        }

        // Upload at the versioned filename.
        guard let newURL = await storage.uploadToSupabase(imageData: imageData, fileName: newFileName) else {
            return .failedUpload
        }

        // Update the DB row to point at the new URL. If this fails, the storage
        // object is orphaned — sweepOrphans() at end of run cleans it up.
        do {
            try await supabase
                .from("spots")
                .update(["photo_url": newURL])
                .eq("place_id", value: spot.place_id)
                .execute()
            return .succeeded
        } catch {
            print("⚠️  PhotoBackfillService: DB update failed for \(spot.place_id): \(error)")
            return .failedDBUpdate
        }
    }

    // MARK: - Filename version logic — kept synchronous + non-isolated for tests.

    /// Pure logic for backfill filename versioning. No async, no actor — easy
    /// to unit-test without spinning up Supabase.
    enum VersioningLogic {
        /// Parses the current photo_url and returns the next version number. URLs
        /// without a `_v{n}.jpg` suffix go to v2 (v1 is implicit = the original
        /// un-versioned upload). URLs already at `_v{n}` go to `v{n+1}`.
        static func nextVersion(currentURL: String?) -> Int {
            guard let url = currentURL,
                  let fileName = extractFileName(from: url) else {
                return 2
            }
            if let n = parseVersionSuffix(fileName: fileName) {
                return n + 1
            }
            return 2
        }

        /// Returns true if the filename matches the versioned pattern
        /// `{placeId}_v{digits}.jpg` (case-insensitive on extension).
        static func isVersionedFilename(_ fileName: String) -> Bool {
            return parseVersionSuffix(fileName: fileName) != nil
        }

        /// Extracts the trailing `_v{digits}` integer from a filename, or nil.
        static func parseVersionSuffix(fileName: String) -> Int? {
            let stem = fileName.replacingOccurrences(
                of: ".jpg", with: "",
                options: [.caseInsensitive, .anchored, .backwards]
            )
            guard let underscoreV = stem.range(of: "_v", options: .backwards) else { return nil }
            let numberPart = stem[underscoreV.upperBound...]
            guard !numberPart.isEmpty, numberPart.allSatisfy({ $0.isNumber }) else { return nil }
            return Int(numberPart)
        }

        /// Returns the trailing path component of a Supabase Storage public URL,
        /// e.g. ".../spot-images/foo_v2.jpg" → "foo_v2.jpg". Returns nil on parse failure.
        static func extractFileName(from urlString: String) -> String? {
            guard let url = URL(string: urlString) else { return nil }
            let last = url.lastPathComponent
            return last.isEmpty ? nil : last
        }
    }

    // Convenience forwarders so the rest of the actor reads naturally.
    func nextVersion(currentURL: String?) -> Int { VersioningLogic.nextVersion(currentURL: currentURL) }
    func isVersionedFilename(_ fileName: String) -> Bool { VersioningLogic.isVersionedFilename(fileName) }
    func extractFileName(from urlString: String) -> String? { VersioningLogic.extractFileName(from: urlString) }

    // MARK: - Supabase queries

    private func fetchSpotsNeedingBackfill(limit: Int?) async -> [SpotRow] {
        do {
            // Fetch all spots; we filter rows lacking a photo_reference at the
            // per-spot stage (`skippedNoReference`). Doing the null-filter
            // client-side avoids tangling with the Supabase Swift `Operator`
            // enum's reserved-word `is` case.
            let baseQuery = supabase
                .from("spots")
                .select("place_id, photo_url, photo_reference")
            if let limit = limit {
                let rows: [SpotRow] = try await baseQuery.limit(limit).execute().value
                return rows
            } else {
                let rows: [SpotRow] = try await baseQuery.execute().value
                return rows
            }
        } catch {
            print("❌ PhotoBackfillService: failed to query spots: \(error)")
            return []
        }
    }

    private func fetchAllReferencedPhotoURLs() async -> [String] {
        struct URLRow: Codable {
            let photo_url: String?
        }
        do {
            let rows: [URLRow] = try await supabase
                .from("spots")
                .select("photo_url")
                .execute()
                .value
            return rows.compactMap { $0.photo_url }
        } catch {
            print("❌ PhotoBackfillService: failed to fetch photo_urls: \(error)")
            return []
        }
    }

    // MARK: - Reporting

    private func printSummary(_ r: BackfillReport, dryRun: Bool) {
        print("""
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        📦 PhotoBackfillService report
           total            : \(r.total)
           succeeded        : \(r.succeeded)
           skipped (no ref) : \(r.skippedNoReference)
           stale references: \(r.staleReferences.count)
           failed uploads   : \(r.failedUploads.count)
           failed DB updates: \(r.failedDBUpdates.count)   (orphan candidates)
           orphans \(dryRun ? "(dry run)" : "deleted   "): \(dryRun ? r.orphansFoundDryRun.count : r.orphansDeleted)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        """)
        if !r.staleReferences.isEmpty {
            print("ℹ️  Stale references (need Place Details refresh — out of scope for this PR):")
            r.staleReferences.forEach {
                print("   - spot=\($0.spotId) place=\($0.placeId)")
            }
        }
    }
}
