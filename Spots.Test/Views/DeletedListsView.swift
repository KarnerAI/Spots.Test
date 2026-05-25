//
//  DeletedListsView.swift
//  Spots.Test
//
//  T21 QA round 3 follow-up: the recovery surface for soft-deleted lists.
//
//  Reached from Settings → "Recently deleted lists" (the destination the
//  delete-confirmation copy promises: "You can recover this list for 30
//  days from Settings."). Pre-this-view that copy was an empty promise
//  because no recovery UI existed.
//
//  Data flow:
//    list_deleted_lists RPC → LocationSavingService.getDeletedLists()
//      → LocationSavingViewModel.getDeletedLists()
//      → DeletedListsView (here)
//
//    Restore: tap Restore → restore_list RPC (owner + within-30-days only)
//      → LocationSavingViewModel.restoreList() reinserts into userLists
//      → row disappears from this screen + reappears in Profile carousel.
//
//  Past the 30-day window the RPC rejects with a typed error (the row gets
//  hard-deleted by the nightly purge cron). Surfaced inline as "No longer
//  recoverable" with the Restore button disabled.
//

import SwiftUI

struct DeletedListsView: View {
    @EnvironmentObject private var locationSavingVM: LocationSavingViewModel

    @State private var deletedLists: [DeletedListSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var restoringIds: Set<UUID> = []

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                errorState(errorMessage)
            } else if deletedLists.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .background(Color(red: 0.95, green: 0.95, blue: 0.97))
        .navigationTitle("Recently deleted")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDeletedLists() }
        .refreshable { await loadDeletedLists() }
    }

    // MARK: - States

    private var listContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                infoCallout
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                VStack(spacing: 0) {
                    ForEach(deletedLists) { summary in
                        row(for: summary)
                        if summary.id != deletedLists.last?.id {
                            Divider()
                                .background(Color.spotsBorderSoft)
                                .padding(.leading, 76)
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.spotsTextSubtle)
            Text("No recently deleted lists")
                .font(.geist(size: 17, weight: .semibold))
                .foregroundStyle(Color.spotsText)
            Text("Lists you delete will appear here for 30 days, then be permanently removed.")
                .font(.geist(size: 13))
                .foregroundStyle(Color.spotsTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(Color.spotsError)
            Text("Couldn't load")
                .font(.geist(size: 17, weight: .semibold))
                .foregroundStyle(Color.spotsText)
            Text(message)
                .font(.geist(size: 13))
                .foregroundStyle(Color.spotsTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Try again") {
                Task { await loadDeletedLists() }
            }
            .font(.geist(size: 14, weight: .semibold))
            .foregroundStyle(Color.spotsAccent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var infoCallout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.spotsAccent)
                .padding(.top, 1)
            Text("Lists are kept here for 30 days after deletion. Their spots stay saved to your other lists in the meantime.")
                .font(.geist(size: 13))
                .foregroundStyle(Color.spotsText)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.spotsAccentSoft)
        )
    }

    // MARK: - Row

    private func row(for summary: DeletedListSummary) -> some View {
        HStack(alignment: .center, spacing: 12) {
            thumbnail(for: summary)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.name ?? "Untitled list")
                    .font(.geist(size: 15, weight: .medium))
                    .foregroundStyle(Color.spotsText)
                    .lineLimit(1)
                Text(daysRemainingLabel(for: summary))
                    .font(.geist(size: 12))
                    .foregroundStyle(remainingColor(for: summary))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            restoreButton(for: summary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func thumbnail(for summary: DeletedListSummary) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.spotsAccentSoft)
                .frame(width: 44, height: 44)
            if let emoji = summary.coverEmoji {
                Text(emoji).font(.system(size: 22))
            } else {
                // Kind-default fallback. Kind comes as raw string from the RPC
                // so map by string here to avoid a Swift enum coupling.
                Image(systemName: defaultIconName(for: summary.kind))
                    .font(.system(size: 18))
                    .foregroundStyle(Color.spotsAccent)
            }
        }
    }

    @ViewBuilder
    private func restoreButton(for summary: DeletedListSummary) -> some View {
        let isRestoring = restoringIds.contains(summary.id)
        let expired = summary.daysRemaining <= 0

        if isRestoring {
            ProgressView().controlSize(.small)
        } else if expired {
            Text("Expired")
                .font(.geist(size: 13, weight: .medium))
                .foregroundStyle(Color.spotsTextSubtle)
        } else {
            Button {
                Task { await restore(summary) }
            } label: {
                Text("Restore")
                    .font(.geist(size: 13, weight: .semibold))
                    .foregroundStyle(Color.spotsAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(Color.spotsAccentSoft)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Restore \(summary.name ?? "list")")
        }
    }

    // MARK: - Display helpers

    private func daysRemainingLabel(for summary: DeletedListSummary) -> String {
        let n = summary.daysRemaining
        if n <= 0 { return "No longer recoverable" }
        if n == 1 { return "1 day left to restore" }
        return "\(n) days left to restore"
    }

    private func remainingColor(for summary: DeletedListSummary) -> Color {
        if summary.daysRemaining <= 0 { return Color.spotsTextSubtle }
        if summary.daysRemaining <= 3 { return Color.spotsError }
        return Color.spotsTextMuted
    }

    private func defaultIconName(for kind: String) -> String {
        switch kind {
        case "favorites": return "heart.fill"
        case "liked": return "hand.thumbsup.fill"
        case "want_to_go": return "flag.fill"
        case "trip": return "airplane"
        case "date_plan": return "calendar"
        default: return "list.bullet"
        }
    }

    // MARK: - Actions

    private func loadDeletedLists() async {
        isLoading = true
        errorMessage = nil
        do {
            let fresh = try await locationSavingVM.getDeletedLists()
            deletedLists = fresh
        } catch {
            errorMessage = "Couldn't load recently deleted lists. Check your connection."
        }
        isLoading = false
    }

    private func restore(_ summary: DeletedListSummary) async {
        restoringIds.insert(summary.id)
        defer { restoringIds.remove(summary.id) }
        do {
            _ = try await locationSavingVM.restoreList(id: summary.id)
            // Remove the restored row optimistically so it disappears
            // immediately without waiting for a refetch.
            deletedLists.removeAll { $0.id == summary.id }
        } catch {
            errorMessage = "Couldn't restore \"\(summary.name ?? "list")\". It may already have been permanently deleted."
        }
    }
}

// MARK: - Preview

#Preview("Populated") {
    let vm = LocationSavingViewModel()
    return NavigationStack {
        DeletedListsView()
            .environmentObject(vm)
    }
}

#Preview("Empty") {
    let vm = LocationSavingViewModel()
    return NavigationStack {
        DeletedListsView()
            .environmentObject(vm)
    }
}
