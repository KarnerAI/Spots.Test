#!/usr/bin/env node
//
// backfill-spots-city-country.mjs
//
// Backfills `city`, `country`, and `rating` on `public.spots` rows that have
// NULL values. Reads each row's stored `place_id`, calls Google Place Details
// for canonical address components + rating, and PATCHes the row via Supabase
// REST.
//
// One-shot, idempotent: only writes the columns that are NULL on a row, so
// re-running is safe and does not overwrite manual corrections.
//
// Why this script exists:
//   `Services/LocationSavingService.swift` historically saved spots without
//   `country`/`rating`, and `getSpotsInList` etc. dropped both columns from
//   the SELECT. Once those reads are fixed (ProfileView "Your Travel Map"
//   countries tab), we still need to fill the historical NULLs in the table
//   so the user actually sees countries / ratings. After this runs, the
//   Travel Map will populate from real data.
//
// Run (default dry-run, prints diffs without writing):
//   cp Scripts/.env.example Scripts/.env  # fill in three keys
//   node --env-file=Scripts/.env Scripts/backfill-spots-city-country.mjs
//
// Apply for real:
//   node --env-file=Scripts/.env Scripts/backfill-spots-city-country.mjs --apply
//
// Requires Node 18+ (built-in fetch) and 20.6+ for --env-file; on older
// Node, source the .env manually before running.
//
// Required env (see Scripts/.env.example):
//   SUPABASE_URL                e.g. https://xmriyge.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY   service_role JWT (NOT the anon key — RLS
//                               normally blocks cross-user writes)
//   GOOGLE_PLACES_API_KEY       a key with Places API (New) enabled
//
// Optional env:
//   BACKFILL_LIMIT      cap rows processed in one run (default: 500)
//   BACKFILL_RATE_MS    delay between Google calls in ms (default: 60)

const APPLY = process.argv.includes("--apply");
const VERBOSE = process.argv.includes("--verbose");

const {
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
  GOOGLE_PLACES_API_KEY,
  BACKFILL_LIMIT,
  BACKFILL_RATE_MS,
} = process.env;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !GOOGLE_PLACES_API_KEY) {
  console.error(
    "Missing required env. Need SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GOOGLE_PLACES_API_KEY.\n" +
      "Copy Scripts/.env.example to Scripts/.env and fill it in."
  );
  process.exit(1);
}

const LIMIT = Number(BACKFILL_LIMIT ?? 500);
const RATE_MS = Number(BACKFILL_RATE_MS ?? 60);

const sb = (path, init = {}) =>
  fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
      ...(init.headers ?? {}),
    },
  });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Fetch up to `limit` rows missing any of the three target fields.
 */
async function fetchTargetRows(limit) {
  // PostgREST `or=()` syntax: any of city, country, rating is NULL.
  const filter = "or=(city.is.null,country.is.null,rating.is.null)";
  const cols = "place_id,name,city,country,rating";
  const res = await sb(`spots?select=${cols}&${filter}&limit=${limit}`);
  if (!res.ok) {
    throw new Error(`Supabase fetch failed: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

/**
 * Pull canonical city + country + rating from Google Place Details.
 * Returns `{ city, country, rating }` with `undefined` for anything missing.
 */
async function fetchPlaceDetails(placeId) {
  const fields = ["address_components", "rating"].join(",");
  const url =
    `https://maps.googleapis.com/maps/api/place/details/json` +
    `?place_id=${encodeURIComponent(placeId)}` +
    `&fields=${fields}` +
    `&key=${GOOGLE_PLACES_API_KEY}`;
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Google Places HTTP ${res.status}`);
  }
  const body = await res.json();
  if (body.status === "NOT_FOUND" || body.status === "INVALID_REQUEST") {
    return { status: body.status };
  }
  if (body.status !== "OK") {
    throw new Error(
      `Google Places status=${body.status} ${body.error_message ?? ""}`
    );
  }
  const components = body.result?.address_components ?? [];
  // Locality is the canonical "city". Common fallbacks for non-US places:
  //   sublocality_level_1 / postal_town / administrative_area_level_2.
  const findComponent = (...types) =>
    components.find((c) => types.some((t) => c.types?.includes(t)));
  const city =
    findComponent("locality")?.long_name ??
    findComponent("postal_town")?.long_name ??
    findComponent("sublocality_level_1")?.long_name ??
    findComponent("administrative_area_level_2")?.long_name;
  const country = findComponent("country")?.long_name;
  const rating = body.result?.rating;
  return { status: "OK", city, country, rating };
}

/**
 * Diff what should be written: only columns currently NULL on the row.
 */
function buildPatch(row, details) {
  const patch = {};
  if (row.city == null && details.city) patch.city = details.city;
  if (row.country == null && details.country) patch.country = details.country;
  if (row.rating == null && typeof details.rating === "number") {
    patch.rating = details.rating;
  }
  return patch;
}

async function applyPatch(placeId, patch) {
  const res = await sb(
    `spots?place_id=eq.${encodeURIComponent(placeId)}`,
    { method: "PATCH", body: JSON.stringify(patch) }
  );
  if (!res.ok) {
    throw new Error(`PATCH failed: ${res.status} ${await res.text()}`);
  }
}

async function main() {
  console.log(`Mode: ${APPLY ? "APPLY (writes)" : "DRY-RUN (no writes)"}`);
  console.log(`Fetching up to ${LIMIT} rows with at least one NULL field...`);

  const rows = await fetchTargetRows(LIMIT);
  console.log(`Found ${rows.length} candidate rows.\n`);

  let updated = 0;
  let skippedNoChange = 0;
  let skippedNotFound = 0;
  let failed = 0;

  for (const row of rows) {
    try {
      const details = await fetchPlaceDetails(row.place_id);
      if (details.status === "NOT_FOUND" || details.status === "INVALID_REQUEST") {
        skippedNotFound++;
        if (VERBOSE) {
          console.log(`  - ${row.place_id} (${row.name ?? "?"}) → ${details.status}`);
        }
      } else {
        const patch = buildPatch(row, details);
        const keys = Object.keys(patch);
        if (keys.length === 0) {
          skippedNoChange++;
          if (VERBOSE) {
            console.log(`  = ${row.place_id} (${row.name ?? "?"}) — Google had no extra fields`);
          }
        } else {
          const summary = keys
            .map((k) => `${k}=${JSON.stringify(patch[k])}`)
            .join(", ");
          console.log(`  ${APPLY ? "✓" : "→"} ${row.name ?? row.place_id}: ${summary}`);
          if (APPLY) await applyPatch(row.place_id, patch);
          updated++;
        }
      }
    } catch (err) {
      failed++;
      console.error(`  ✗ ${row.place_id} (${row.name ?? "?"}): ${err.message}`);
    }
    await sleep(RATE_MS);
  }

  console.log("");
  console.log(`Done. ${APPLY ? "Wrote" : "Would write"} ${updated} rows.`);
  console.log(`  no-change: ${skippedNoChange}`);
  console.log(`  not-found: ${skippedNotFound}`);
  console.log(`  failed:    ${failed}`);
  if (!APPLY && updated > 0) {
    console.log(`\nRe-run with --apply to actually write.`);
  }
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
