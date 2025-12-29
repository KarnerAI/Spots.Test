//
//  CustomBottomNav.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

struct CustomBottomNav: View {
    @Binding var selectedTab: Int
    let onTabChange: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Top border/separator
            Rectangle()
                .fill(Color.gray200)
                .frame(height: 0.5)
            
            // Navigation tabs
            HStack(spacing: 0) {
                // Newsfeed Tab
                TabButton(
                    icon: "newspaper",
                    label: "Newsfeed",
                    isSelected: selectedTab == 0,
                    action: {
                        selectedTab = 0
                        onTabChange(0)
                    }
                )
                
                // Explore Tab
                TabButton(
                    icon: "compass",
                    label: "Explore",
                    isSelected: selectedTab == 1,
                    action: {
                        selectedTab = 1
                        onTabChange(1)
                    }
                )
                
                // Profile Tab
                TabButton(
                    icon: "person",
                    label: "Profile",
                    isSelected: selectedTab == 2,
                    action: {
                        selectedTab = 2
                        onTabChange(2)
                    }
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(Color.white)
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom) {
            Color.white
                .frame(height: 0)
        }
    }
}

struct TabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(isSelected ? .gray900 : .gray400)
                
                Text(label)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(isSelected ? .gray900 : .gray400)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    CustomBottomNav(selectedTab: .constant(1)) { _ in }
}

