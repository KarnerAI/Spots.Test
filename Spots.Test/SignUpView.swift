//
//  SignUpView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

struct SignUpView: View {
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
                        
                        Text("Sign Up")
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
                    
                    // Social Sign Up Buttons
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
                        
                        Text("or sign up with email")
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
                        // Username Field
                        FormField(
                            label: "Username",
                            placeholder: "Choose a username",
                            text: Binding(
                                get: { viewModel.formData.username },
                                set: { viewModel.handleUsernameChange($0) }
                            ),
                            icon: "person",
                            error: viewModel.usernameError,
                            isSecure: false
                        )
                        
                        // First Name Field
                        FormField(
                            label: "First Name",
                            placeholder: "Enter your first name",
                            text: Binding(
                                get: { viewModel.formData.firstName },
                                set: { viewModel.formData.firstName = $0 }
                            ),
                            icon: nil,
                            error: nil,
                            isSecure: false
                        )
                        
                        // Last Name Field
                        FormField(
                            label: "Last Name",
                            placeholder: "Enter your last name",
                            text: Binding(
                                get: { viewModel.formData.lastName },
                                set: { viewModel.formData.lastName = $0 }
                            ),
                            icon: nil,
                            error: nil,
                            isSecure: false
                        )
                        
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
                            placeholder: "Create a password",
                            text: Binding(
                                get: { viewModel.formData.password },
                                set: { viewModel.formData.password = $0 }
                            ),
                            showPassword: $viewModel.showPassword
                        )
                        
                        // Confirm Password Field
                        PasswordField(
                            label: "Confirm Password",
                            placeholder: "Confirm your password",
                            text: Binding(
                                get: { viewModel.formData.confirmPassword },
                                set: {
                                    viewModel.formData.confirmPassword = $0
                                    viewModel.passwordError = ""
                                }
                            ),
                            showPassword: $viewModel.showConfirmPassword,
                            error: viewModel.passwordError
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    
                    // Submit Button
                    Button(action: {
                        Task {
                            await viewModel.handleSignupSubmit {
                                onLogin()
                            }
                        }
                    }) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Sign Up")
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
                    .padding(.bottom, 16)
                    
                    // Error Message
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                    }
                    
                    // Terms
                    Text("By signing up, you agree to our Terms of Service and Privacy Policy")
                        .font(.system(size: 12))
                        .foregroundColor(.gray500)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                    
                    // Switch to Login
                    Button(action: {
                        viewModel.currentScreen = .login
                        viewModel.resetForm()
                    }) {
                        HStack {
                            Text("Already have an account? ")
                                .foregroundColor(.gray600)
                            Text("Log In")
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

// Social Login Button Component
struct SocialButton: View {
    let icon: String
    let text: String
    let backgroundColor: Color
    let textColor: Color
    let borderColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if icon == "google" {
                    // Google icon
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                        Text("G")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.blue)
                    }
                } else if icon == "apple" {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
                
                Text(text)
                    .font(.system(size: 16))
                    .foregroundColor(textColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(borderColor, lineWidth: borderColor == .clear ? 0 : 1)
            )
            .cornerRadius(25)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// Form Field Component
struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String?
    let error: String?
    let isSecure: Bool
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.gray700)
            
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(.gray400)
                        .frame(width: 20)
                }
                
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .font(.system(size: 16))
                        .foregroundColor(.gray900)
                } else {
                    TextField(placeholder, text: $text)
                        .font(.system(size: 16))
                        .foregroundColor(.gray900)
                        .keyboardType(keyboardType)
                        .autocapitalization(keyboardType == .emailAddress ? .none : .words)
                }
            }
            .padding(.horizontal, icon != nil ? 16 : 16)
            .padding(.vertical, 14)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(error != nil ? Color.red : Color.gray200, lineWidth: 1)
            )
            .cornerRadius(12)
            
            if let error = error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.leading, 4)
            }
        }
    }
}

// Password Field Component
struct PasswordField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @Binding var showPassword: Bool
    var error: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.gray700)
            
            HStack {
                Image(systemName: "lock")
                    .font(.system(size: 20))
                    .foregroundColor(.gray400)
                    .frame(width: 20)
                
                if showPassword {
                    TextField(placeholder, text: $text)
                        .font(.system(size: 16))
                        .foregroundColor(.gray900)
                } else {
                    SecureField(placeholder, text: $text)
                        .font(.system(size: 16))
                        .foregroundColor(.gray900)
                }
                
                Button(action: {
                    showPassword.toggle()
                }) {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 20))
                        .foregroundColor(.gray400)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(error != nil ? Color.red : Color.gray200, lineWidth: 1)
            )
            .cornerRadius(12)
            
            if let error = error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.leading, 4)
            }
        }
    }
}

