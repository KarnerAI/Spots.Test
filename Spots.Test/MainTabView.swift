//
//  MainTabView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1 // Default to Explore tab (index 1)
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Content views
            Group {
                if selectedTab == 0 {
                    NewsFeedView()
                } else if selectedTab == 1 {
                    ExploreView()
                } else {
                    ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom bottom navigation bar
            VStack {
                Spacer()
                CustomBottomNav(selectedTab: $selectedTab) { tab in
                    selectedTab = tab
                }
            }
        }
    }
}

#Preview {
    MainTabView()
}

