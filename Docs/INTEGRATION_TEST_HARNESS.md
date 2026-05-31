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

## Applying the existing SQL migrations to local Supabase

The historical migrations in `Spots.Test/SQL/` aren't yet wired into `supabase/migrations/`. PR-A doesn't need them (the smoke test only exercises Supabase Auth). PR-B will wire them up.

Two paths when you get there:

- **Recommended (PR-B):** copy/rename the existing `SQL/*.sql` files into `supabase/migrations/` with timestamp prefixes the CLI expects (`YYYYMMDDHHMMSS_<name>.sql`). Then `supabase db reset` becomes a one-command reset.
- **Manual / one-off:** use `Docs/scripts/apply-migrations-to-test.sh` with `DB_URL` set to the local Postgres connection string (`postgresql://postgres:postgres@127.0.0.1:54322/postgres`). Works against both local and cloud, depending on the DB_URL.

---

## What this harness deliberately does NOT do (yet)

- **CI wiring.** Out of scope for PR-A per D16 ("small, low-risk, independently reviewable"). When CI lands, the GitHub Actions workflow installs Supabase CLI, runs `supabase start`, and the tests use a CI-provided `secrets.json` written to the runner's home directory.
- **Per-test schema reset.** Comes in PR-B alongside the activity-model migrations. The current model is "tests use a fresh auth user per test; orphaned table rows survive across tests." PR-B will add truncation helpers.
- **Migration wiring.** See above — comes in PR-B.

---

## Files

| File | Purpose |
|---|---|
| `Spots.TestTests/Integration/IntegrationTestConfig.swift` | Loads `~/.config/spots-test-harness/secrets.json`. Skips test if missing. Refuses to run if URL matches prod. |
| `Spots.TestTests/Integration/SupabaseIntegrationTestCase.swift` | Base `XCTestCase`. Builds `anonClient` + `serviceClient`. Provides `signInAsFreshUser()` + tearDown user cleanup. |
| `Spots.TestTests/Integration/SupabaseConnectionSmokeTest.swift` | One proof-of-life test exercising sign-up + sign-in + admin delete. |
| `supabase/` (created by `supabase init`) | Local-dev config (`config.toml`) + `migrations/` folder the CLI watches. |
| `Docs/scripts/apply-migrations-to-test.sh` | `psql`-based migration applier. Takes a `DB_URL` env var; works against either local or a future cloud test project. |
