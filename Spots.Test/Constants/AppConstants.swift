//
//  AppConstants.swift
//  Spots.Test
//
//  App-wide static configuration values. Keep this file small and
//  intentional — anything that needs to vary by environment belongs in
//  Config.swift (which reads from Info.plist / env vars), not here.
//

import Foundation

enum AppConstants {
    /// Hussain's Spots account user ID. Used as the default "Follow the
    /// founder" suggestion on the post-signup onboarding screen 4. If the
    /// founder account is ever rotated or deleted, the onboarding follow
    /// step will surface its inline error path (D11 retry-with-backoff)
    /// instead of silently failing.
    static let founderUserId: UUID = UUID(uuidString: "7c0ecf5d-b4b1-47a1-bf8c-9161b8ebccea")!
}
