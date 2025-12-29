//
//  ExploreView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

struct ExploreView: View {
    @State private var showSearchView = false
    
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search Bar
                Button(action: {
                    showSearchView = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundColor(.gray400)
                        
                        Text("Search for places...")
                            .font(.system(size: 16))
                            .foregroundColor(.gray400)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(24)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 0)
                
                // Placeholder Map View
                ZStack {
                    // Placeholder background to simulate map appearance
                    // This will be replaced with actual Google Maps integration later
                    Color(red: 0.96, green: 0.95, blue: 0.93) // Light beige/gray to simulate map
                        .ignoresSafeArea()
                    
                    // Optional: Add some visual elements to make it look more like a map
                    VStack {
                        Spacer()
                        Text("Map View")
                            .font(.system(size: 14))
                            .foregroundColor(.gray400)
                            .padding(.bottom, 100)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showSearchView) {
            SearchView(
                onSelectSpot: { spotName in
                    print("Selected spot: \(spotName)")
                    // Handle spot selection here
                },
                onFiltersClick: {
                    // Handle filters click here
                    print("Filters clicked")
                },
                recentSpots: [],
                recentUsers: [],
                searchResults: (spots: [], users: []),
                onSearch: { query, mode in
                    print("Search: \(query) in mode: \(mode)")
                    // Handle search here - fetch results and update searchResults
                },
                onUserFollow: { userId, isFollowing in
                    print("User \(userId) follow state: \(isFollowing)")
                    // Handle follow/unfollow here
                }
            )
        }
    }
}

#Preview {
    ExploreView()
}

