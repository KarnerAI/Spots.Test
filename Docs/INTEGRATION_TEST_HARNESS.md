# Supabase Integration Test Harness

This harness lets us write tests that hit a **real** Postgres + Supabase stack, but running locally via Docker — not against the prod project. It's the foundation the Newsfeed Activity Model redesign tests sit on (see `0. Strategy/spots-newsfeed-activity-model.html` §07, D11 + D16).

The harness lives entirely in `Spots.TestTests/Integration/` and is built so:

- Tests that need the harness inherit from `SupabaseIntegrationTestCase`.
- Tests that don't (the existing pure-logic suites) keep using Swift Testing as today.
- If the local secrets file isn't present, the integration tests **skip** (`XCTSkip`) — they don't fail. New machines without the harness configured can still run unit tests normally.

---

## Why local Supabase via Docker (not the cloud)

We evaluated three approaches in the eng-review follow-up:

1. **Dedicated cloud test Supabase project** — Free-tier slot, no Docker, but blocked by Supabase's 2-project per-org limit.
2. **Supabase Pro** — $25/mo, removes the quota; rejected as premature for current scale.
3. **Local Supabase via Docker** — chosen. $0 forever, no vendor quota, faster tests, no network dependency.

**Switching paths later is trivial**: only `supabase_url` and the keys in `secrets.json` change. The Swift code is identical.

---

## One-time setup

### 1. Install Docker Desktop

- Download from <https://www.docker.com/products/docker-desktop/>. Pick "Mac — Apple Silicon" for M1/M2/M3/M4 chips; Intel otherwise.
- Drag Docker to Applications. Launch it. Accept defaults. Skip Docker Hub sign-in.
- Wait for the 🐳 whale icon in the menu bar to stop animating.
- **Cap disk usage:** Settings → Resources → Virtual disk limit → **30 GB**. Optional: cap Memory at 4 GB and CPUs at 4 so Docker doesn't compete with Xcode.

### 2. Install the Supabase CLI

```bash
brew install supabase/tap/supabase
supabase --version   # verify install
```

If Homebrew isn't installed yet, get it from <https://brew.sh> first (~5 min).

### 3. Initialize Supabase in the repo

From the repo root (`Spots.Test/`):

```bash
supabase init
# Answer N to the VS Code / IntelliJ settings prompts.
```

This creates a `supabase/` directory holding `config.toml` and a `migrations/` folder. Commit it — future contributors get the same local config.

### 4. Start the local stack

```bash
supabase start
```

The first run downloads ~500 MB of Docker images (~3–5 min). Subsequent runs are ~30 sec. When it finishes, the CLI prints a credentials block. On recent CLI versions (2.x+) it looks like:

```
Project URL:  http://127.0.0.1:54321
Publishable:  sb_publishable_...
Secret:       sb_secret_...
```

Older CLI versions printed `anon key` / `service_role key` instead — those are the equivalents. Either way, the Swift SDK accepts both formats.

If you lose this output, run `supabase status` any time to re-print it. Open <http://127.0.0.1:54323> as a sanity check — that's the local Supabase Studio dashboard.

### 5. Create the secrets file

The secrets file lives outside the repo so it can never be committed by accident. Same path as the cloud path would have used; the values just point at localhost.

```bash
mkdir -p ~/.config/spots-test-harness
$EDITOR ~/.config/spots-test-harness/secrets.json
```

Paste:

```json
{
  "supabase_url": "http://127.0.0.1:54321",
  "supabase_anon_key": "<paste Publishable key here>",
  "supabase_service_role_key": "<paste Secret key here>"
}
```

The JSON keys in `secrets.json` are local to this harness — they map to the SDK's `supabaseKey` argument regardless of whether the underlying credential is `sb_publishable_*` (newer) or a JWT-format `anon` key (older). Same for `supabase_service_role_key` → `sb_secret_*` or JWT-format `service_role`.

These local keys are not real secrets — every Supabase CLI install uses the same defaults, and the local stack only listens on `127.0.0.1`. The harness still refuses to run if `supabase_url` ever matches the prod URL, so misconfiguration can't nuke prod data.

### 6. Run the smoke test

In Xcode: pick the `Spots.Test` scheme, hit **Cmd+U**, find `SupabaseConnectionSmokeTest` in the Test navigator (`Spots.TestTests/Integration/`). It should pass in ~1 sec.

If you see `Skipped: Integration test secrets not found at …` — Step 5 didn't land.

If you see `Could not connect to host` — `supabase start` isn't running.

---

## Day-to-day workflow

| Action | Command |
|---|---|
| Run integration tests | Ensure Docker Desktop is up, then `supabase start` if needed. Run tests in Xcode. |
| Check stack status | `supabase status` |
| Reset DB to a clean state | `supabase db reset` (re-runs every file in `supabase/migrations/`) |
| Stop the stack (reclaim memory) | `supabase stop` |
| Quit Docker entirely | 🐳 whale icon → Quit Docker Desktop |

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

## Applying the SQL migrations to local Supabase

**As of PR-B**, every historical SQL file in `Spots.Test/SQL/` is wired into `supabase/migrations/` with sequential `20260101_*` timestamp prefixes, plus the 6 new PR-B activity-model migrations (`20260101005000_*` through `20260101005500_*`). `supabase db reset` is a one-command full reset:

```bash
cd Spots.Test/
supabase db reset
```

This drops the local database, re-applies all 45 migrations in order, and restarts the auth/storage containers. Takes ~30 seconds. Run it before any integration test session if you've been mucking with rows manually.

Four ordering fixes were applied during the wiring vs. raw git commit dates — see the `chore(db): wire 39 SQL/ files` commit message for the specifics. Three `upsert_spot` updaters gained a `DROP FUNCTION IF EXISTS prior_signature` prefix so the trailing `COMMENT ON FUNCTION` stays unambiguous as overloads stack.

The original `Docs/scripts/apply-migrations-to-test.sh` is still around for one-off applications against cloud (e.g. prod). For local-stack work, use `supabase db reset` instead.

---

## Cross-user test patterns (PR-B)

The PR-B activity-model tests introduced `FeedActivityIntegrationTestCase`, a subclass of `SupabaseIntegrationTestCase` that adds multi-user lifecycle helpers. The pattern for tests that need an actor + a follower:

```swift
final class MyTest: FeedActivityIntegrationTestCase {
    func test_actorSavesAndFollowerSees() async throws {
        let primary  = try await signInPrimaryUser(prefix: "actor")
        let follower = try await createAdditionalUser(prefix: "follower")
        try await makeFollowAccepted(follower: follower.id, followee: primary.id)

        // ... actor's writes via anonClient (currently signed in as primary) ...

        try await signInAnon(as: follower)
        // ... follower's reads via anonClient (now signed in as follower) ...
    }
}
```

Both users are deleted in tearDown via the service-role client; CASCADE FKs handle profiles / lists / spot_list_items / feed_activities cleanup.

---

## Foot-gun: service-role UPDATEs via supabase-swift

Discovered empirically during PR-B test development: the supabase-swift PostgrestClient's `.from("...").update(...).eq(...).execute()` against the local CLI's newer `sb_secret_*` service-role key format **silently no-ops** — returns success but doesn't actually update the row. The same PATCH via `curl` with both `apikey` AND `Authorization: Bearer` headers set works correctly.

Reads via the service client work fine. Inserts via the service client work fine. Only UPDATE is affected, and only via the SDK on the local stack.

`FeedActivityIntegrationTestCase` works around this with a direct `URLSession` PostgREST helper (`serviceRoleRequest`) for the few setup-time mutations that need service-role bypass. New tests that need to mutate rows as the service role should use this helper, not the SDK's `.update()`.

This may resolve in a future supabase-swift release. If you re-discover it, don't waste time second-guessing — go around the SDK.

---

## What this harness deliberately does NOT do (yet)

- **CI wiring.** Out of scope per D16 ("small, low-risk, independently reviewable"). When CI lands, the GitHub Actions workflow installs Supabase CLI, runs `supabase start`, and the tests use a CI-provided `secrets.json` written to the runner's home directory.
- **Per-test schema reset.** Each test creates fresh auth users (and the user-deletion CASCADE handles their app data). For tests that need a fully-clean slate across the whole DB, run `supabase db reset` manually before the test run.

---

## Files

| File | Purpose |
|---|---|
| `Spots.TestTests/Integration/IntegrationTestConfig.swift` | Loads `~/.config/spots-test-harness/secrets.json`. Skips test if missing. Refuses to run if URL matches prod. |
| `Spots.TestTests/Integration/SupabaseIntegrationTestCase.swift` | Base `XCTestCase`. Builds `anonClient` + `serviceClient`. Provides `signInAsFreshUser()` + tearDown user cleanup. |
| `Spots.TestTests/Integration/SupabaseConnectionSmokeTest.swift` | One proof-of-life test exercising sign-up + sign-in + admin delete. |
| `supabase/` (created by `supabase init`) | Local-dev config (`config.toml`) + `migrations/` folder the CLI watches. |
| `Docs/scripts/apply-migrations-to-test.sh` | `psql`-based migration applier. Takes a `DB_URL` env var; works against either local or a future cloud test project. |
