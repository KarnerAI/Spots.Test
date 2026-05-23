//
//  BackfillDebugView.swift
//  Spots.Test
//
//  Hidden debug screen to trigger PhotoBackfillService. Gated to DEBUG builds
//  so it never ships to TestFlight or App Store.
//
//  Wire-up:
//      #if DEBUG
//      NavigationLink("Backfill spot images", destination: BackfillDebugView())
//      #endif
//
//  IMPORTANT: First prod-data run MUST keep "Dry-run sweep" toggled ON. The
//  sweep deletes Supabase Storage objects whose URLs aren't referenced by any
//  spots row. A dry-run logs candidates without deleting; review the log,
//  then re-run with the toggle off.
//

#if DEBUG

import SwiftUI

struct BackfillDebugView: View {
    @State private var isRunning = false
    @State private var dryRunSweep = true
    @State private var limitText: String = "5"
    @State private var lastReport: PhotoBackfillService.BackfillReport?
    @State private var errorMessage: String?

    @StateObject private var localityBackfill = LocalityBackfillService.shared
    @State private var localityLimitText: String = ""

    var body: some View {
        Form {
            Section(header: Text("Photo backfill").font(.headline)) {
                Toggle("Dry-run sweep (recommended for first run)", isOn: $dryRunSweep)
                HStack {
                    Text("Limit (blank = all)")
                    Spacer()
                    TextField("e.g. 5", text: $limitText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                Button(action: triggerRun) {
                    HStack {
                        if isRunning { ProgressView().padding(.trailing, 6) }
                        Text(isRunning ? "Running..." : "Run backfill")
                    }
                }
                .disabled(isRunning)
            }

            if let error = errorMessage {
                Section(header: Text("Error")) {
                    Text(error).foregroundColor(.red)
                }
            }

            if let report = lastReport {
                Section(header: Text("Last run")) {
                    LabeledRow("Total", "\(report.total)")
                    LabeledRow("Succeeded", "\(report.succeeded)")
                    LabeledRow("Skipped (no ref)", "\(report.skippedNoReference)")
                    LabeledRow("Stale references", "\(report.staleReferences.count)")
                    LabeledRow("Failed uploads", "\(report.failedUploads.count)")
                    LabeledRow("Failed DB updates", "\(report.failedDBUpdates.count)")
                    if dryRunSweep {
                        LabeledRow("Sweep (dry-run)", "\(report.orphansFoundDryRun.count) candidates")
                    } else {
                        LabeledRow("Sweep deleted", "\(report.orphansDeleted)")
                    }
                }
            }

            // MARK: - Locality backfill
            //
            // Fixes the user-visible bug where saved spots showed
            // "Île-de-France" instead of "Paris" (region vs locality). Adds
            // the locality field to rows saved before the column existed.
            // Re-fetches via Google Places — one lookup per row — throttled
            // to ~5 QPS. Re-runnable: skips rows that already have locality.
            Section(header: Text("Locality backfill").font(.headline)) {
                HStack {
                    Text("Limit (blank = all)")
                    Spacer()
                    TextField("e.g. 50", text: $localityLimitText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                Button(action: triggerLocalityBackfill) {
                    HStack {
                        if localityBackfill.progress.isRunning {
                            ProgressView().padding(.trailing, 6)
                        }
                        Text(localityBackfill.progress.isRunning ? "Running..." : "Backfill locality")
                    }
                }
                .disabled(localityBackfill.progress.isRunning)

                let p = localityBackfill.progress
                if p.total > 0 || p.isRunning {
                    LabeledRow("Progress", "\(p.processed) / \(p.total)")
                    LabeledRow("Updated", "\(p.updated)")
                    LabeledRow("Skipped (no locality)", "\(p.skippedNoLocality)")
                    LabeledRow("Failures", "\(p.failures.count)")
                }
                if !p.failures.isEmpty {
                    DisclosureGroup("Failure details") {
                        ForEach(Array(p.failures.enumerated()), id: \.offset) { _, failure in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(failure.placeId).font(.caption.monospaced())
                                Text(failure.reason).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section(header: Text("Notes").font(.headline).foregroundColor(.secondary)) {
                Text("Keep this screen foregrounded for the duration. iOS suspends backgrounded apps after ~30s; an interrupted run is safe to resume — backfill is idempotent.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Backfill (debug)")
    }

    private func triggerLocalityBackfill() {
        let parsed = Int(localityLimitText.trimmingCharacters(in: .whitespaces))
        Task {
            await LocalityBackfillService.shared.run(limit: parsed)
        }
    }

    private func triggerRun() {
        isRunning = true
        errorMessage = nil
        let parsedLimit = Int(limitText.trimmingCharacters(in: .whitespaces))
        let dry = dryRunSweep
        Task {
            let report = await PhotoBackfillService.shared.run(
                limit: parsedLimit,
                dryRunSweep: dry
            )
            await MainActor.run {
                self.lastReport = report
                self.isRunning = false
            }
        }
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}

#endif
