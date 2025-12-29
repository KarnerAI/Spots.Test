//
//  LoginView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    let onLogin: () -> Void
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: {
                            viewModel.currentScreen = .welcome
                            viewModel.resetForm()
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 24))
                                .foregroundColor(.gray900)
                                .frame(width: 44, height: 44)
                        }
                        
                        Spacer()
                        
                        Text("Log In")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.gray900)
                        
                        Spacer()
                        
                        // Balance the header
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    
                    // Logo
                    Image("SpotsLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .padding(.bottom, 32)
                    
                    // Social Login Buttons
                    VStack(spacing: 12) {
                        SocialButton(
                            icon: "google",
                            text: "Continue with Google",
                            backgroundColor: .white,
                            textColor: .gray700,
                            borderColor: .gray200
                        ) {
                            viewModel.handleSocialLogin(provider: "Google", onSuccess: onLogin)
                        }
                        
                        SocialButton(
                            icon: "apple",
                            text: "Continue with Apple",
                            backgroundColor: .black,
                            textColor: .white,
                            borderColor: .clear
                        ) {
                            viewModel.handleSocialLogin(provider: "Apple", onSuccess: onLogin)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    
                    // Divider
                    HStack(spacing: 16) {
                        Rectangle()
                            .fill(Color.gray200)
                            .frame(height: 1)
                        
                        Text("or log in with email")
                            .font(.system(size: 14))
                            .foregroundColor(.gray500)
                        
                        Rectangle()
                            .fill(Color.gray200)
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    
                    // Form
                    VStack(spacing: 16) {
                        // Email Field
                        FormField(
                            label: "Email",
                            placeholder: "Enter your email",
                            text: Binding(
                                get: { viewModel.formData.email },
                                set: { viewModel.formData.email = $0 }
                            ),
                            icon: "envelope",
                            error: nil,
                            isSecure: false,
                            keyboardType: .emailAddress
                        )
                        
                        // Password Field
                        PasswordField(
                            label: "Password",
                            placeholder: "Enter your password",
                            text: Binding(
                                get: { viewModel.formData.password },
                                set: { viewModel.formData.password = $0 }
                            ),
                            showPassword: $viewModel.showPassword
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    
                    // Forgot Password
                    HStack {
                        Spacer()
                        Button(action: {
                            // Handle forgot password
                            print("Forgot password tapped")
                        }) {
                            Text("Forgot Password?")
                                .font(.system(size: 14))
                                .foregroundColor(.spotsTeal)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    
                    // Submit Button
                    Button(action: {
                        Task {
                            await viewModel.handleLoginSubmit {
                                onLogin()
                            }
                        }
                    }) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Log In")
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.spotsTeal)
                        .cornerRadius(28)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(viewModel.isLoading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    
                    // Error Message
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                    }
                    
                    // Switch to Sign Up
                    Button(action: {
                        viewModel.currentScreen = .signup
                        viewModel.resetForm()
                    }) {
                        HStack {
                            Text("Don't have an account? ")
                                .foregroundColor(.gray600)
                            Text("Sign Up")
                                .foregroundColor(.spotsTeal)
                        }
                        .font(.system(size: 16))
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }
}

