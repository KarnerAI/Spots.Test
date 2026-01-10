//
//  CustomBottomNav.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI
import Foundation
import UIKit

// #region agent log
func debugLog(_ message: String, data: [String: Any] = [:]) {
    let logPath = "/Users/shaon/Library/CloudStorage/GoogleDrive-hussain@karnerblu.com/Shared drives/6. Spots 2.0/3. Engineering/2. CodeBase/SpotsTest/Spots.Test/.cursor/debug.log"
    let logEntry: [String: Any] = [
        "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        "location": "CustomBottomNav.swift",
        "message": message,
        "data": data,
        "sessionId": "debug-session",
        "runId": "run1"
    ]
    // Also print to console for debugging
    print("🔍 DEBUG: \(message) - \(data)")
    
    if let jsonData = try? JSONSerialization.data(withJSONObject: logEntry),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        // Create directory if it doesn't exist
        let fileManager = FileManager.default
        let directory = (logPath as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        
        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
            fileHandle.seekToEndOfFile()
            fileHandle.write((jsonString + "\n").data(using: .utf8)!)
            fileHandle.closeFile()
        } else {
            try? jsonString.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
}
// #endregion

struct CustomBottomNav: View {
    @Binding var selectedTab: Int
    let onTabChange: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Top border/separator
            Rectangle()
                .fill(Color(red: 0.88, green: 0.88, blue: 0.88))
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
                    icon: "safari",
                    label: "Explore",
                    isSelected: selectedTab == 1,
                    action: {
                        // #region agent log
                        debugLog("Explore tab clicked", data: ["icon": "safari", "selectedTab": selectedTab, "hypothesisId": "A"])
                        // #endregion
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
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(isSelected ? Color(red: 0.13, green: 0.13, blue: 0.13) : Color(red: 0.63, green: 0.63, blue: 0.63))
                
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color(red: 0.13, green: 0.13, blue: 0.13) : Color(red: 0.63, green: 0.63, blue: 0.63))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        // #region agent log
        .onAppear {
            debugLog("TabButton view appeared", data: ["icon": icon, "label": label, "isSelected": isSelected, "hypothesisId": "C"])
        }
        // #endregion
    }
}

#Preview {
    CustomBottomNav(selectedTab: .constant(1)) { _ in }
}

