//
//  EmojiPickerSheet.swift
//  Spots.Test
//
//  T21 QA round 2: a presented sheet that wraps the iOS emoji keyboard
//  with a rounded-top sheet host so it visually matches the iMessage
//  emoji panel (rounded top corners, drag handle, sheet shadow).
//
//  Previous implementation raised the system keyboard directly on top of
//  the parent .sheet — that gave flat top corners and felt visually broken
//  next to iMessage's rounded panel. This version presents the EmojiKeyboardField
//  inside a small SwiftUI sheet with .presentationDetents and .presentationDragIndicator,
//  letting iOS render the sheet chrome (rounded corners + drag handle) on top
//  of the keyboard surface.
//
//  Usage:
//    @State var presentingEmoji = false
//    @State var picked: String? = nil
//    .sheet(isPresented: $presentingEmoji) {
//        EmojiPickerSheet(picked: $picked)
//            .presentationDetents([.height(360)])
//            .presentationDragIndicator(.visible)
//    }
//

import SwiftUI

/// Sheet host for the EmojiKeyboardField. Auto-focuses the invisible
/// TextField on appear so the emoji keyboard rises immediately, then
/// dismisses itself when the user picks an emoji.
struct EmojiPickerSheet: View {
    /// Bound emoji value. Updated when the user selects an emoji.
    @Binding var picked: String?

    @Environment(\.dismiss) private var dismiss
    @State private var focused: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Pick an emoji")
                    .font(.geist(size: 16, weight: .semibold))
                    .foregroundStyle(Color.spotsText)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.geist(size: 14, weight: .medium))
                    .foregroundStyle(Color.spotsAccent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // The big preview area — shows whatever has been selected so far
            // (mostly for visual feedback during the keyboard interaction).
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.spotsAccentSoft)
                    .frame(width: 88, height: 88)
                if let picked {
                    Text(picked).font(.system(size: 44))
                } else {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.spotsAccent.opacity(0.55))
                }
            }

            Text("Use the keyboard search to find any emoji.")
                .font(.geist(size: 12))
                .foregroundStyle(Color.spotsTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer(minLength: 0)

            // Invisible 1x1 emoji-keyboard text field. Focused on appear so
            // the iOS emoji keyboard rises into the sheet's bottom area.
            EmojiKeyboardField(
                emoji: Binding(
                    get: { picked },
                    set: { new in
                        if let new {
                            picked = new
                            // Tiny delay so the preview tile briefly shows
                            // the selection before the sheet closes.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                dismiss()
                            }
                        }
                    }
                ),
                isFocused: $focused
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .background(Color.white)
        .onAppear {
            // Slight delay lets the sheet finish its presentation animation
            // before the keyboard rises — avoids a flicker on iOS 17.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                focused = true
            }
        }
    }
}
