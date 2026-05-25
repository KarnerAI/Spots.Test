//
//  EmojiKeyboardField.swift
//  Spots.Test
//
//  T21 polish: a UITextField bridge that forces the iOS emoji keyboard to
//  appear when focused. Used in CreateListView and ListSettingsSheet so Maya
//  can pick any emoji (with search!) instead of being constrained to the
//  12-emoji quick-tap grid.
//
//  How it works:
//    Override `textInputMode` on UITextField to return the "emoji" input mode
//    from UITextInputMode.activeInputModes. iOS opens the emoji keyboard
//    directly, including the magnifying-glass search field at the top.
//
//  The TextField itself is invisible to the user — we only care about
//  receiving keystrokes. The selected emoji is captured via the delegate,
//  written to a binding, and the field's text is cleared so subsequent
//  presentations start fresh.
//
//  Quirks:
//    - iOS only exposes the emoji input mode if at least one emoji keyboard
//      is enabled on the device. This is the default since iOS 13, but in
//      the edge case where it's disabled, the keyboard falls back to the
//      user's primary language keyboard. Maya can still type unicode emoji
//      via the system globe key.
//    - `textInputContextIdentifier` must be a non-nil string ("" works) to
//      prevent UIKit from caching a previous keyboard mode for this field.
//
//  Reference: this is the standard pattern documented in WWDC sessions and
//  used by Apple Notes / Reminders for their emoji-tag pickers.
//

import SwiftUI
import UIKit

/// SwiftUI wrapper around `EmojiKeyboardUITextField`. Push focus on/off via
/// the `isFocused` binding; the selected emoji lands in `emoji`.
struct EmojiKeyboardField: UIViewRepresentable {
    @Binding var emoji: String?
    @Binding var isFocused: Bool

    func makeUIView(context: Context) -> EmojiKeyboardUITextField {
        let field = EmojiKeyboardUITextField()
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        // Invisible — we just want the keyboard, not a visible input.
        field.tintColor = .clear
        field.textColor = .clear
        field.backgroundColor = .clear
        field.borderStyle = .none
        return field
    }

    func updateUIView(_ uiView: EmojiKeyboardUITextField, context: Context) {
        if isFocused && !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isFocused && uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(emoji: $emoji, isFocused: $isFocused)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var emoji: String?
        @Binding var isFocused: Bool

        init(emoji: Binding<String?>, isFocused: Binding<Bool>) {
            self._emoji = emoji
            self._isFocused = isFocused
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            // Capture the first emoji from the input. Reject non-emoji input
            // so the user can't paste/type random text. Backspace (empty
            // string) is allowed so they can clear if needed.
            if string.isEmpty {
                emoji = nil
                return false
            }
            if let firstEmoji = string.firstEmoji {
                emoji = String(firstEmoji)
                // Resign focus on selection — feels like a "picked" gesture.
                DispatchQueue.main.async {
                    self.isFocused = false
                    textField.resignFirstResponder()
                }
                return false
            }
            // Non-emoji input rejected. The keyboard stays open but the
            // character doesn't land.
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            // Sync state if the user dismissed via tap-outside or hardware
            // keyboard rather than picking an emoji.
            DispatchQueue.main.async { self.isFocused = false }
        }
    }
}

/// UITextField subclass that pins its keyboard to the emoji input mode.
/// iOS picks this up before the keyboard is materialized.
final class EmojiKeyboardUITextField: UITextField {
    /// Forces UIKit to treat this field as a unique input context. Without
    /// this, the system may reuse a previously-active keyboard mode (e.g.
    /// the user's primary language) and ignore textInputMode entirely.
    override var textInputContextIdentifier: String? { "" }

    /// Returns the emoji input mode if available. iOS automatically includes
    /// it as long as the user hasn't disabled emoji in keyboard settings.
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { mode in
            mode.primaryLanguage == "emoji"
        }
    }
}

// MARK: - Emoji detection helper

private extension Character {
    /// Treats any character whose scalars include an Emoji_Presentation or
    /// non-ASCII Emoji as an emoji. Covers single-scalar emoji (🌮), ZWJ
    /// sequences (👨‍👩‍👧), and flags (🇲🇽).
    var isEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        // Anything in the emoji ranges, or any non-ASCII scalar that's marked
        // as emoji presentation.
        if first.properties.isEmoji && (first.properties.isEmojiPresentation || first.value > 0x238C) {
            return true
        }
        return unicodeScalars.contains(where: { $0.properties.isEmojiPresentation })
    }
}

private extension String {
    /// First emoji character in the string, or nil if none.
    var firstEmoji: Character? {
        first(where: { $0.isEmoji })
    }
}
