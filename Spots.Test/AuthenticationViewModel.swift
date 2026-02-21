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
    @Published var isCheckingUsername = false
    @Published var isUsernameAvailable = false
    @Published var passwordError = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAuthenticated: Bool = false

    /// Current user profile from auth metadata (for profile screen). Fallbacks: "First Name", "Last Name", "username".
    @Published var currentUserFirstName: String = "First Name"
    @Published var currentUserLastName: String = "Last Name"
    @Published var currentUserUsername: String = "username"
    /// Public URL of the user's profile avatar (from auth metadata or profiles table). nil = no photo set.
    @Published var currentUserAvatarUrl: String? = nil
    /// The authenticated user's UUID, set after session is established.
    @Published var currentUserId: UUID? = nil

    @Published var formData = FormData()

    private let supabase = SupabaseManager.shared.client
    /// Task handle for debounced username validation — cancelled on each new keystroke.
    private var usernameValidationTask: Task<Void, Never>?
    /// Task handle for the auth state listener (lives for the ViewModel's lifetime).
    private var authListenerTask: Task<Void, Never>?

    init() {
        listenForAuthStateChanges()
    }

    deinit {
        authListenerTask?.cancel()
    }
    
    struct FormData {
        var username: String = ""
        var firstName: String = ""
        var lastName: String = ""
        var email: String = ""
        var password: String = ""
        var confirmPassword: String = ""
    }
    
    func handleUsernameChange(_ username: String) {
        formData.username = username
        usernameError = ""
        isUsernameAvailable = false

        // Cancel any in-flight check
        usernameValidationTask?.cancel()

        guard username.count >= 3 else {
            isCheckingUsername = false
            return
        }

        isCheckingUsername = true
        usernameValidationTask = Task {
            // 500ms debounce
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            do {
                let taken = try await ProfileService.shared.isUsernameTaken(username: username)
                guard !Task.isCancelled else { return }
                isCheckingUsername = false
                if taken {
                    usernameError = "This username is already taken"
                } else {
                    isUsernameAvailable = true
                }
            } catch {
                guard !Task.isCancelled else { return }
                isCheckingUsername = false
                // Silently fail — don't block signup for a network hiccup
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

            if response.session == nil {
                // Email confirmation is required — the account was created successfully.
                // Show a clear success message; the user must confirm before logging in.
                // Default lists will be created by the auth state listener after login.
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Check your email and click the confirmation link, then log in."
                }
                return
            }

            // Auto-confirm is enabled — session is already live.
            // Auth state listener handles isAuthenticated, profile loading, and default lists.
            await MainActor.run {
                isLoading = false
                onSuccess()
            }
        } catch let authError as AuthError where authError == .sessionMissing {
            // Safety net: show a friendly message if sessionMissing leaks to the outer catch.
            await MainActor.run {
                isLoading = false
                errorMessage = "Check your email and click the confirmation link, then log in."
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
            _ = try await supabase.auth.signIn(
                email: formData.email,
                password: formData.password
            )

            // Auth state listener handles isAuthenticated, profile loading, and default lists.
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

    // MARK: - Session Management

    /// Subscribes to Supabase auth state changes for the lifetime of this ViewModel.
    /// Handles initial session, sign-in, sign-out, and token refresh events reactively.
    private func listenForAuthStateChanges() {
        authListenerTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in self.supabase.auth.authStateChanges {
                guard !Task.isCancelled else { return }

                switch event {
                case .initialSession, .signedIn, .tokenRefreshed:
                    if let session {
                        self.loadProfileFromUser(session.user)
                        self.isAuthenticated = true
                        if event == .signedIn {
                            // Ensure default lists exist for every new sign-in.
                            // Covers email/password login, post-confirmation login, and future social login.
                            // ensureDefaultListsForCurrentUser() is idempotent so safe to call each time.
                            Task {
                                do {
                                    try await LocationSavingService.shared.ensureDefaultListsForCurrentUser()
                                } catch {
                                    print("AuthenticationViewModel: ensureDefaultLists failed: \(error)")
                                }
                            }
                        }
                    } else {
                        // initialSession with nil session → no stored session
                        self.isAuthenticated = false
                        self.clearCurrentUserProfile()
                    }
                case .signedOut:
                    self.isAuthenticated = false
                    self.currentScreen = .welcome
                    self.clearCurrentUserProfile()
                    self.resetForm()
                default:
                    break
                }
            }
        }
    }

    /// Load first name, last name, username (and optional avatar_url) from auth user metadata.
    private func loadProfileFromUser(_ user: User) {
        func stringFromAnyJSON(_ value: AnyJSON?) -> String? {
            guard case .string(let s)? = value, !s.isEmpty else { return nil }
            return s
        }
        let meta = user.userMetadata
        currentUserId = user.id
        currentUserFirstName = stringFromAnyJSON(meta["first_name"]) ?? "First Name"
        currentUserLastName = stringFromAnyJSON(meta["last_name"]) ?? "Last Name"
        currentUserUsername = stringFromAnyJSON(meta["username"]) ?? "username"
        currentUserAvatarUrl = stringFromAnyJSON(meta["avatar_url"])
    }

    /// Refresh profile fields from the current session (call after saving Edit Profile).
    func refreshProfile() {
        Task {
            do {
                let session = try await supabase.auth.session
                await MainActor.run { loadProfileFromUser(session.user) }
            } catch {
                print("AuthenticationViewModel: refreshProfile failed: \(error)")
            }
        }
    }

    private func clearCurrentUserProfile() {
        currentUserId = nil
        currentUserFirstName = "First Name"
        currentUserLastName = "Last Name"
        currentUserUsername = "username"
        currentUserAvatarUrl = nil
    }
    
    func signOut() {
        Task {
            do {
                try await supabase.auth.signOut()
                // Auth state listener will handle isAuthenticated, profile clearing, and navigation
            } catch {
                print("Error signing out: \(error)")
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

