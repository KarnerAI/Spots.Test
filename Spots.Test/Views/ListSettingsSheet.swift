//
//  ListSettingsSheet.swift
//  Spots.Test
//
//  T21: Custom Lists CRUD — settings sheet.
//
//  Half-sheet that opens from the List Detail "⋯" menu. Rows: Rename, Change
//  cover, Set photo cover from spot, Visibility (3-state pill), Edit
//  description, Manage collaborators (stub for T4), Delete list (destructive).
//
//  Default lists (Favorites / Liked / Want to go) get a stripped-down version:
//  Rename is disabled, Delete is hidden, an explanatory note appears at the top.
//  RLS enforces these constraints server-side too, so the UI gates are belt-
//  and-suspenders rather than the only line of defense.
//
//  Delete shows an iron-clad confirmation modal with the "23 spots will stay
//  saved" copy so Maya knows deletion isn't catastrophic + the 30-day restore
//  window is mentioned.
//
//  Figma mockups: https://www.figma.com/design/yrvGkmBbzeHzd00wK3hLFJ
//  Section 4 in the board: custom · default · delete confirm.
//

import SwiftUI

struct ListSettingsSheet: View {
    let list: UserList
    /// Called when the list is deleted (soft-delete via RPC). Presenter pops
    /// the List Detail view since the underlying list is now tombstoned.
    var onDeleted: (() -> Void)? = nil
    /// Called when the list is renamed / has its cover/visibility changed.
    /// Presenter refreshes the affected screens (List Detail header, Profile
    /// carousel, All Lists row).
    var onUpdated: ((UserList) -> Void)? = nil

    @EnvironmentObject private var locationSavingVM: LocationSavingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingRename = false
    @State private var showingChangeEmoji = false
    @State private var showingEditDescription = false
    @State private var showingDeleteConfirm = false
    @State private var showingCollaboratorsPlaceholder = false
    @State private var pendingAction: PendingAction? = nil
    @State private var errorMessage: String? = nil

    private enum PendingAction: Equatable {
        case rename
        case visibility(ListVisibility)
        case coverEmoji(String?)
        case description
        case delete
    }

    private var isDefault: Bool { list.kind.isSystemKind }

    /// Preview line for the Edit description row. Shows a single-line preview
    /// of the current description, or "Add" if empty, so Maya knows whether
    /// tapping will create or edit.
    private var descriptionPreview: String {
        if let desc = list.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            return desc
        }
        return "Add"
    }

    private var spotCountText: String {
        // Without a fresh count we use the optimistic "N spots will stay saved"
        // copy in the delete modal. Real count comes from the tile-summaries RPC;
        // VM-side state isn't reliable here because the count can change between
        // open and tap. The modal copy stays generic in the empty case.
        "the spots in this list"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if isDefault {
                        defaultListNote
                    }
                    settingsRows
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.geist(size: 13))
                            .foregroundStyle(Color.spotsError)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.white)
            .navigationTitle("List settings")
            .navigationBarTitleDisplayMode(.inline)
            // X close button removed in QA round 3 — drag-down dismiss is
            // discoverable enough (drag indicator on the sheet handles this),
            // and removing the X cuts visual clutter from the title row.
            // Confirmation modal — destructive Delete
            .alert("Delete \"\(list.displayName)\"?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { performDelete() }
            } message: {
                Text("\(spotCountText.capitalized) will stay saved to your other lists. You can recover this list for 30 days from Settings.")
            }
            // Inline rename
            .sheet(isPresented: $showingRename) {
                RenameListSheet(currentName: list.name ?? list.displayName) { newName in
                    performRename(to: newName)
                }
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
            }
            // Inline emoji change
            .sheet(isPresented: $showingChangeEmoji) {
                ChangeCoverEmojiSheet(currentEmoji: list.coverEmoji) { newEmoji in
                    performSetCoverEmoji(newEmoji)
                }
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
            }
            // Edit description — passes an async throws save closure so the
            // sub-sheet can surface errors inline (e.g. missing description
            // column if the SQL migration hasn't been applied yet).
            .sheet(isPresented: $showingEditDescription) {
                EditDescriptionSheet(currentDescription: list.description) { newDescription in
                    let updated = try await locationSavingVM.setListDescription(
                        id: list.id,
                        description: newDescription
                    )
                    onUpdated?(updated)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            // Collaborators placeholder (T4 fills this in)
            .sheet(isPresented: $showingCollaboratorsPlaceholder) {
                CollaboratorsPlaceholderSheet()
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Sections

    private var defaultListNote: some View {
        Text("\(list.kind.displayName) is one of your default lists. You can customize its cover, but it can't be renamed or deleted.")
            .font(.geist(size: 12))
            .foregroundStyle(Color.spotsTextMuted)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
    }

    /// Row layout (QA round 3 reorder):
    ///   Identity:    Name, Description
    ///   Appearance:  Icon, Cover photo
    ///   Access:      Visibility, Collaborators
    ///   Destructive: Delete
    /// 8pt spacer between groups for visual rhythm without adding more
    /// divider lines (lighter than the previous "every row separated by a
    /// hairline" look — QA round 3 feedback).
    @ViewBuilder
    private var settingsRows: some View {
        // ── Identity ──────────────────────────────────────────────
        // Name — disabled on default lists (system kinds use their canonical
        // displayName like "Favorites", not user-editable).
        settingsRow(
            icon: "textformat",
            iconColor: Color.spotsTextMuted,
            title: "Name",
            metaText: isDefault ? "Default list" : list.displayName,
            disabled: isDefault,
            action: { showingRename = true }
        )

        // Description — custom lists only. Default lists use the hardcoded
        // copy from ListKind.defaultDescription.
        if !isDefault {
            settingsRow(
                icon: "text.alignleft",
                iconColor: Color.spotsTextMuted,
                title: "Description",
                metaText: descriptionPreview,
                action: { showingEditDescription = true }
            )
        }

        groupSpacer

        // ── Appearance ────────────────────────────────────────────
        // Icon — custom lists only. Default lists render their canonical
        // SF Symbol everywhere; no emoji to swap.
        if !isDefault {
            settingsRow(
                icon: "face.smiling",
                iconColor: Color.spotsTextMuted,
                title: "Icon",
                metaEmoji: list.coverEmoji,
                action: { showingChangeEmoji = true }
            )
        }

        // Cover photo — custom lists only. Placeholder action; T21.6 routes
        // to a spot-picker.
        if !isDefault {
            settingsRow(
                icon: "photo.on.rectangle.angled",
                iconColor: Color.spotsTextMuted,
                title: "Cover photo",
                metaText: list.coverImageUrl == nil ? "Auto" : "Manual",
                action: { /* P2 — spot-picker wiring */ }
            )
        }

        if !isDefault { groupSpacer }

        // ── Access ────────────────────────────────────────────────
        visibilityRow

        // Collaborators — visible always; stub for T4.
        settingsRow(
            icon: "person.2",
            iconColor: Color.spotsTextMuted,
            title: "Collaborators",
            metaText: "Coming soon",
            action: { showingCollaboratorsPlaceholder = true }
        )

        // ── Destructive ───────────────────────────────────────────
        if !isDefault {
            groupSpacer
            settingsRow(
                icon: "trash",
                iconColor: Color.spotsError,
                title: "Delete list",
                titleColor: Color.spotsError,
                action: { showingDeleteConfirm = true }
            )
        }
    }

    /// Small vertical gap between row groups. Replaces what would be a heavier
    /// divider with a 12pt breath — less visual noise per QA round 3.
    private var groupSpacer: some View {
        Color.clear.frame(height: 12)
    }

    /// Visibility row uses a two-row layout (label + subtext on row 1, full-width
    /// 3-segment pill on row 2) so the pill always has enough horizontal room
    /// to render its longest segment ("Private") without text wrapping.
    private var visibilityRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                iconCircle(systemName: "lock", color: Color.spotsTextMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Visibility")
                        .font(.geist(size: 14, weight: .medium))
                        .foregroundStyle(Color.spotsText)
                    Text(visibilitySubtext)
                        .font(.geist(size: 12))
                        .foregroundStyle(Color.spotsTextMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            visibilityPill
                .padding(.leading, 38) // align under the title (icon width + spacing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.spotsBorderSoft)
                .frame(height: 1)
                .padding(.leading, 48)
        }
    }

    private var visibilitySubtext: String {
        switch list.visibility {
        case .private: return "Private — only you can see this list"
        case .shared: return "Shared — you and people you invited"
        case .public: return "Public — anyone can find and follow"
        }
    }

    private var visibilityPill: some View {
        HStack(spacing: 2) {
            ForEach(ListVisibility.allCases, id: \.self) { option in
                visibilityPillSegment(option)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.spotsAccentSoft)
        )
    }

    private func visibilityPillSegment(_ option: ListVisibility) -> some View {
        Button {
            if option != list.visibility, pendingAction == nil {
                performSetVisibility(option)
            }
        } label: {
            Text(option.displayName)
                .font(.geist(size: 13, weight: list.visibility == option ? .semibold : .medium))
                .foregroundStyle(list.visibility == option ? Color.spotsText : Color.spotsTextMuted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(list.visibility == option ? Color.white : Color.clear)
                        .shadow(color: list.visibility == option ? Color.black.opacity(0.06) : Color.clear, radius: 1, y: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set visibility to \(option.displayName)")
        .accessibilityAddTraits(list.visibility == option ? .isSelected : [])
        .disabled(pendingAction != nil)
    }

    // MARK: - Generic row

    private func settingsRow(
        icon: String,
        iconColor: Color,
        title: String,
        titleColor: Color = Color.spotsText,
        metaText: String? = nil,
        metaEmoji: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: { if !disabled { action() } }) {
            HStack(alignment: .center, spacing: 14) {
                iconCircle(systemName: icon, color: iconColor)
                Text(title)
                    .font(.geist(size: 15, weight: .medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if let metaEmoji {
                    Text(metaEmoji)
                        .font(.system(size: 20))
                } else if let metaText {
                    Text(metaText)
                        .font(.geist(size: 13))
                        .foregroundStyle(Color.spotsTextMuted)
                        .lineLimit(1)
                }
                if !disabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.spotsTextSubtle)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled || pendingAction != nil)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.spotsBorderSoft)
                .frame(height: 1)
                .padding(.leading, 48)
        }
    }

    private func iconCircle(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
    }

    // MARK: - Actions

    private func performRename(to newName: String) {
        pendingAction = .rename
        errorMessage = nil
        Task { @MainActor in
            do {
                let updated = try await locationSavingVM.renameList(id: list.id, newName: newName)
                onUpdated?(updated)
                pendingAction = nil
                showingRename = false
            } catch {
                errorMessage = (error as? CustomListError)?.errorDescription
                    ?? "Couldn't rename. Try again."
                pendingAction = nil
            }
        }
    }

    private func performSetVisibility(_ newVisibility: ListVisibility) {
        pendingAction = .visibility(newVisibility)
        errorMessage = nil
        Task { @MainActor in
            do {
                let updated = try await locationSavingVM.setListVisibility(id: list.id, visibility: newVisibility)
                onUpdated?(updated)
                pendingAction = nil
            } catch {
                errorMessage = "Couldn't change visibility. Try again."
                pendingAction = nil
            }
        }
    }

    private func performSetCoverEmoji(_ newEmoji: String?) {
        pendingAction = .coverEmoji(newEmoji)
        errorMessage = nil
        Task { @MainActor in
            do {
                let updated = try await locationSavingVM.setListCoverEmoji(id: list.id, emoji: newEmoji)
                onUpdated?(updated)
                pendingAction = nil
                showingChangeEmoji = false
            } catch {
                errorMessage = "Couldn't change the emoji. Try again."
                pendingAction = nil
            }
        }
    }

    private func performDelete() {
        pendingAction = .delete
        errorMessage = nil
        Task { @MainActor in
            do {
                _ = try await locationSavingVM.deleteList(id: list.id)
                pendingAction = nil
                onDeleted?()
                dismiss()
            } catch {
                errorMessage = "Couldn't delete the list. Default lists can't be deleted; for custom lists, check your connection and try again."
                pendingAction = nil
            }
        }
    }
}

// MARK: - Rename sub-sheet

private struct RenameListSheet: View {
    let currentName: String
    let onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @FocusState private var focused: Bool

    init(currentName: String, onCommit: @escaping (String) -> Void) {
        self.currentName = currentName
        self.onCommit = onCommit
        self._draft = State(initialValue: currentName)
    }

    private static let maxLength = LocationSavingService.maxListNameLength

    private var canCommit: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != currentName && draft.count <= Self.maxLength
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Rename list")
                    .font(.geist(size: 13, weight: .medium))
                    .foregroundStyle(Color.spotsTextMuted)

                TextField("List name", text: $draft)
                    .font(.geist(size: 17, weight: .medium))
                    .foregroundStyle(Color.spotsText)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.spotsBorder, lineWidth: 1)
                    )
                    .onChange(of: draft) { _, newValue in
                        if newValue.count > Self.maxLength {
                            draft = String(newValue.prefix(Self.maxLength))
                        }
                    }
                    .submitLabel(.done)
                    .onSubmit {
                        if canCommit { commit() }
                    }

                HStack {
                    Spacer()
                    Text("\(draft.count) / \(Self.maxLength)")
                        .font(.geistMono(size: 11))
                        .foregroundStyle(Color.spotsTextSubtle)
                }
            }
            .padding(20)
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.spotsAccent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commit() }
                        .font(.geist(size: 15, weight: .semibold))
                        .foregroundStyle(canCommit ? Color.spotsAccent : Color.spotsTextSubtle)
                        .disabled(!canCommit)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
    }
}

// MARK: - Change-list-icon sub-sheet

private struct ChangeCoverEmojiSheet: View {
    let currentEmoji: String?
    let onCommit: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String?
    @State private var keyboardFocused: Bool = false

    init(currentEmoji: String?, onCommit: @escaping (String?) -> Void) {
        self.currentEmoji = currentEmoji
        self.onCommit = onCommit
        self._draft = State(initialValue: currentEmoji)
    }

    /// Same starter set as CreateListView. Keeping them in sync feels right —
    /// if Maya picked from this list at create, she finds the same options here.
    private let starterEmojis: [String] = [
        "🌮", "🍕", "☕️", "🍜", "🍣", "🍺",
        "🏛", "🏞", "🎨", "🛍", "📚", "🎵"
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                // Tile + CTA — single tap target raises the EmojiPickerSheet
                // (rounded-top sheet hosting the iOS emoji keyboard, matches
                // iMessage's visual treatment).
                Button {
                    keyboardFocused = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.spotsAccentSoft)
                                .frame(width: 64, height: 64)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.spotsBorder, lineWidth: 1)
                                )
                            if let draft {
                                Text(draft).font(.system(size: 30))
                            } else {
                                Image(systemName: "face.smiling")
                                    .font(.system(size: 24, weight: .light))
                                    .foregroundStyle(Color.spotsAccent.opacity(0.55))
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft == nil ? "Pick an emoji" : "Change emoji")
                                .font(.geist(size: 14, weight: .medium))
                                .foregroundStyle(Color.spotsAccent)
                            Text("Tap to open the emoji keyboard.")
                                .font(.geist(size: 12))
                                .foregroundStyle(Color.spotsTextMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("Quick picks")
                    .font(.geist(size: 11, weight: .medium))
                    .foregroundStyle(Color.spotsTextMuted)
                    .padding(.top, 4)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6),
                    spacing: 6
                ) {
                    ForEach(starterEmojis, id: \.self) { emoji in
                        Button {
                            draft = (draft == emoji) ? nil : emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: 24))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(draft == emoji ? Color.spotsAccentSoft : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(draft == emoji ? Color.spotsAccent : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Invisible bridge that captures the emoji-keyboard selection.
                // QA round 3: revert to direct inline keyboard (no extra sheet).
                EmojiKeyboardField(
                    emoji: Binding(
                        get: { draft },
                        set: { if let new = $0 { draft = new } }
                    ),
                    isFocused: $keyboardFocused
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .navigationTitle("List icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.spotsAccent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onCommit(draft) }
                        .font(.geist(size: 15, weight: .semibold))
                        .foregroundStyle(Color.spotsAccent)
                }
            }
        }
    }
}

// MARK: - Edit-description sub-sheet

private struct EditDescriptionSheet: View {
    let currentDescription: String?
    /// Async throws closure — owner of the sheet handles the actual persist.
    /// We surface errors inline so the user sees feedback (the previous
    /// version's error lived on the hidden parent ListSettingsSheet, making
    /// Save feel like a no-op).
    let onSave: (String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @FocusState private var focused: Bool

    init(currentDescription: String?, onSave: @escaping (String?) async throws -> Void) {
        self.currentDescription = currentDescription
        self.onSave = onSave
        self._draft = State(initialValue: currentDescription ?? "")
    }

    private static let maxLength = LocationSavingService.maxListDescriptionLength

    private var canCommit: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = currentDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed != original && draft.count <= Self.maxLength && !isSaving
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add a description")
                    .font(.geist(size: 13, weight: .medium))
                    .foregroundStyle(Color.spotsTextMuted)

                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("e.g. \"Best taquerias on Calle Madero\" or \"Trip planning for August 2026\"")
                            .font(.geist(size: 15))
                            .foregroundStyle(Color.spotsTextSubtle)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $draft)
                        .focused($focused)
                        .font(.geist(size: 15))
                        .foregroundStyle(Color.spotsText)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minHeight: 140)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.spotsBorder, lineWidth: 1)
                        )
                        .onChange(of: draft) { _, newValue in
                            if newValue.count > Self.maxLength {
                                draft = String(newValue.prefix(Self.maxLength))
                            }
                        }
                }

                HStack {
                    Text("Tell others what this list is about. Optional.")
                        .font(.geist(size: 12))
                        .foregroundStyle(Color.spotsTextMuted)
                    Spacer()
                    Text("\(draft.count) / \(Self.maxLength)")
                        .font(.geistMono(size: 11))
                        .foregroundStyle(Color.spotsTextSubtle)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.geist(size: 13))
                        .foregroundStyle(Color.spotsError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            .padding(20)
            .navigationTitle("Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.spotsAccent)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Save") { commit() }
                            .font(.geist(size: 15, weight: .semibold))
                            .foregroundStyle(canCommit ? Color.spotsAccent : Color.spotsTextSubtle)
                            .disabled(!canCommit)
                    }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty → nil so the column gets cleared rather than storing an empty string.
        let payload: String? = trimmed.isEmpty ? nil : trimmed
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await onSave(payload)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorMessage = (error as? CustomListError)?.errorDescription
                    ?? friendlyError(for: error)
            }
        }
    }

    /// Translate common Supabase / Postgrest errors into copy Maya can act on.
    /// The most likely failure today is "column user_lists.description does not
    /// exist" — surfaces when the new SQL migration hasn't been applied yet.
    private func friendlyError(for error: Error) -> String {
        let desc = error.localizedDescription.lowercased()
        if desc.contains("description") && desc.contains("does not exist") {
            return "Description column not found. Apply the 2026-05-25_lists_add_description.sql migration in Supabase and try again."
        }
        return "Couldn't save the description. Check your connection and try again."
    }
}

// MARK: - Collaborators placeholder sub-sheet (T4 fills in)

private struct CollaboratorsPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.spotsAccent)
                    .padding(.top, 24)
                Text("Coming soon")
                    .font(.geist(size: 19, weight: .semibold))
                    .foregroundStyle(Color.spotsText)
                Text("Invite friends by handle or share a link so they can add spots to this list. Shipping in the next update.")
                    .font(.geist(size: 13))
                    .foregroundStyle(Color.spotsTextMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .navigationTitle("Collaborators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.spotsAccent)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Custom list — full menu") {
    let sample = UserList(
        id: UUID(),
        userId: UUID(),
        kind: .custom,
        name: "Mexico City 2026",
        visibility: .shared,
        coverEmoji: "🌮"
    )
    return ListSettingsSheet(list: sample)
        .environmentObject(LocationSavingViewModel())
}

#Preview("Default list — rename + delete hidden") {
    let sample = UserList(
        id: UUID(),
        userId: UUID(),
        kind: .favorites,
        name: nil,
        visibility: .private,
        coverEmoji: "❤️"
    )
    return ListSettingsSheet(list: sample)
        .environmentObject(LocationSavingViewModel())
}
