//
//  CreateListView.swift
//  Spots.Test
//
//  T21: Custom Lists CRUD — Create flow.
//
//  Modal form Maya sees when she taps "+ New list" anywhere (Profile carousel
//  tile, List Picker top-right pill, All Lists nav "+"). Captures: name
//  (required, ≤50 chars), emoji cover, and visibility (Private/Shared/Public,
//  default Private).
//
//  Cover model: Maya picks an emoji here. Once she saves the list and adds
//  the first spot, the server-side auto-cover RPC (T21.2) swaps the cover to
//  that spot's photo. The emoji remains the fallback when the list is empty
//  or when the most-recent spot has no photo. This is why the form is
//  emoji-only — no photo picker in v1.
//
//  Per DESIGN.md: Geist throughout, cool blue accent (#2563EB), sentence-case
//  labels, real photography (n/a here), no decorative chrome. Figma mockups:
//  https://www.figma.com/design/yrvGkmBbzeHzd00wK3hLFJ
//

import SwiftUI

struct CreateListView: View {
    /// Called with the freshly-created list when the user taps Save and the
    /// server returns success. The presenter dismisses + scrolls/selects it.
    let onCreated: (UserList) -> Void

    @EnvironmentObject private var locationSavingVM: LocationSavingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var coverEmoji: String? = nil
    @State private var visibility: ListVisibility = .private
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    /// Drives the EmojiKeyboardField — tapping the emoji tile or "Choose emoji"
    /// text flips this to true, which raises the iOS emoji keyboard. The
    /// coordinator flips it back to false after the user picks an emoji.
    @State private var emojiKeyboardFocused: Bool = false

    /// Curated 12-emoji starter grid. Covers the most common Maya use cases
    /// (food + drinks + culture + travel). v1 limitation — a full emoji picker
    /// is a P2 enhancement; for now Maya picks one of these or skips and lets
    /// the auto-cover from her first spot's photo take over.
    private let starterEmojis: [String] = [
        "🌮", "🍕", "☕️", "🍜", "🍣", "🍺",
        "🏛", "🏞", "🎨", "🛍", "📚", "🎵"
    ]

    private static let maxNameLength = LocationSavingService.maxListNameLength

    /// Save is enabled only when name is non-empty after trimming.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= Self.maxNameLength
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    nameField
                    coverSection
                    visibilitySection
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.geist(size: 13))
                            .foregroundStyle(Color.spotsError)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.white)
            .navigationTitle("New list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.geist(size: 15, weight: .medium))
                        .foregroundStyle(Color.spotsAccent)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                                .font(.geist(size: 15, weight: .semibold))
                                .foregroundStyle(canSave ? Color.spotsAccent : Color.spotsTextSubtle)
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Sections

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name this list", text: $name)
                .font(.geist(size: 17, weight: .medium))
                .foregroundStyle(Color.spotsText)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.spotsBorder, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .onChange(of: name) { _, newValue in
                    if newValue.count > Self.maxNameLength {
                        name = String(newValue.prefix(Self.maxNameLength))
                    }
                }

            HStack {
                Spacer()
                Text("\(name.count) / \(Self.maxNameLength)")
                    .font(.geistMono(size: 11))
                    .foregroundStyle(Color.spotsTextSubtle)
                    .padding(.trailing, 18)
            }
        }
    }

    private var coverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cover")
                .font(.geist(size: 11, weight: .medium))
                .foregroundStyle(Color.spotsTextMuted)
                .padding(.horizontal, 16)

            // Tile + CTA — tapping either opens an EmojiPickerSheet (rounded
            // top corners, drag handle), inside which the iOS emoji keyboard
            // rises. Matches the iMessage emoji-panel visual treatment. The
            // 12-emoji grid below stays as quick-tap shortcuts for common picks.
            Button {
                emojiKeyboardFocused = true
            } label: {
                HStack(spacing: 12) {
                    emojiTile

                    VStack(alignment: .leading, spacing: 4) {
                        Text(coverEmoji == nil ? "Choose emoji" : "Change emoji")
                            .font(.geist(size: 14, weight: .medium))
                            .foregroundStyle(Color.spotsAccent)
                        Text("Tap to open the emoji keyboard (search included).")
                            .font(.geist(size: 12))
                            .foregroundStyle(Color.spotsTextMuted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            // Auto-cover behavior hint
            HStack(alignment: .top, spacing: 8) {
                Text("Once you save a spot to this list, its photo becomes the list cover automatically.")
                    .font(.geist(size: 12))
                    .foregroundStyle(Color.spotsText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.spotsAccentSoft)
            )
            .padding(.horizontal, 16)

            // Quick-tap shortcuts.
            emojiGrid
                .padding(.top, 4)

            // Invisible UIKit bridge that receives the emoji-keyboard
            // selection. Off-screen at 1pt so it never takes layout space.
            // Tapping "Choose emoji" focuses this and the iOS emoji keyboard
            // rises directly (no extra sheet wrapper — QA round 3 feedback).
            EmojiKeyboardField(
                emoji: Binding(
                    get: { coverEmoji },
                    set: { if let new = $0 { coverEmoji = new } }
                ),
                isFocused: $emojiKeyboardFocused
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityHidden(true)
        }
    }

    private var emojiTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.spotsAccentSoft)
                .frame(width: 80, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.spotsBorder, lineWidth: 1)
                )

            if let coverEmoji {
                Text(coverEmoji)
                    .font(.system(size: 38))
            } else {
                Image(systemName: "face.smiling")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.spotsAccent.opacity(0.55))
            }
        }
        .accessibilityLabel(coverEmoji == nil ? "No emoji selected" : "Selected emoji \(coverEmoji ?? "")")
    }

    private var emojiGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6),
            spacing: 6
        ) {
            ForEach(starterEmojis, id: \.self) { emoji in
                Button {
                    if coverEmoji == emoji {
                        coverEmoji = nil
                    } else {
                        coverEmoji = emoji
                    }
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(coverEmoji == emoji ? Color.spotsAccentSoft : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(coverEmoji == emoji ? Color.spotsAccent : Color.clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose \(emoji) as cover")
                .accessibilityAddTraits(coverEmoji == emoji ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Who can see this list")
                .font(.geist(size: 11, weight: .medium))
                .foregroundStyle(Color.spotsTextMuted)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            ForEach(ListVisibility.allCases, id: \.self) { option in
                visibilityRow(option)
            }
        }
    }

    private func visibilityRow(_ option: ListVisibility) -> some View {
        Button {
            visibility = option
        } label: {
            HStack(alignment: .top, spacing: 12) {
                radio(isSelected: visibility == option)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .font(.geist(size: 14, weight: .medium))
                        .foregroundStyle(Color.spotsText)
                    Text(option.description)
                        .font(.geist(size: 13))
                        .foregroundStyle(Color.spotsTextMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            // Hairline divider between rows; skip after the last row
            if option != ListVisibility.allCases.last {
                Rectangle()
                    .fill(Color.spotsBorder)
                    .frame(height: 1)
                    .padding(.leading, 48)
                    .padding(.trailing, 16)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(visibility == option ? .isSelected : [])
    }

    private func radio(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Color.spotsAccent : Color.spotsBorderStrong, lineWidth: isSelected ? 6 : 1.5)
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(Color.white)
                )
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let created = try await locationSavingVM.createList(
                    name: trimmed,
                    visibility: visibility,
                    coverEmoji: coverEmoji
                )
                isSaving = false
                onCreated(created)
                dismiss()
            } catch {
                errorMessage = friendlyMessage(for: error)
                isSaving = false
            }
        }
    }

    /// Map server / validation errors to copy Maya can act on.
    private func friendlyMessage(for error: Error) -> String {
        if let custom = error as? CustomListError {
            return custom.localizedDescription
        }
        return "Couldn't save the list. Check your connection and try again."
    }
}

// Design tokens (Color.spots* + Font.geist*) live in Helpers/DesignTokens.swift
// since they're shared across CreateListView, ListSettingsSheet, AllListsView,
// and ListPickerView. Lifted in the eng-review round 2 polish pass.

// MARK: - Preview

#Preview("CreateListView (interactive)") {
    // The preview is interactive in the canvas — tap the Name field to type,
    // tap an emoji in the grid, tap visibility rows. Save lights up cool blue
    // once the name is non-empty.
    CreateListView { _ in }
        .environmentObject(LocationSavingViewModel())
}

#Preview("CreateListView in a sheet (presentation context)") {
    // Mimics the real entry point: presented as a sheet from a host screen.
    // Useful for checking the half-sheet detents + drag-to-dismiss feel.
    struct Host: View {
        @State private var presented = true
        var body: some View {
            Color.white.ignoresSafeArea()
                .sheet(isPresented: $presented) {
                    CreateListView { _ in presented = false }
                        .environmentObject(LocationSavingViewModel())
                }
        }
    }
    return Host()
}
