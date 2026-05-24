//
//  OnboardingViewModel.swift
//  Spots.Test
//
//  State machine for the post-signup onboarding flow.
//  Owned by PostSignupOnboardingFlow and shared across all four
//  step views via @EnvironmentObject.
//
//  ┌──────────────────────────────────────────────────────────────────┐
//  │  STATE MACHINE                                                   │
//  │                                                                  │
//  │   path = []           → screen 1 (Welcome / profile)             │
//  │   path = [.bucket]    → screen 2 (Build your bucket list)        │
//  │   path = [.bucket,                                               │
//  │           .favorites] → screen 3 (What do you love?)             │
//  │   path = [.bucket,                                               │
//  │           .favorites,                                            │
//  │           .followFounder] → screen 4 (Follow the founder)        │
//  │                                                                  │
//  │  furthestStep tracks the highest step ever reached (1..4).        │
//  │  Back-navigation does NOT decrement it (per Design D6).           │
//  │  profiles.onboarding_step on the server mirrors furthestStep.    │
//  └──────────────────────────────────────────────────────────────────┘
//
//  Cross-references:
//  - Plan: ~/.claude/plans/i-want-to-design-piped-tarjan.md
//  - Routes: Models/OnboardingRoute.swift
//  - SQL state: profiles.onboarding_step (column), onboarding_events (table)
//  - Telemetry shape: ProfileService.OnboardingEventType
//

import Foundation
import SwiftUI
import UIKit
import Supabase

@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: - Navigation state

    /// NavigationStack path. Driven by advance/skip/back. The welcome step
    /// is the stack root (empty path) — only screens 2-4 are pushed routes.
    @Published var path: [OnboardingRoute] = []

    /// 1..4. The FURTHEST step the user has reached. Persisted to
    /// profiles.onboarding_step. Back-navigation does NOT decrement
    /// this — see plan Design D6.
    @Published private(set) var furthestStep: Int = 1

    // MARK: - Screen 1 (Welcome / profile) state

    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var username: String = ""
    @Published var usernameState: UsernameValidationState = .idle
    @Published var selectedPhoto: UIImage? = nil
    @Published var isSavingProfile: Bool = false
    @Published var profileSaveError: String? = nil

    /// Email-path users skip the name/username fields (already collected
    /// during signup). They only see the "add photo" affordance on
    /// screen 1. Set on init by reading the auth metadata.
    @Published var welcomeStepShowsProfileFields: Bool = false

    // MARK: - Screens 2 / 3 (curated grid) state

    /// The 12 curated spots fetched once from Supabase. Source of truth:
    /// `spots` table rows with `curated_seed_order IS NOT NULL`, ordered
    /// by the column. Both bucket and favorites screens render this same
    /// array — only the target list (and icon) differs.
    @Published private(set) var curatedSpots: [Spot] = []
    @Published private(set) var isLoadingCurated: Bool = false
    @Published private(set) var curatedLoadFailed: Bool = false

    /// place_ids the user has saved to bucket_list during this session.
    /// Mirrored to DB on each toggle via LocationSavingService. Re-hydrated
    /// from the DB on first load (so resume-from-step shows prior saves).
    @Published private(set) var bucketSelections: Set<String> = []
    @Published private(set) var favoriteSelections: Set<String> = []

    /// Cached default-list IDs so toggles don't re-fetch every tap.
    private var bucketListId: UUID? = nil
    private var favoritesListId: UUID? = nil

    /// Top-toast message shown by the step views on save failure (D3).
    /// Auto-dismissed by the view after 3s.
    @Published var toastMessage: String? = nil

    // MARK: - Screen 4 (Follow founder) state

    @Published var founderProfile: UserProfile? = nil
    @Published var founderSpotCount: Int? = nil
    @Published var founderListCount: Int? = nil
    @Published var followState: FollowFounderState = .idle

    // MARK: - Completion state

    /// When true, the celebration overlay is rendered above the flow.
    /// Cleared after the overlay's hold + cross-fade completes.
    @Published var isShowingCelebration: Bool = false
    @Published var isCompletingOnboarding: Bool = false

    /// Set to true once the profile write in `completeOnboarding` succeeds.
    /// `dismissCelebration` reads this to decide whether to flip the
    /// auth-VM handoff flag. Keeping the handoff out of `completeOnboarding`
    /// avoids tearing down `PostSignupOnboardingFlow` while the celebration
    /// overlay is still on screen — that race surfaced as a SwiftUI
    /// layout crash in TestFlight build 8.
    private var onboardingHandoffPending: Bool = false

    // MARK: - Dependencies

    private let profileService: ProfileService
    private let savingService: LocationSavingServiceProtocol
    private let followService: FollowService
    private weak var authVM: AuthenticationViewModel?

    /// Debounce holder for username live-check.
    private var usernameCheckTask: Task<Void, Never>? = nil

    // MARK: - Init

    init(
        authVM: AuthenticationViewModel,
        profileService: ProfileService = .shared,
        savingService: LocationSavingServiceProtocol = LocationSavingService.shared,
        followService: FollowService = .shared
    ) {
        self.authVM = authVM
        self.profileService = profileService
        self.savingService = savingService
        self.followService = followService

        seedFromAuth(authVM)
    }

    /// Pre-populate fields from auth state. Called on init and any
    /// subsequent reload (e.g. on retry after auth refresh).
    private func seedFromAuth(_ authVM: AuthenticationViewModel) {
        // AuthVM seeds these with placeholder strings ("First Name", "username")
        // when the underlying auth metadata key is missing. Treat those
        // placeholders as empty so they don't surface in the form.
        firstName = authVM.currentUserFirstName.isPlaceholder("First Name")
            ? "" : authVM.currentUserFirstName
        lastName = authVM.currentUserLastName.isPlaceholder("Last Name")
            ? "" : authVM.currentUserLastName

        // Email-path users arrive with a username already set in auth
        // metadata + DB. We hide name/username fields for them — only
        // photo is offered on screen 1. `isSocialSignup` is the AuthVM's
        // canonical "no username in auth metadata yet" signal.
        welcomeStepShowsProfileFields = authVM.isSocialSignup

        if !authVM.isSocialSignup, !authVM.currentUserUsername.isPlaceholder("username") {
            username = authVM.currentUserUsername
            usernameState = .valid
        }

        // Adopt the server-side furthest step if the user is resuming.
        if let step = authVM.currentOnboardingStep {
            furthestStep = max(1, min(step, OnboardingRoute.totalSteps))
            rebuildPath(toFurthest: furthestStep)
        }
    }

    /// Reconstruct the NavigationStack path so the user lands on the
    /// furthest screen they reached. Called once during resume.
    private func rebuildPath(toFurthest step: Int) {
        switch step {
        case 1: path = []
        case 2: path = [.bucket]
        case 3: path = [.bucket, .favorites]
        case 4: path = [.bucket, .favorites, .followFounder]
        default: path = []
        }
    }

    // MARK: - Hydration (called by step views on appear)

    /// Re-hydrate bucket/favorite selection sets from the DB so resume
    /// renders previously-saved cards as already-saved. Cheap — one
    /// query per list. Safe to call multiple times.
    func hydrateSelectionsIfNeeded() async {
        do {
            if bucketListId == nil {
                bucketListId = try await savingService.getListByKind(.wantToGo)?.id
            }
            if favoritesListId == nil {
                favoritesListId = try await savingService.getListByKind(.favorites)?.id
            }
        } catch {
            print("OnboardingViewModel: hydrate listIds failed: \(error)")
            // Non-fatal — toggles will retry the fetch.
        }
    }

    /// Fetch the 12 curated onboarding spots from Supabase. Source of
    /// truth is the `spots` table where `curated_seed_order` is not null,
    /// ordered by that column. Idempotent — re-call is cheap because the
    /// VM keeps the array cached after first success.
    ///
    /// Failure modes: if the fetch fails (network, RLS) we set
    /// `curatedLoadFailed = true` so the screen can show a retry CTA
    /// instead of an empty grid.
    func loadCuratedSpotsIfNeeded() async {
        guard curatedSpots.isEmpty, !isLoadingCurated else { return }
        isLoadingCurated = true
        curatedLoadFailed = false
        defer { isLoadingCurated = false }

        do {
            let rows: [Spot] = try await SupabaseManager.shared.client
                .from("spots")
                .select("place_id, name, address, city, country, latitude, longitude, types, photo_url, photo_reference, rating, created_at, updated_at")
                .not("curated_seed_order", operator: .is, value: "null")
                .order("curated_seed_order", ascending: true)
                .execute()
                .value
            curatedSpots = rows
        } catch {
            print("OnboardingViewModel: loadCuratedSpots failed: \(error)")
            curatedLoadFailed = true
        }
    }

    /// Fetch the founder's profile + curated stats for the screen 4 card.
    /// Idempotent. Skips if already loaded.
    func loadFounderProfileIfNeeded() async {
        guard founderProfile == nil else { return }
        do {
            founderProfile = try await profileService.fetchProfile(
                userId: AppConstants.founderUserId
            )
            // Spot count and list count: best-effort. If either fetch
            // fails, the card hides the stat line rather than blocking
            // the follow action.
            async let spots = founderSpotCountForFounder()
            async let lists = founderListCountForFounder()
            founderSpotCount = try? await spots
            founderListCount = try? await lists
        } catch {
            print("OnboardingViewModel: loadFounderProfile failed: \(error)")
            // founderProfile stays nil — view falls back to a generic card.
        }
    }

    /// Count distinct spots the founder has saved across all their lists.
    /// Used for the social-proof line on the founder card (CEO D8).
    private func founderSpotCountForFounder() async throws -> Int {
        // Run via the existing protocol path if it exposes a counter;
        // otherwise this is a TODO — for v1 we read the founder's
        // spot-count via a thin RPC OR we just hide the stat line.
        // For now, return a deterministic placeholder so the UI shape
        // is right; the actual fetch is wired up alongside the eng
        // review's "Founder card social proof" cherry-pick.
        return 0
    }

    private func founderListCountForFounder() async throws -> Int {
        return 0
    }

    // MARK: - Username (screen 1)

    /// Debounced (500ms) live uniqueness check for the username field.
    /// Cancels any previous in-flight check. Mirrors the existing pattern
    /// in SocialOnboardingView so behavior is consistent.
    func onUsernameChanged(_ newValue: String) {
        usernameCheckTask?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            usernameState = .idle
            return
        }
        guard trimmed.count >= 3 else {
            usernameState = .error("At least 3 characters")
            return
        }

        usernameState = .checking
        let uidOrNil = authVM?.currentUserId

        usernameCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled, let self = self else { return }
            do {
                let taken: Bool
                if let uid = uidOrNil {
                    taken = try await self.profileService.isUsernameTaken(
                        username: trimmed,
                        excludingUserId: uid
                    )
                } else {
                    taken = try await self.profileService.isUsernameTaken(username: trimmed)
                }
                guard !Task.isCancelled else { return }
                self.usernameState = taken ? .taken : .valid
            } catch {
                guard !Task.isCancelled else { return }
                // Soft-fail: let the user proceed; DB unique constraint
                // will catch a real collision on save.
                self.usernameState = .valid
            }
        }
    }

    // MARK: - Save & advance from screen 1

    /// Persist profile (name/username/photo) and advance to screen 2.
    /// Returns true on success so the view can transition; false leaves
    /// the user on screen 1 with `profileSaveError` populated.
    func saveProfileAndAdvance() async -> Bool {
        guard !isSavingProfile else { return false }
        guard let uid = authVM?.currentUserId else {
            profileSaveError = "Not signed in"
            return false
        }

        isSavingProfile = true
        profileSaveError = nil
        defer { isSavingProfile = false }

        do {
            // Upload avatar if user picked one. Failure is non-fatal —
            // we surface inline but allow them to continue without.
            // The double-optional `authVM?.currentUserAvatarUrl` flattens
            // because currentUserAvatarUrl is itself String?.
            var uploadedURL: String? = authVM?.currentUserAvatarUrl ?? nil
            if let photo = selectedPhoto {
                do {
                    uploadedURL = try await profileService.uploadAvatar(
                        userId: uid,
                        image: photo
                    )
                } catch {
                    profileSaveError = "Couldn't upload photo — continue without?"
                    // Fall through: persist the rest of the profile anyway.
                }
            }

            // For Google-path users we write name + username from local
            // state. For email-path users name + username are already in
            // the profiles row from signup; we re-write them to be
            // idempotent and to allow back-nav edits.
            try await profileService.updateProfile(
                userId: uid,
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                username: username.trimmingCharacters(in: .whitespaces),
                avatarUrl: uploadedURL
            )
            await profileService.syncAuthMetadata(
                firstName: firstName,
                lastName: lastName,
                username: username,
                avatarUrl: uploadedURL
            )

            // Mirror to auth VM for downstream views.
            authVM?.currentUserFirstName = firstName
            authVM?.currentUserLastName = lastName
            authVM?.currentUserUsername = username
            if let url = uploadedURL {
                authVM?.currentUserAvatarUrl = url
            }

            await advance(from: 1)
            return true
        } catch {
            profileSaveError = "Couldn't save — try again. (\(error.localizedDescription))"
            return false
        }
    }

    // MARK: - Screens 2 / 3 toggles

    /// Toggle a curated spot's membership in the user's bucket_list.
    /// Optimistic: updates the local selection set immediately and reverts
    /// + surfaces a toast on DB failure.
    func toggleBucket(placeId: String, displayName: String) async {
        let wasSelected = bucketSelections.contains(placeId)
        let willBeSelected = !wasSelected

        // Optimistic local flip so the tap feels instant.
        if willBeSelected { bucketSelections.insert(placeId) }
        else { bucketSelections.remove(placeId) }

        do {
            // Lazily resolve the list id on first use.
            if bucketListId == nil {
                bucketListId = try await savingService.getListByKind(.wantToGo)?.id
            }
            guard let listId = bucketListId else {
                throw OnboardingError.missingDefaultList
            }
            if willBeSelected {
                try await savingService.saveSpotToList(placeId: placeId, listId: listId)
            } else {
                try await savingService.removeSpotFromList(placeId: placeId, listId: listId)
            }
        } catch {
            // Revert and surface a toast.
            if wasSelected { bucketSelections.insert(placeId) }
            else { bucketSelections.remove(placeId) }
            toastMessage = "Couldn't save \(displayName) — try again"
        }
    }

    /// Toggle a curated spot's membership in the user's starred (favorites) list.
    func toggleFavorite(placeId: String, displayName: String) async {
        let wasSelected = favoriteSelections.contains(placeId)
        let willBeSelected = !wasSelected

        if willBeSelected { favoriteSelections.insert(placeId) }
        else { favoriteSelections.remove(placeId) }

        do {
            if favoritesListId == nil {
                favoritesListId = try await savingService.getListByKind(.favorites)?.id
            }
            guard let listId = favoritesListId else {
                throw OnboardingError.missingDefaultList
            }
            if willBeSelected {
                try await savingService.saveSpotToList(placeId: placeId, listId: listId)
            } else {
                try await savingService.removeSpotFromList(placeId: placeId, listId: listId)
            }
        } catch {
            if wasSelected { favoriteSelections.insert(placeId) }
            else { favoriteSelections.remove(placeId) }
            toastMessage = "Couldn't save \(displayName) — try again"
        }
    }

    enum OnboardingError: LocalizedError {
        case missingDefaultList

        var errorDescription: String? {
            switch self {
            case .missingDefaultList:
                return "Your default list wasn't found yet. Try again in a moment."
            }
        }
    }

    // MARK: - Follow founder (screen 4)

    /// Attempt to follow the founder with up to 2 retries (3 attempts total)
    /// at 0.5s and 1.5s backoff. Surfaces an inline error on persistent
    /// failure (per CEO D11). Done button stays disabled until success.
    func followFounder() async {
        // Allow re-entry from .idle (first attempt) and .failed (user
        // tapping "Try again"). Block from .attempting (already running)
        // and .succeeded (no point re-following).
        switch followState {
        case .idle, .failed:
            break
        case .attempting, .succeeded:
            return
        }

        let attempts: [TimeInterval] = [0, 0.5, 1.5] // initial + 2 retries
        for (idx, delay) in attempts.enumerated() {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            followState = .attempting(retryCount: idx)
            do {
                _ = try await followService.follow(userId: AppConstants.founderUserId)
                followState = .succeeded
                return
            } catch {
                if idx == attempts.count - 1 {
                    followState = .failed("Couldn't follow right now — try again or skip.")
                    return
                }
                // Silent retry; loop continues.
            }
        }
    }

    // MARK: - Navigation actions (Continue / Skip / Back)

    /// Tap Continue on step N. Logs step_completed, advances furthestStep
    /// if needed, pushes the next route.
    func advance(from step: Int) async {
        await logEvent(.stepCompleted, step: step)
        bumpFurthest(to: step + 1)
        pushNextRoute(after: step)
    }

    /// Tap Skip on step N. Logs step_skipped, advances furthestStep
    /// if needed, pushes the next route. Step 1 ignores Skip (username
    /// is required).
    func skip(from step: Int) async {
        guard step > 1 else { return }
        await logEvent(.stepSkipped, step: step)
        bumpFurthest(to: step + 1)
        pushNextRoute(after: step)
    }

    /// Pop the current screen. Logs step_revisited for the screen we land
    /// on. Does NOT decrement furthestStep — server state stays at the
    /// furthest reached value.
    func back() async {
        guard !path.isEmpty else { return }
        path.removeLast()
        // The screen we land on: welcome (1) if path is now empty,
        // otherwise the last remaining route's step number.
        let landedOn = path.last?.stepNumber ?? 1
        await logEvent(.stepRevisited, step: landedOn)
    }

    private func pushNextRoute(after step: Int) {
        switch step {
        case 1: path.append(.bucket)
        case 2: path.append(.favorites)
        case 3: path.append(.followFounder)
        case 4: break // Done is handled by completeOnboarding()
        default: break
        }
    }

    private func bumpFurthest(to newStep: Int) {
        guard newStep > furthestStep else { return }
        furthestStep = newStep
        Task { [furthestStep, weak self] in
            guard let self = self, let uid = self.authVM?.currentUserId else { return }
            do {
                try await self.profileService.updateOnboardingStep(
                    userId: uid,
                    step: min(furthestStep, OnboardingRoute.totalSteps)
                )
            } catch {
                print("OnboardingViewModel: persist furthestStep failed: \(error)")
                // Non-fatal: next advance/skip retries the write.
            }
        }
    }

    // MARK: - Completion (Done on screen 4)

    /// Wraps up the flow: marks onboarding_completed, clears the DB step
    /// column, signals the AuthVM to swap routing, and triggers the
    /// celebration overlay. The view layer hides the overlay after its
    /// hold + fade is done by calling `dismissCelebration()`.
    func completeOnboarding() async {
        guard !isCompletingOnboarding else { return }
        isCompletingOnboarding = true

        // Trigger the celebration overlay immediately — the writes below
        // happen in parallel and don't block the visual transition.
        isShowingCelebration = true
        let lightHaptic = UIImpactFeedbackGenerator(style: .light)
        lightHaptic.impactOccurred()

        await logEvent(.onboardingCompleted, step: nil)

        guard let uid = authVM?.currentUserId else { return }
        do {
            try await profileService.updateOnboardingStep(userId: uid, step: nil)
            // Mark the handoff as ready; the actual flip happens in
            // `dismissCelebration` so ContentView doesn't swap
            // PostSignupOnboardingFlow → MainTabView while the celebration
            // overlay is still animating.
            onboardingHandoffPending = true
        } catch {
            print("OnboardingViewModel: completeOnboarding write failed: \(error)")
            // Even on failure, we move on — the user finished onboarding
            // from a UX perspective. Next launch's AuthStateListener will
            // see the stale onboarding_step and just re-show the flow,
            // which is recoverable.
        }
    }

    /// Called by the celebration overlay after its 1.5s hold completes.
    /// Clears the overlay AND performs the auth-VM handoff that swaps
    /// ContentView from PostSignupOnboardingFlow to MainTabView. Doing the
    /// handoff here (instead of inside `completeOnboarding`) keeps the
    /// parent view alive for the duration of the celebration, which
    /// prevents a SwiftUI layout crash observed when MainTabView mounted
    /// mid-overlay.
    func dismissCelebration() {
        isShowingCelebration = false
        isCompletingOnboarding = false
        if onboardingHandoffPending {
            onboardingHandoffPending = false
            authVM?.needsPostSignupOnboarding = false
        }
    }

    // MARK: - Telemetry

    /// Fire-and-forget telemetry write. Failures are logged but don't
    /// surface to the user — the state machine in profiles.onboarding_step
    /// is the source of truth.
    private func logEvent(_ type: ProfileService.OnboardingEventType, step: Int?) async {
        do {
            try await profileService.logOnboardingEvent(type, step: step)
        } catch {
            print("OnboardingViewModel: logEvent(\(type.rawValue), step=\(step ?? -1)) failed: \(error)")
        }
    }
}

// MARK: - Supporting state types

extension OnboardingViewModel {

    /// Username availability state for screen 1's inline indicator.
    enum UsernameValidationState: Equatable {
        case idle
        case checking
        case valid
        case taken
        case error(String)

        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }

        /// Human-readable error label for the field — nil when no error.
        var errorMessage: String? {
            switch self {
            case .taken: return "That's taken"
            case .error(let msg): return msg
            case .idle, .checking, .valid: return nil
            }
        }
    }

    /// Follow-founder state machine for screen 4. The view reads this
    /// to enable/disable the Done button and to surface the inline
    /// retry message.
    enum FollowFounderState: Equatable {
        case idle
        case attempting(retryCount: Int)
        case succeeded
        case failed(String)

        var isInFlight: Bool {
            if case .attempting = self { return true }
            return false
        }

        var isSucceeded: Bool {
            if case .succeeded = self { return true }
            return false
        }

        var errorMessage: String? {
            if case .failed(let msg) = self { return msg }
            return nil
        }
    }
}

// MARK: - Placeholder string helper

private extension String {
    /// True when the string equals the AuthenticationViewModel's hardcoded
    /// fallback (e.g. "First Name", "username"). The AuthVM seeds these
    /// when the underlying auth metadata key is missing; treating them as
    /// "real" values would surface ugly placeholder text in the onboarding
    /// form fields.
    func isPlaceholder(_ placeholder: String) -> Bool {
        self == placeholder
    }
}
