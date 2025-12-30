//
//  UserList.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import Foundation

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

