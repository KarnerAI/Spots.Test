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
    @StateObject private var locationSavingVM = LocationSavingViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content views — keep all alive to avoid recreating GMSMapView on tab switch
            ZStack {
                NewsFeedView()
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)
                ExploreView(viewModel: mapViewModel)
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)
                NavigationStack {
                    ProfileView()
                }
                .opacity(selectedTab == 2 ? 1 : 0)
                .allowsHitTesting(selectedTab == 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(locationSavingVM)
            
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

