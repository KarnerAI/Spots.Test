#!/usr/bin/env node
//
// backfill-spots-city-country.mjs
//
// Backfills `city`, `country`, `rating`, `types`, and `photo_reference` on
// `public.spots` rows that have NULL/empty values. Reads each row's stored
// `place_id`, calls Google Place Details once per row to get canonical
// address components + rating + types + first photo reference, and PATCHes
// the row via Supabase REST.
//
// `photo_url` (the Supabase-Storage-cached image) is intentionally out of
// scope here — that's `PhotoBackfillService`'s job. Once `photo_reference`
// is filled, that service has what it needs to upload the image.
//
// One-shot, idempotent: only writes the columns that are NULL/empty on a
// row, so re-running is safe and does not overwrite manual corrections.
//
// Why this script exists:
//   The iOS save path eagerly enriches new saves via Place Details. But the
//   spots table has many legacy rows from before that code shipped, plus a
//   few half-NULL rows from `PlacesAPIService.upsertSpotWithPhoto` which
//   used to insert nearby-search cache entries with only photo + address
//   data (fixed elsewhere in this PR). This script catches up the historical
//   pile so the Profile "Your Footprint" section, the Explore card metadata,
//   and category-based filtering all see complete data.
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
 * Fetch up to `limit` rows missing any of the five target fields.
 */
async function fetchTargetRows(limit) {
  // PostgREST `or=()` syntax: any of the enrichment columns is NULL.
  // Note: photo_url is intentionally excluded — that's the Supabase-Storage-
  // cached image, populated by PhotoBackfillService, not by Place Details.
  const filter =
    "or=(city.is.null,country.is.null,rating.is.null,types.is.null,photo_reference.is.null)";
  const cols = "place_id,name,city,country,rating,types,photo_reference";
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
  // Single Place Details call covers all five enrichment fields. `types` and
  // `photos` cost the same SKU as `address_components` so we may as well
  // ask for everything in one round-trip.
  const fields = ["address_components", "rating", "types", "photos"].join(",");
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
  // Match the iOS save path's shape: a single-element array containing the
  // primary normalized category. LocationSavingViewModel writes
  // `[details.category.lowercased().replacingOccurrences(of: " ", with: "_")]`,
  // and Google's `types[0]` is already in that lowercase_underscore shape
  // (e.g. "restaurant", "tourist_attraction"), so we mirror it directly.
  // Trade-off: drops the secondary types Google returns. Stable, internally
  // consistent with new saves, and re-pullable later if we ever want richer
  // types — see PR description.
  const primaryType = body.result?.types?.[0];
  const types = primaryType ? [primaryType] : undefined;
  // First photo's reference token. Cheap to grab; lets the existing photo
  // pipeline (Google → Supabase Storage upload) catch up downstream without
  // this script having to handle binary uploads.
  const photoReference = body.result?.photos?.[0]?.photo_reference;
  return { status: "OK", city, country, rating, types, photoReference };
}

/**
 * Diff what should be written: only columns currently NULL/empty on the row.
 *
 * `types` is treated as missing when the row's existing array is null or
 * empty — a stale `[]` shouldn't block the backfill from filling it.
 */
function buildPatch(row, details) {
  const patch = {};
  if (row.city == null && details.city) patch.city = details.city;
  if (row.country == null && details.country) patch.country = details.country;
  if (row.rating == null && typeof details.rating === "number") {
    patch.rating = details.rating;
  }
  const rowTypesEmpty = row.types == null || row.types.length === 0;
  if (rowTypesEmpty && details.types && details.types.length > 0) {
    patch.types = details.types;
  }
  if (row.photo_reference == null && details.photoReference) {
    patch.photo_reference = details.photoReference;
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
