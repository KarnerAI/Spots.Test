//
//  SaveSpotButton.swift
//  Spots.Test
//
//  Shared bookmark / list-icon button used by the Explore card and the
//  Newsfeed card. Three render states:
//
//    !hasLoadedSavedPlaces  → generic gray bookmark (we don't know yet)
//    kind == nil            → generic gray bookmark (not in any default list)
//    kind == .favorites     → ListIconView red heart   (elite love)
//    kind == .liked         → ListIconView blue thumb  (mid love)
//    kind == .wantToGo      → ListIconView emerald flag (wishlist)
//
//  Tap opens the ListPickerSheet via the owner's `onTap` closure — same as
//  the prior teal "Spot" button on the feed and the bookmark on Explore.
//

import SwiftUI

struct SaveSpotButton: View {
    let placeId: String
    let kind: ListKind?
    let hasLoadedSavedPlaces: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if hasLoadedSavedPlaces, let kind {
                    ListIconView(kind: kind)
                        .font(.system(size: 16, weight: .medium))
                } else {
                    Image(systemName: "bookmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray500)
                }
            }
            .frame(width: 36, height: 36)
            .background(Color.gray100)
            .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard hasLoadedSavedPlaces, let kind else {
            return "Save spot"
        }
        return "Saved to \(kind.displayName)"
    }
}

#Preview("Not loaded") {
    SaveSpotButton(placeId: "abc", kind: nil, hasLoadedSavedPlaces: false, onTap: {})
        .padding()
}

#Preview("Loaded — not saved") {
    SaveSpotButton(placeId: "abc", kind: nil, hasLoadedSavedPlaces: true, onTap: {})
        .padding()
}

#Preview("Loaded — favorites") {
    SaveSpotButton(placeId: "abc", kind: .liked, hasLoadedSavedPlaces: true, onTap: {})
        .padding()
}

#Preview("Loaded — top spots") {
    SaveSpotButton(placeId: "abc", kind: .favorites, hasLoadedSavedPlaces: true, onTap: {})
        .padding()
}

#Preview("Loaded — bucket list") {
    SaveSpotButton(placeId: "abc", kind: .wantToGo, hasLoadedSavedPlaces: true, onTap: {})
        .padding()
}
