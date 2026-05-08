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

    var body: some View {
        Form {
            Section(header: Text("Run").font(.headline)) {
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

            Section(header: Text("Notes").font(.headline).foregroundColor(.secondary)) {
                Text("Keep this screen foregrounded for the duration. iOS suspends backgrounded apps after ~30s; an interrupted run is safe to resume — backfill is idempotent.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Photo backfill (debug)")
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
