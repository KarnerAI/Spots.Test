//
//  AllListsView.swift
//  Spots.Test
//
//  T21: Custom Lists CRUD — "View all" destination.
//
//  Lands when Maya taps "View all" on the Profile Lists section. Before T21
//  this link was broken (no destination). Now it shows a vertical list of all
//  her lists, defaults first (Favorites / Liked / Want to go), then a
//  "YOUR LISTS" section header, then her custom lists in created-order.
//
//  Per ordering decision in design-shotgun on 2026-05-25: defaults always
//  appear at the top — they're auto-created and Maya doesn't think of them
//  as "her" lists in the same way as Mexico City 2026.
//
//  Each row shows: cover (emoji or photo from auto-cover), name, spot count
//  + visibility label, ⋯ menu (opens ListSettingsSheet). Nav bar has back
//  button + "Lists" title + "+" to open CreateListView.
//
//  Figma mockups: https://www.figma.com/design/yrvGkmBbzeHzd00wK3hLFJ
//  Section 5A.
//

import SwiftUI

struct AllListsView: View {
    @EnvironmentObject private var locationSavingVM: LocationSavingViewModel

    @State private var showingCreate = false
    @State private var settingsTargetList: UserList? = nil
    @State private var tileSummaries: [UUID: LocationSavingService.ListTileSummary] = [:]

    /// Default lists are pinned to the top in canonical order: Favorites → Liked → Want to go.
    private static let defaultOrder: [ListKind] = [.favorites, .liked, .wantToGo]

    private var defaultLists: [UserList] {
        Self.defaultOrder.compactMap { kind in
            locationSavingVM.userLists.first(where: { $0.kind == kind })
        }
    }

    private var customLists: [UserList] {
        locationSavingVM.userLists
            .filter { !$0.kind.isSystemKind }
            .sorted { lhs, rhs in
                let lDate = lhs.createdAt ?? Date.distantPast
                let rDate = rhs.createdAt ?? Date.distantPast
                return lDate > rDate
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(defaultLists) { list in
                    listRow(list)
                }

                if !customLists.isEmpty {
                    sectionHeader("Your lists")
                    ForEach(customLists) { list in
                        listRow(list)
                    }
                } else {
                    emptyCustomLists
                }
            }
        }
        .background(Color.white)
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.spotsAccent)
                }
                .accessibilityLabel("New list")
            }
        }
        .task {
            await refreshIfStale()
        }
        .refreshable {
            await locationSavingVM.loadUserLists(forceRefresh: true)
            await refreshTileSummaries()
        }
        .sheet(isPresented: $showingCreate) {
            CreateListView { _ in
                Task { await refreshTileSummaries() }
            }
            .environmentObject(locationSavingVM)
        }
        .sheet(item: $settingsTargetList) { list in
            ListSettingsSheet(
                list: list,
                onDeleted: {
                    settingsTargetList = nil
                    Task { await refreshTileSummaries() }
                },
                onUpdated: { _ in
                    Task { await refreshTileSummaries() }
                }
            )
            .environmentObject(locationSavingVM)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.geist(size: 11, weight: .medium))
            .tracking(0.8)
            .foregroundStyle(Color.spotsTextMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 8)
    }

    private var emptyCustomLists: some View {
        VStack(spacing: 8) {
            sectionHeader("Your lists")
            VStack(spacing: 6) {
                Text("No custom lists yet")
                    .font(.geist(size: 15, weight: .semibold))
                    .foregroundStyle(Color.spotsText)
                Text("Group your saves into lists like “Tacos in Brooklyn” or “Mexico City 2026.”")
                    .font(.geist(size: 13))
                    .foregroundStyle(Color.spotsTextMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button {
                    showingCreate = true
                } label: {
                    Text("Create your first list")
                        .font(.geist(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.spotsAccent)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Row
    //
    // Per QA feedback (2026-05-25): drop photo covers in row thumbnails — they
    // make the list-of-lists feel busy. Use the list's coverEmoji (or a per-kind
    // default for system lists) on the soft-blue tile so this screen reads as
    // a clean directory, not a photo gallery. The photo cover still appears on
    // the Profile carousel + List Detail header where the surface is bigger.

    private func listRow(_ list: UserList) -> some View {
        NavigationLink {
            destinationView(for: list)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                emojiThumbnail(for: list)

                VStack(alignment: .leading, spacing: 2) {
                    Text(list.displayName)
                        .font(.geist(size: 15, weight: .medium))
                        .foregroundStyle(Color.spotsText)
                        .lineLimit(1)
                    Text(metaLabel(for: list))
                        .font(.geist(size: 12))
                        .foregroundStyle(Color.spotsTextMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)

                Button {
                    settingsTargetList = list
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.spotsTextMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings for \(list.displayName)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.spotsBorder)
                    .frame(height: 1)
                    .padding(.leading, 76)
            }
        }
        .buttonStyle(.plain)
    }

    /// Route a row tap to ListDetailView. System kinds pass the resolved
    /// UserList via `.singleList`; this matches how Profile's destinationView
    /// builds the same screen.
    @ViewBuilder
    private func destinationView(for list: UserList) -> some View {
        ListDetailView(title: list.displayName, mode: .singleList(list))
            .environmentObject(locationSavingVM)
    }

    /// Emoji-only thumbnail. Uses list.coverEmoji if set; otherwise a sane
    /// per-kind default (❤️ Favorites, 👍 Liked, 🚩 Want to go, 📋 custom).
    private func emojiThumbnail(for list: UserList) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.spotsAccentSoft)
                .frame(width: 48, height: 48)
            Text(list.coverEmoji ?? defaultEmoji(for: list.kind))
                .font(.system(size: 24))
        }
    }

    private func defaultEmoji(for kind: ListKind) -> String {
        switch kind {
        case .favorites: return "❤️"
        case .liked: return "👍"
        case .wantToGo: return "🚩"
        case .custom: return "📋"
        case .trip: return "✈️"
        case .datePlan: return "📅"
        }
    }

    private func metaLabel(for list: UserList) -> String {
        let count = tileSummaries[list.id]?.spotCount ?? 0
        let countText = count == 1 ? "1 spot" : "\(count) spots"
        return "\(countText) · \(list.visibility.displayName)"
    }

    // MARK: - Data refresh

    /// Loads userLists if stale, then loads tile summaries for cover + count.
    private func refreshIfStale() async {
        await locationSavingVM.loadUserLists()
        await refreshTileSummaries()
    }

    private func refreshTileSummaries() async {
        let ids = locationSavingVM.userLists.map { $0.id }
        guard !ids.isEmpty else {
            tileSummaries = [:]
            return
        }
        do {
            let summaries = try await LocationSavingService.shared.getListTileSummaries(listIds: ids)
            var map: [UUID: LocationSavingService.ListTileSummary] = [:]
            for s in summaries { map[s.listId] = s }
            tileSummaries = map
        } catch {
            // Non-fatal — UI falls back to emoji-only thumbnails and zero counts.
            print("AllListsView: getListTileSummaries failed: \(error)")
        }
    }
}

// MARK: - Preview

#Preview("AllListsView — populated") {
    let vm = LocationSavingViewModel()
    vm.userLists = [
        UserList(id: UUID(), userId: UUID(), kind: .favorites, name: nil, visibility: .private, coverEmoji: "❤️"),
        UserList(id: UUID(), userId: UUID(), kind: .liked, name: nil, visibility: .private, coverEmoji: "👍"),
        UserList(id: UUID(), userId: UUID(), kind: .wantToGo, name: nil, visibility: .private, coverEmoji: "🚩"),
        UserList(id: UUID(), userId: UUID(), kind: .custom, name: "Mexico City 2026", visibility: .shared, coverEmoji: "🌮"),
        UserList(id: UUID(), userId: UUID(), kind: .custom, name: "Pizza in NYC", visibility: .public, coverEmoji: "🍕"),
        UserList(id: UUID(), userId: UUID(), kind: .custom, name: "Coffee crawl", visibility: .private, coverEmoji: "☕️")
    ]
    return NavigationStack {
        AllListsView()
            .environmentObject(vm)
    }
}

#Preview("AllListsView — defaults only (empty custom)") {
    let vm = LocationSavingViewModel()
    vm.userLists = [
        UserList(id: UUID(), userId: UUID(), kind: .favorites, name: nil, visibility: .private, coverEmoji: "❤️"),
        UserList(id: UUID(), userId: UUID(), kind: .liked, name: nil, visibility: .private, coverEmoji: "👍"),
        UserList(id: UUID(), userId: UUID(), kind: .wantToGo, name: nil, visibility: .private, coverEmoji: "🚩")
    ]
    return NavigationStack {
        AllListsView()
            .environmentObject(vm)
    }
}
