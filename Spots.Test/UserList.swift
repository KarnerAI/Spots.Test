//
//  UserList.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation
import SwiftUI

enum ListType: String, Codable {
    case starred
    case favorites
    case bucketList = "bucket_list"
    
    var displayName: String {
        switch self {
        case .starred: return "Starred"
        case .favorites: return "Favorites"
        case .bucketList: return "Bucket List"
        }
    }
    
    var iconName: String {
        switch self {
        case .starred: return "star.fill"
        case .favorites: return "heart.fill"
        case .bucketList: return "flag.fill"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .starred: return Color(red: 0.92, green: 0.70, blue: 0.03) // #EAB308
        case .favorites: return Color(red: 0.94, green: 0.27, blue: 0.27) // #EF4444
        case .bucketList: return Color(red: 0.23, green: 0.51, blue: 0.96) // #3B82F6
        }
    }
}

// MARK: - Display List Type Resolver

/// Returns the single list type to display for a spot based on priority.
/// Priority: bucketList > starred > favorites
/// - Parameter saved: Set of list types the spot belongs to
/// - Returns: The list type to display, or nil if the set is empty
func displayListType(for saved: Set<ListType>) -> ListType? {
    if saved.contains(.bucketList) {
        return .bucketList
    } else if saved.contains(.starred) {
        return .starred
    } else if saved.contains(.favorites) {
        return .favorites
    }
    return nil
}

// MARK: - Shared List Icon View

/// Shared view component for rendering list type icons with consistent styling
struct ListIconView: View {
    let listType: ListType
    
    var body: some View {
        Image(systemName: listType.iconName)
            .foregroundColor(listType.iconColor)
    }
}

struct UserList: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let listType: ListType?
    let name: String?
    let createdAt: Date?
    let updatedAt: Date?
    
    var displayName: String {
        if let listType = listType {
            return listType.displayName
        }
        return name ?? "Untitled List"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case listType = "list_type"
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

