//
//  SaveSpotButton.swift
//  Spots.Test
//
//  Shared bookmark / list-icon button used by the Explore card and the
//  Newsfeed card. Three render states:
//
//    !hasLoadedSavedPlaces  → generic gray bookmark (we don't know yet)
//    listType == nil        → generic gray bookmark (not in any default list)
//    listType == .favorites → ListIconView red heart
//    listType == .starred   → ListIconView gold star
//    listType == .bucketList → ListIconView blue flag
//
//  Tap opens the ListPickerSheet via the owner's `onTap` closure — same as
//  the prior teal "Spot" button on the feed and the bookmark on Explore.
//

import SwiftUI

struct SaveSpotButton: View {
    let placeId: String
    let listType: ListType?
    let hasLoadedSavedPlaces: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if hasLoadedSavedPlaces, let listType {
                    ListIconView(listType: listType)
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
        guard hasLoadedSavedPlaces, let listType else {
            return "Save spot"
        }
        switch listType {
        case .favorites:  return "Saved to Favorites"
        case .starred:    return "Saved to Top Spots"
        case .bucketList: return "Saved to Want to Go"
        }
    }
}

#Preview("Not loaded") {
    SaveSpotButton(placeId: "abc", listType: nil, hasLoadedSavedPlaces: false, onTap: {})
        .padding()
}

#Preview("Loaded — not saved") {
    SaveSpotButton(placeId: "abc", listType: nil, hasLoadedSavedPlaces: true, onTap: {})
        .padding()
}

#Preview("Loaded — favorites") {
    SaveSpotButton(placeId: "abc", listType: .favorites, hasLoadedSavedPlaces: true, onTap: {})
        .padding()
}

#Preview("Loaded — top spots") {
    SaveSpotButton(placeId: "abc", listType: .starred, hasLoadedSavedPlaces: true, onTap: {})
        .padding()
}

#Preview("Loaded — bucket list") {
    SaveSpotButton(placeId: "abc", listType: .bucketList, hasLoadedSavedPlaces: true, onTap: {})
        .padding()
}
