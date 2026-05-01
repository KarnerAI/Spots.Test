//
//  UserListRowView.swift
//  Spots.Test
//
//  Reusable row for the Followers / Following lists. Avatar + @username +
//  display name, a "View Profile" pill button, and an X to remove the user
//  from the current list (Remove Follower or Unfollow, depending on tab).
//

import SwiftUI

struct UserListRowView: View {
    let profile: UserProfile
    var onViewProfile: () -> Void
    var onRemove: () -> Void
    var isRemoving: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(urlString: profile.avatarUrl, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.username)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray900)
                    .lineLimit(1)
                Text(profile.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(.gray500)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onViewProfile) {
                Text("View Profile")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray700)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray100)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray500)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(isRemoving)
            .opacity(isRemoving ? 0.4 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
