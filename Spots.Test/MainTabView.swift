//
//  MainTabView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 1 // Default to Explore tab (index 1)
    @StateObject private var mapViewModel = MapViewModel()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Content views
            Group {
                if selectedTab == 0 {
                    NewsFeedView()
                } else if selectedTab == 1 {
                    ExploreView(viewModel: mapViewModel)
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
        .onAppear {
            mapViewModel.requestLocation()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                mapViewModel.resetExploreSession()
            }
        }
    }
}

#Preview {
    MainTabView()
}

