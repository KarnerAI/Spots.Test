//
//  AvatarView.swift
//  Spots.Test
//
//  Circular avatar that loads from a URL string with a `person.fill` placeholder.
//  Treats AsyncImage `.empty` and `.failure` identically so the view never gets
//  stuck on an indefinite spinner when the URL is missing or fails to load.
//

import SwiftUI

struct AvatarView: View {
    let urlString: String?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let url = resolvedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    /// Parse the URL string defensively. Some Supabase storage URLs include
    /// characters (spaces, commas, parens from filenames) that aren't valid
    /// in a URL until percent-encoded — `URL(string:)` returns nil for those.
    /// Try a strict parse first; fall back to a percent-encoded retry so a
    /// single bad character doesn't drop the whole avatar to the placeholder.
    private var resolvedURL: URL? {
        guard let raw = urlString, !raw.isEmpty else { return nil }
        if let url = URL(string: raw) { return url }
        let allowed = CharacterSet.urlQueryAllowed.union(.urlPathAllowed)
        if let encoded = raw.addingPercentEncoding(withAllowedCharacters: allowed),
           let url = URL(string: encoded) {
            return url
        }
        return nil
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.gray200)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.gray400)
            )
    }
}
