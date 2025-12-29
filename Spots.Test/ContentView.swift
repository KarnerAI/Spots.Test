//
//  ContentView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AuthenticationViewModel()
    
    var body: some View {
        ZStack {
            switch viewModel.currentScreen {
            case .welcome:
                WelcomeView(viewModel: viewModel) {
                    handleLogin()
                }
            case .signup:
                SignUpView(viewModel: viewModel) {
                    handleLogin()
                }
            case .login:
                LoginView(viewModel: viewModel) {
                    handleLogin()
                }
            }
        }
    }
    
    private func handleLogin() {
        // Handle successful login - navigate to main app
        print("User logged in successfully")
        // In a real app, you would navigate to the main app screen here
    }
}

#Preview {
    ContentView()
}
