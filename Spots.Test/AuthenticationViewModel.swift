//
//  AuthenticationViewModel.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI
import Supabase

enum AuthScreen {
    case welcome
    case signup
    case login
}

class AuthenticationViewModel: ObservableObject {
    @Published var currentScreen: AuthScreen = .welcome
    @Published var showPassword = false
    @Published var showConfirmPassword = false
    @Published var usernameError = ""
    @Published var passwordError = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    @Published var formData = FormData()
    
    private let supabase = SupabaseManager.shared.client
    
    struct FormData {
        var username: String = ""
        var firstName: String = ""
        var lastName: String = ""
        var email: String = ""
        var password: String = ""
        var confirmPassword: String = ""
    }
    
    // Mock taken usernames for validation
    private let takenUsernames = ["neena", "john", "sarah", "mike", "admin", "test"]
    
    func handleUsernameChange(_ username: String) {
        formData.username = username
        usernameError = ""
        
        // Validate username
        if username.count >= 3 {
            if takenUsernames.contains(username.lowercased()) {
                usernameError = "This username is already taken"
            }
        }
    }
    
    // MARK: - Email/Password Sign Up
    func handleSignupSubmit(onSuccess: @escaping () -> Void) async {
        // Validate passwords match
        if formData.password != formData.confirmPassword {
            await MainActor.run {
                passwordError = "Passwords do not match"
            }
            return
        }
        
        if !usernameError.isEmpty {
            return
        }
        
        // Validate required fields
        guard !formData.email.isEmpty,
              !formData.password.isEmpty,
              !formData.username.isEmpty else {
            await MainActor.run {
                errorMessage = "Please fill in all required fields"
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            passwordError = ""
        }
        
        do {
            // Sign up with Supabase
            let response = try await supabase.auth.signUp(
                email: formData.email,
                password: formData.password,
                data: [
                    "username": AnyJSON.string(formData.username),
                    "first_name": AnyJSON.string(formData.firstName),
                    "last_name": AnyJSON.string(formData.lastName)
                ]
            )
            
            await MainActor.run {
                isLoading = false
                onSuccess()
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Email/Password Login
    func handleLoginSubmit(onSuccess: @escaping () -> Void) async {
        // Validate required fields
        guard !formData.email.isEmpty,
              !formData.password.isEmpty else {
            await MainActor.run {
                errorMessage = "Please enter your email and password"
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let response = try await supabase.auth.signIn(
                email: formData.email,
                password: formData.password
            )
            
            await MainActor.run {
                isLoading = false
                onSuccess()
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Social Login (Placeholder for now)
    func handleSocialLogin(provider: String, onSuccess: @escaping () -> Void) {
        // Mock social login - we'll implement Apple Sign In later
        print("Login with \(provider)")
        // For now, just show a message
        Task {
            await MainActor.run {
                errorMessage = "\(provider) sign in will be available soon"
            }
        }
    }
    
    func resetForm() {
        formData = FormData()
        showPassword = false
        showConfirmPassword = false
        usernameError = ""
        passwordError = ""
        errorMessage = nil
    }
}

