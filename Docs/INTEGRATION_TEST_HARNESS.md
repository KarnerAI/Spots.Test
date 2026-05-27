# Supabase Integration Test Harness

This harness lets us write tests that hit a **real** Supabase project (a dedicated test project, never prod). It's the foundation the Newsfeed Activity Model redesign tests sit on (see `0. Strategy/spots-newsfeed-activity-model.html` §07.3, D11 + D16).

The harness lives entirely in `Spots.TestTests/Integration/` and is built so:

- Tests that need the harness inherit from `SupabaseIntegrationTestCase`.
- Tests that don't (the existing pure-logic suites) keep using Swift Testing as today.
- If the local secrets file isn't present, the integration tests **skip** (`XCTSkip`) — they don't fail. New machines without the harness configured can still run unit tests normally.

---

## One-time setup

### 1. Create the dedicated test Supabase project

1. Go to <https://supabase.com/dashboard>.
2. Click **New project**. Use the same organization as prod.
3. Name: `spots-test` (or similar — never reuse the prod project).
4. Database password: generate a strong one, save in 1Password.
5. Region: same as prod.
6. Pricing plan: **Free** is fine. The project pauses after a week idle and wakes automatically when tests run.
7. Wait ~2 minutes for provisioning.

### 2. Configure the project for testing

Once the test project is up, change two settings so tests can sign users up cleanly:

- **Authentication → Providers → Email:**
  - Enable **Email** provider.
  - **Disable** "Confirm email" (we want auto-confirm — otherwise sign-up returns no session and the smoke test fails).
- **Authentication → URL Configuration:**
  - Add `http://localhost` to the redirect URLs (avoids occasional warnings during sign-up).

### 3. Apply the existing SQL migrations

The smoke test only exercises Supabase Auth, so it works on an empty project. But PR-B and beyond expect the full schema. Apply migrations either:

- **Via the Supabase dashboard SQL editor** — paste each file from `Spots.Test/SQL/` in chronological order, oldest first. ~25 files; takes 10 minutes.
- **Via the script** (`Docs/scripts/apply-migrations-to-test.sh`) — requires `psql`. Run once after grabbing the test project's connection string from **Project Settings → Database**.

If you're only landing PR-A (the harness itself), you can skip this step until PR-B opens.

### 4. Create the local secrets file

In **Project Settings → API**, copy three values:

- **Project URL** (e.g. `https://abcd1234.supabase.co`)
- **anon public** key (long JWT)
- **service_role secret** key (long JWT — keep private; this can bypass RLS)

Then create the file (outside the repo, so it can never be committed):

```bash
mkdir -p ~/.config/spots-test-harness
$EDITOR ~/.config/spots-test-harness/secrets.json
```

Paste:

```json
{
  "supabase_url": "https://YOUR-TEST-PROJECT.supabase.co",
  "supabase_anon_key": "eyJ...",
  "supabase_service_role_key": "eyJ..."
}
```

The harness refuses to run if `supabase_url` matches the prod URL — belt-and-suspenders so a misconfigured secrets file can't nuke prod data.

### 5. Run the smoke test

In Xcode: pick the `Spots.Test` scheme, hit **Cmd+U**, find `SupabaseConnectionSmokeTest` in the Test navigator. It should pass in ~1–2 seconds (one network round trip to the test project's `/auth/v1/signup` + `/auth/v1/token`).

If you see `Skipped: Integration test secrets not found at …` — the secrets file is missing or unreadable. Re-check step 4.

If you see a failure mentioning "Email signups are disabled" or similar — re-check step 2.

---

## Writing new integration tests

```swift
import XCTest
@testable import Spots_Test

final class MyNewIntegrationTest: SupabaseIntegrationTestCase {
    func test_somethingAgainstRealSupabase() async throws {
        try await signInAsFreshUser()
        // anonClient is now signed in as a brand-new user; serviceClient is
        // available for admin/cleanup ops. The user is deleted in tearDown.

        let result = try await anonClient
            .from("user_lists")
            .select()
            .execute()

        // ... assertions ...
    }
}
```

Lifecycle guarantees:

- Each test gets a fresh user (`signInAsFreshUser()` returns the session).
- `tearDown` deletes that user via the service-role client.
- App-level table cleanup (truncating spots, lists, etc.) is **not** in PR-A — it lands in PR-B alongside the activity-model migrations that introduce most of the relevant tables.

---

## What this harness deliberately does NOT do

These were called out in the eng review (§07.3, §07.4) but split out:

- **Local Supabase via Docker.** Considered, rejected: extra dependency for a non-technical founder. Switching later is a swap-the-URL change.
- **CI wiring.** Out of scope for PR-A per D16 ("small, low-risk, independently reviewable"). When CI lands, secrets move to GitHub Actions secrets and `IntegrationTestConfig` reads them via env vars.
- **Schema reset between tests.** Comes in PR-B alongside the migrations that touch `feed_activities`, `spot_list_items`, etc.
- **Test data fixtures.** Will grow case-by-case as PR-B and later PRs need them.

---

## Files

| File | Purpose |
|---|---|
| `Spots.TestTests/Integration/IntegrationTestConfig.swift` | Loads `~/.config/spots-test-harness/secrets.json`. Skips test if missing. |
| `Spots.TestTests/Integration/SupabaseIntegrationTestCase.swift` | Base `XCTestCase`. Builds `anonClient` + `serviceClient`. Provides `signInAsFreshUser()` + tearDown user cleanup. |
| `Spots.TestTests/Integration/SupabaseConnectionSmokeTest.swift` | One proof-of-life test exercising sign-up + sign-in + admin delete. |
| `Docs/scripts/apply-migrations-to-test.sh` | Applies the `SQL/` migrations to the test project in chronological order. Needed before PR-B-style tests. |
