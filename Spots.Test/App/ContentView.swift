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
        Group {
            if viewModel.isAuthenticated {
                if viewModel.needsPostSignupOnboarding {
                    // Post-signup flow: 4-step container that the user
                    // completes (or skips through). When done, the VM
                    // clears profiles.onboarding_step and AuthVM flips
                    // `needsPostSignupOnboarding` back to false — this
                    // branch then yields to MainTabView reactively.
                    PostSignupOnboardingFlow(authVM: viewModel)
                } else {
                    MainTabView().environmentObject(viewModel)
                }
            } else {
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
        }
    }
    
    private func handleLogin() {
        // Authentication state is now handled by the viewModel
        // The view will automatically update when isAuthenticated changes
    }
}

#Preview {
    ContentView()
}
