//
//  MainTabView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI
import UIKit

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 1
    // Tabs are mounted on first visit and then kept alive (preserves map camera,
    // feed scroll position, etc.). We start with only the default tab mounted so
    // cold start doesn't pay for the other tabs' .task / .onAppear work.
    @State private var mountedTabs: Set<Int> = [1]
    // Constructed together so MapViewModel can hold the same LocationSavingViewModel
    // that's published as an @EnvironmentObject below — single source of truth for
    // saved-places state across Explore + Newsfeed.
    @StateObject private var locationSavingVM: LocationSavingViewModel
    @StateObject private var mapViewModel: MapViewModel
    // Hoisted out of NewsFeedView so the tab bar can drive scroll-to-top and
    // tab-return refresh without an extra coordination object, and so the
    // feed's state survives any future un-mount.
    @StateObject private var feedViewModel = FeedViewModel()

    /// Local copy of the toast message that drives the overlay's animation.
    /// Read once from `locationSavingVM.lastSaveError`, displayed for ~2s,
    /// then cleared (both locally and on the VM).
    @State private var visibleSaveError: String?

    // Force opaque white tab bar with a very subtle hairline (Instagram-style).
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        // Subtle hairline: ~6% black instead of iOS's heavier system separator
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.06)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        // Build LocationSavingViewModel first; pass it into MapViewModel so
        // both observe the same saved-places state. SwiftUI initializes
        // @StateObject lazily — wrapping each in StateObject(wrappedValue:)
        // here guarantees both are constructed exactly once per MainTabView
        // instance with the cross-VM reference intact.
        let saving = LocationSavingViewModel()
        _locationSavingVM = StateObject(wrappedValue: saving)
        _mapViewModel = StateObject(wrappedValue: MapViewModel(locationSavingVM: saving))
    }

    var body: some View {
        // Custom binding so we can detect "tapped the already-active tab" and
        // "switched into the Newsfeed tab" — SwiftUI's default selection
        // binding fires only on actual changes.
        let tabSelection = Binding<Int>(
            get: { selectedTab },
            set: { newValue in
                if newValue == 0 {
                    if selectedTab == 0 {
                        // Re-tap on the already-active Newsfeed tab → scroll-to-top + refresh.
                        feedViewModel.scrollToTopToken = UUID()
                    } else {
                        // Switching back into the Newsfeed tab → soft refresh if stale.
                        Task { await feedViewModel.refreshIfStale() }
                    }
                }
                selectedTab = newValue
                mountedTabs.insert(newValue)
            }
        )

        return TabView(selection: tabSelection) {
            Group {
                if mountedTabs.contains(0) {
                    NewsFeedView(viewModel: feedViewModel)
                } else {
                    Color.clear
                }
            }
            .tabItem { Label("Newsfeed", systemImage: "newspaper") }
            .tag(0)

            Group {
                if mountedTabs.contains(1) {
                    ExploreView(viewModel: mapViewModel)
                } else {
                    Color.clear
                }
            }
            .tabItem { Label("Explore", systemImage: "magnifyingglass") }
            .tag(1)

            Group {
                if mountedTabs.contains(2) {
                    NavigationStack {
                        ProfileView()
                    }
                } else {
                    Color.clear
                }
            }
            .tabItem { Label("Profile", systemImage: "person") }
            .tag(2)
        }
        .symbolVariant(.none)
        .environmentObject(locationSavingVM)
        .overlay(alignment: .top) {
            saveErrorToast
        }
        .onChange(of: selectedTab) { _, newTab in
            mountedTabs.insert(newTab)
        }
        .onAppear {
            mapViewModel.requestLocation()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                mapViewModel.resetExploreSession()
            }
        }
        .onChange(of: locationSavingVM.lastSaveError) { _, newError in
            // VM publishes a fresh error → mirror to local @State so the toast
            // animates in. Clear the VM side immediately so the same error
            // message can re-fire if the user retries and fails again.
            guard let newError else { return }
            visibleSaveError = newError
            locationSavingVM.lastSaveError = nil
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if visibleSaveError == newError {
                    withAnimation(.easeOut(duration: 0.2)) {
                        visibleSaveError = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var saveErrorToast: some View {
        if let message = visibleSaveError {
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.85))
                .clipShape(Capsule())
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: visibleSaveError)
        }
    }
}

#Preview {
    MainTabView()
}
