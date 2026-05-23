# TODOS

Deferred work items captured during planning + reviews. Each item is self-contained so it can be picked up cold.

---

## P1 — Onboarding contacts import

**What:** Add Contacts.framework permission flow + Supabase RPC to match phone/email hashes to Spots users + new UX on onboarding screen 4 (or as new screen 5).

**Why:** "Follow the founder" is the v1 shortcut. The strategic activation lever is "follow your friends already on Spots." Founder-mode framing has high skip risk; contacts import directly addresses the empty Newsfeed problem with real social signal.

**Pros:** Strongest activation lever; addresses founder-only narcissism risk; matches what Pinterest/Strava/BeReal do post-signup.

**Cons:** Privacy framing must be careful; permission denial UX matters; needs sufficient user density to find matches (which is partly why it's deferred — wait for density to grow).

**Context:** Discussed in CEO review D3. Rejected for v1 because (a) user density is too low to guarantee matches, (b) ships v1 faster, (c) lets us see activation telemetry from v1 before investing. Decide once telemetry data arrives showing actual skip rate on screen 4.

**Effort:** Human ~1 day / CC ~2hr. Adds: Contacts.framework permission in Info.plist, new `match_contacts_to_users(phone_hashes[], email_hashes[])` Supabase RPC, permission-denied fallback UX.

**Priority:** P1. **Depends on:** v1 onboarding shipped + telemetry data collected.

---

## ~~P2 — Fix spots.city vs locality naming~~ (DONE 2026-05-19, branch `fix-city-mapping-05.19.26`)

**Shipped:** `locality TEXT` column added to `spots`; `NearbySpot.toNearbySpot()` populates locality from `addressComponents.locality.longText` with empty→nil normalization at the boundary; `Spot.displayCity` computed property centralizes the `locality ?? city` fallback rule; all display callsites (ListDetailView, SpottedByView, FeedItemCardView, ListPickerView, CuratedSpotCard, LocationGrouping.cityRows) read via `displayCity`; `CuratedSpot.displayCity(forPlaceId:dbCity:)` workaround deleted; `LocalityBackfillService` + debug-screen button re-fetches null-locality rows from Google Places (throttled 5 QPS, resumable, observable).

**Follow-up captured below as P3 — Rename spots.city → spots.region.**

---

## P3 — Rename spots.city → spots.region (DB-side cleanup)

**What:** The `spots.city` column is now load-bearing only as a region fallback for pre-backfill rows and for Travel Map grouping. Once `LocalityBackfillService` has been run against production and verified, the column should be renamed to `spots.region` to match what it actually stores. Pair with a Swift-side rename of `Spot.city` → `Spot.region`.

**Why:** Eliminates the last bit of cognitive load from the misnamed column. New contributors no longer need the "city actually means region" explanation.

**Pros:** Schema becomes fully self-documenting.

**Cons:** Touches every SELECT clause that mentions `city`, every Spot constructor, every Codable CodingKey, every SpotResponse struct in services. Larger diff than this PR, but mechanical. Needs a coordinated client + DB rollout: ship a client that reads `region` (with read-side fallback to `city` for one release) before the DB column rename, or both columns aliased via a generated/computed view.

**Context:** Surfaced 2026-05-19 alongside the locality column add. `Spot.displayCity` already abstracts this from UI callers, so the rename is contained to the data layer.

**Effort:** Human ~half day / CC ~1-2 hours. **Depends on:** locality backfill complete (verified via `SELECT count(*) FROM spots WHERE locality IS NULL`) — once that count stabilizes at "spots that genuinely have no locality" (remote attractions, etc.), the rename is safe.

**Priority:** P3.

---

## P2 — Tastemaker accounts on screen 4

**What:** Curate 3-5 NYC food/travel accounts to display alongside the founder card on onboarding screen 4.

**Why:** Diversifies the social proof; turns a 1:1 parasocial moment with the founder into a "here are voices to follow" moment. Mitigates founder-only narcissism risk.

**Pros:** More credible signal; broader feed seed; not founder-dependent.

**Cons:** Requires those accounts to exist on Spots, be opted-in, and have populated profiles (spots saved, lists, photos). Without that population, looks empty and is worse than founder-only.

**Context:** CEO review D5. Skipped because tastemaker accounts don't yet exist. Revisit once 3-5 such accounts have been seeded on the platform.

**Effort:** Human ~half day / CC ~30min once accounts exist. **Depends on:** seeded tastemaker accounts; potentially their explicit opt-in.

---

## P3 — Location pre-ask on screen 2

**What:** Before showing the bucket-list curated grid, prompt for location permission. If granted, mix curated global icons with 2-3 "Nearby gems near you" rows resolved via `PlacesAPIService`. If denied, fall back to curated-only.

**Why:** Personalizes the first activation moment — Maya in NYC sees Joe's Pizza next to the Eiffel Tower. Higher relevance.

**Pros:** More personal; Maya-ICP-aligned (NYC focus); leverages existing PlacesAPIService.

**Cons:** Asking permission early in the flow reduces grant rate; CLLocationManager prompt is intrusive; if denied the screen feels like a downgrade.

**Effort:** CC ~30min.

---

## P3 — Verbatim Maya-ICP-doc micro-copy

**What:** Replace generic onboarding headlines ("Where will you go next?") with phrasing lifted directly from the Maya ICP doc.

**Why:** Forces the app to speak Maya's exact mental-model language. Onboarding copy that mirrors how the target user actually thinks creates instant resonance.

**Effort:** CC ~15min (provide source phrases from the ICP screenshot).

---

## P3 — Newsfeed skip-recovery nudge

**What:** If a user lands on Newsfeed with `onboarding_step=null` AND zero saved spots AND zero follows, show a dismissible card: "Save your first spot" linking back to the bucket-list curated grid.

**Why:** Recovers some activation for users who skipped everything during onboarding.

**Effort:** CC ~30min. **Depends on:** v1 onboarding shipped.

---

## Future / forward concerns

- **v2 onboarding migration policy** — when v2 onboarding ships with restructured screens, users mid-flow on v1 (`onboarding_step ∈ {1,2,3,4}`) need a defined policy: snap forward to completed, restart, or interpolate. Not blocking v1.

---

## P2 — Unify image disk caches

**What:** Migrate `GooglePlacesImageView` (currently uses `SpotImageCache`, disk-keyed by `(photoReference, width)`) to load through `ImageHTTPSession.shared` and retire (or repurpose) `SpotImageCache`. Goal: one disk cache for image bytes, one budget to tune.

**Why:** After the cached-egress PR (PR #23), two parallel disk caches exist — `SpotImageCache` (Google Places) and `URLCache` inside `ImageHTTPSession.shared` (Supabase + Unsplash). They don't share storage budgets; a user scrolling between feed (Supabase URLs) and a Nearby search (Google Places) is double-counting image bytes toward the OS's low-storage attack surface. Eviction logic lives in two places. DRY violation.

**Pros:** One place to reason about image bytes, one budget. Removes ~200 lines of bespoke cache code (`SpotImageCache.swift`). Reduces "Other Documents" footprint visible to users in iOS Settings.

**Cons:** `GooglePlacesImageView` uses custom headers (`X-Goog-Api-Key`, `X-Goog-FieldMask`) on requests — those need to flow through `URLSession.dataTask` rather than `URL`-only convenience APIs. `SpotImageCache` is also keyed by photo reference + width, which doesn't map 1:1 to URL — the migration may need a normalization shim.

**Context:** Flagged in `/plan-eng-review` Issue 5 (5A) for the cached-egress PR. Deferred to keep that PR's diff right-sized.

**Effort:** Human ~half-day / CC ~1hr. Touch points: `Components/GooglePlacesImageView.swift`, `Helpers/SpotImageCache.swift`, `Services/GooglePlacesPhotoFetcher.swift`.

**Priority:** P2.

---

## P2 — Avatars bucket variants

**What:** Apply the same sized-variant scheme (thumb `_w400`, avatar `_w96`) to the `avatars` Storage bucket so avatar URLs serve a 96px-wide variant by default. Currently the bucket only stores `avatar.jpg` at upload resolution.

**Why:** `AvatarView` is rendered at 48pt by default (~96px on 2× Retina). Today it pulls the full upload-size image. Compared to spot cards this is small bytes per render, but the pattern is identical and the egress adds up across feed rendering (every feed card has ≥1 avatar).

**Pros:** Extends the same pattern that worked for spot images. Independent of the spot-images variant flow; can ship without touching `ImageStorageService.uploadSpotImage`.

**Cons:** Avatar uploads go through `ProfileService` (separate code path from spot uploads); the variant-upload + fallback-URL plumbing has to be re-wired there. Avatars also support upload from the user (vs Google Places source), so the resize step happens on user-provided bytes.

**Context:** Flagged in `/plan-eng-review` "NOT in scope" for the cached-egress PR.

**Effort:** Human ~half-day / CC ~1hr. Touch points: `Services/ProfileService.swift` (or wherever avatar upload lives), `Components/AvatarView.swift`.

**Priority:** P2.

---

## P3 — Unsplash profile cover egress

**What:** Audit profile cover image loads from Unsplash. Either pass Unsplash's `?w=<px>` resize query param when constructing URLs, or migrate profile covers to Supabase Storage with the same variant scheme as spot images.

**Why:** `ProfileView.coverSection` renders a 260pt tall full-width image. Today it loads the raw Unsplash URL at whatever resolution Unsplash returned, often 2000+ px wide. Unsplash supports `?w=800&fit=crop` for cheap server-side resizing. Not Supabase egress, but it does hit user bandwidth + memory + render time.

**Pros:** Two-line fix if we just append `?w=800&fit=crop` to existing Unsplash URLs. Lighter memory footprint per profile view.

**Cons:** `CoverPhotoPickerView` stores the raw Unsplash URL in the user's `profile.cover_photo_url` — appending the param at construction time means every read site has to apply it (or we migrate the DB column to store the param-bearing URL).

**Context:** Flagged in `/plan-eng-review` "NOT in scope" for the cached-egress PR.

**Effort:** Human ~1hr / CC ~15min. Touch points: `Views/ProfileView.swift`, `Views/CoverPhotoPickerView.swift`.

**Priority:** P3.
