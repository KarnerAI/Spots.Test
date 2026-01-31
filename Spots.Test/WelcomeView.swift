//
//  WelcomeView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

struct WelcomeView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    let onLogin: () -> Void
    
    var body: some View {
        ZStack {
            // Background - solid white
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo and Welcome Message
                VStack(spacing: 24) {
                    // Logo
                    Image("SpotsLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)
                    
                    VStack(spacing: 12) {
                        Text("Welcome to Spots")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.gray900)
                        
                        Text("Save, Discover, and Explore Spots through Friends.")
                            .font(.system(size: 16))
                            .foregroundColor(.gray500)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                
                Spacer()
                
                // Buttons
                VStack(spacing: 16) {
                    Button(action: {
                        viewModel.currentScreen = .signup
                    }) {
                        Text("Sign Up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(red: 0.36, green: 0.69, blue: 0.72))
                            .cornerRadius(28)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    Button(action: {
                        viewModel.currentScreen = .login
                    }) {
                        HStack {
                            Text("Already have an account? ")
                                .foregroundColor(.gray600)
                            Text("Log In")
                                .foregroundColor(Color(red: 0.36, green: 0.69, blue: 0.72))
                        }
                        .font(.system(size: 16))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}

// Custom button style for scale animation
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Color extensions for consistent styling
extension Color {
    static let gray900 = Color(red: 0.13, green: 0.13, blue: 0.13)  // #212121
    static let gray700 = Color(red: 0.38, green: 0.38, blue: 0.38)  // #616161
    static let gray600 = Color(red: 0.45, green: 0.45, blue: 0.45)  // #737373
    static let gray500 = Color(red: 0.51, green: 0.51, blue: 0.51)  // #828282
    static let gray400 = Color(red: 0.63, green: 0.63, blue: 0.63)  // #A1A1A1
    static let gray300 = Color(red: 0.7, green: 0.7, blue: 0.7)     // #B3B3B3
    static let gray200 = Color(red: 0.88, green: 0.88, blue: 0.88)  // #E0E0E0
    static let gray100 = Color(red: 0.95, green: 0.95, blue: 0.95)  // #F3F4F6
    static let gray50 = Color(red: 0.98, green: 0.98, blue: 0.98)   // #FAFAFA
    static let spotsTeal = Color(red: 0.36, green: 0.69, blue: 0.72) // #5DB0B8
}

