# Scripts

One-off operational scripts for the Spots iOS project. Not part of the app
build — most engineers never touch these.

## `backfill-spots-city-country.mjs`

Fills in `city`, `country`, and `rating` on `public.spots` rows that have NULL
values, using each row's stored `place_id` against the Google Places API.

Why: older saves wrote spots without those columns, so the Profile "Your
Travel Map" Countries tab was empty even after the iOS-side fetch bug was
fixed. This script gets historical data caught up. Idempotent — only writes
columns that are currently NULL.

### One-time setup

```bash
cd Spots.Test/Scripts
cp .env.example .env
# fill in SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GOOGLE_PLACES_API_KEY
```

The service role key is in Supabase project settings → API → Project API keys
→ `service_role`. **Never commit it.** `.env` is gitignored.

### Run

Dry-run (default — prints what it would change, makes no writes):

```bash
node --env-file=Scripts/.env Scripts/backfill-spots-city-country.mjs
```

Apply for real:

```bash
node --env-file=Scripts/.env Scripts/backfill-spots-city-country.mjs --apply
```

Useful flags:

- `--verbose` — also print rows skipped (e.g. Google `NOT_FOUND`).
- `BACKFILL_LIMIT=N` env — cap rows touched in one run (default 500).
- `BACKFILL_RATE_MS=N` env — delay between Google calls (default 60ms).
  Bump if you hit `OVER_QUERY_LIMIT`.

### Requirements

- Node **18+** for built-in `fetch`.
- Node **20.6+** to use `--env-file`. On older Node, source the env manually:
  `set -a && source Scripts/.env && set +a && node Scripts/backfill...`.

### Cost

Google Place Details runs ~$0.017 per call. The current spots table has
~180 rows; a full backfill is roughly $3 in API spend. Re-runs are cheaper
because already-filled rows are skipped server-side via the `is.null` filter.

## `validate-info-plist-keys.sh`

Validates that the app's required Info.plist keys are present. Run during
release prep. Self-documenting — read the script.
