//
//  UserList.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//
//  Phase 1 / Ticket T2: legacy `ListType` (starred/favorites/bucket_list)
//  replaced by `ListKind` (favorites/liked/want_to_go/custom/trip/date_plan).
//  The DB column `user_lists.list_type` was dropped and replaced by
//  `user_lists.kind` in 2026-05-23_phase1_lists_and_imports.sql. Display
//  labels now match DB values directly — no more starred=Favorites quirk.
//

import Foundation
import SwiftUI

// MARK: - List Kind

/// Semantic kind of a list. Matches the DB enum `list_kind_enum`.
///
/// - `favorites` / `liked` / `wantToGo`: the 3 default system lists.
///   Auto-created for every user on signup.
/// - `custom`: user-created list with a name.
/// - `trip` / `datePlan`: Phase 3 list kinds that carry `startDate` /
///   `endDate`. Treated as custom lists in Phase 1.
enum ListKind: String, Codable, CaseIterable {
    case favorites = "favorites"
    case liked = "liked"
    case wantToGo = "want_to_go"
    case custom = "custom"
    case trip = "trip"
    case datePlan = "date_plan"

    /// User-facing display label. For system kinds this is the canonical
    /// name shown in UI; custom-kind lists use their `name` field instead.
    var displayName: String {
        switch self {
        case .favorites: return "Favorites"
        case .liked: return "Liked"
        case .wantToGo: return "Want to Go"
        case .custom: return "List"
        case .trip: return "Trip"
        case .datePlan: return "Date plan"
        }
    }

    /// SF Symbol icon. Carried over from the legacy ListType:
    /// heart = elite love (Favorites), thumbs-up = mid (Liked),
    /// flag = wishlist (Want to Go). The 3 new kinds get minimal
    /// styling here — final iconography lands in T3+ design work.
    var iconName: String {
        switch self {
        case .favorites: return "heart.fill"
        case .liked: return "hand.thumbsup.fill"
        case .wantToGo: return "flag.fill"
        case .custom: return "list.bullet"
        case .trip: return "airplane"
        case .datePlan: return "calendar"
        }
    }

    /// Tint color for the icon. Matches iconName semantically.
    var iconColor: Color {
        switch self {
        case .favorites: return Color(red: 0.94, green: 0.27, blue: 0.27) // #EF4444 red
        case .liked: return Color(red: 0.23, green: 0.51, blue: 0.96)    // #3B82F6 blue
        case .wantToGo: return Color(red: 0.06, green: 0.73, blue: 0.51) // #10B981 emerald
        case .custom: return Color.gray
        case .trip: return Color(red: 0.15, green: 0.39, blue: 0.92)     // #2563EB cool blue (DESIGN.md)
        case .datePlan: return Color(red: 0.15, green: 0.39, blue: 0.92)
        }
    }

    /// The 3 default system kinds. Auto-created per user on signup;
    /// cannot be deleted by RLS policy.
    static let systemKinds: Set<ListKind> = [.favorites, .liked, .wantToGo]

    var isSystemKind: Bool { ListKind.systemKinds.contains(self) }
}

// MARK: - List Visibility

/// Whether a list is privately scoped to the owner+editors or readable
/// publicly via its `shareSlug`. Default `.private`.
enum ListVisibility: String, Codable, CaseIterable {
    case `private` = "private"
    case `public` = "public"
}

// MARK: - Display Kind Resolver

/// Returns the single list kind to display for a spot when it belongs
/// to more than one of the 3 system lists. Priority preserved from the
/// legacy `displayListType(for:)`: wantToGo > favorites > liked.
///
/// Non-system kinds (custom/trip/date_plan) are not part of the system
/// display priority and are ignored by this helper.
///
/// - Parameter saved: Set of list kinds the spot belongs to.
/// - Returns: The system list kind to display, or nil if no system kind matches.
func displayKind(for saved: Set<ListKind>) -> ListKind? {
    if saved.contains(.wantToGo) {
        return .wantToGo
    } else if saved.contains(.favorites) {
        return .favorites
    } else if saved.contains(.liked) {
        return .liked
    }
    return nil
}

// MARK: - Shared List Icon View

/// Shared view component for rendering list kind icons with consistent styling.
struct ListIconView: View {
    let kind: ListKind

    var body: some View {
        Image(systemName: kind.iconName)
            .foregroundColor(kind.iconColor)
    }
}

// MARK: - User List Model

/// Mirrors a row in `public.user_lists` (post-Phase-1 schema).
///
/// Column → field mapping:
///
///     id              -> id
///     user_id         -> userId
///     kind            -> kind                (NOT NULL, default 'custom')
///     name            -> name                (nullable for system kinds)
///     visibility      -> visibility          (NOT NULL, default .private)
///     share_slug      -> shareSlug           (nullable, unique when set)
///     invite_token    -> inviteToken         (nullable, unique when set)
///     start_date      -> startDate           (nullable)
///     end_date        -> endDate             (nullable)
///     cover_image_url -> coverImageUrl       (nullable)
///     cover_emoji     -> coverEmoji          (nullable)
///     created_at      -> createdAt
///     updated_at      -> updatedAt
struct UserList: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let userId: UUID
    let kind: ListKind
    let name: String?
    let visibility: ListVisibility
    let shareSlug: String?
    let inviteToken: String?
    let startDate: Date?
    let endDate: Date?
    let coverImageUrl: String?
    let coverEmoji: String?
    let createdAt: Date?
    let updatedAt: Date?

    /// Resolved display name. System kinds use their canonical label;
    /// custom kinds use the user-supplied `name`.
    var displayName: String {
        if kind.isSystemKind {
            return kind.displayName
        }
        return name ?? "Untitled List"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case kind
        case name
        case visibility
        case shareSlug = "share_slug"
        case inviteToken = "invite_token"
        case startDate = "start_date"
        case endDate = "end_date"
        case coverImageUrl = "cover_image_url"
        case coverEmoji = "cover_emoji"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Custom decoder so existing rows (pre-Phase-1) and forward-compat
    /// rows (unknown future kind values) both decode predictably.
    /// `visibility` defaults to `.private` if absent.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.userId = try c.decode(UUID.self, forKey: .userId)
        self.kind = try c.decode(ListKind.self, forKey: .kind)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.visibility = try c.decodeIfPresent(ListVisibility.self, forKey: .visibility) ?? .private
        self.shareSlug = try c.decodeIfPresent(String.self, forKey: .shareSlug)
        self.inviteToken = try c.decodeIfPresent(String.self, forKey: .inviteToken)
        self.startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        self.endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        self.coverImageUrl = try c.decodeIfPresent(String.self, forKey: .coverImageUrl)
        self.coverEmoji = try c.decodeIfPresent(String.self, forKey: .coverEmoji)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// Explicit memberwise initializer used by tests and callers.
    init(
        id: UUID,
        userId: UUID,
        kind: ListKind,
        name: String? = nil,
        visibility: ListVisibility = .private,
        shareSlug: String? = nil,
        inviteToken: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        coverImageUrl: String? = nil,
        coverEmoji: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.kind = kind
        self.name = name
        self.visibility = visibility
        self.shareSlug = shareSlug
        self.inviteToken = inviteToken
        self.startDate = startDate
        self.endDate = endDate
        self.coverImageUrl = coverImageUrl
        self.coverEmoji = coverEmoji
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
