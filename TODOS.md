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

## P2 — Fix spots.city vs locality naming

**What:** The `spots.city` column actually stores `administrative_area_level_1` (state/region/province), not the literal city/locality. Add a proper `locality` column (Paris, Rome, Mexico City) alongside the existing `city`-which-is-actually-region. Update `NearbySpot.toNearbySpot()` to populate both. Audit display callsites and prefer `locality` for city-like contexts, keep `region` for grouping contexts (Travel Map, profile region groupings).

**Why:** The current naming is confusing for new contributors and produces awkward labels in the UI for international spots ("Île-de-France" under Eiffel Tower, "Lazio" under the Colosseum, "Catalunya" under Sagrada Família). For US spots it works because the state name often coincides with the user's mental "city" anchor. The misnaming was deliberate (per `NearbySpot.swift:253-259` comment) — the column was repurposed to drive the Travel Map's region grouping — but it never got renamed afterwards.

**Pros:** Display labels become honest. Anyone reading the schema understands what each column holds. Onboarding cards (and any future feature) can use the right value without per-feature overrides.

**Cons:** Schema migration touches every existing `spots` row (backfill `locality` from address parsing). Display callsites across the app need an audit: feed hero card subtitle, list grouping views (the "Île-de-France" header from the screenshot that surfaced this), Travel Map. Risk of mid-migration UI states.

**Context:** Surfaced during onboarding implementation 2026-05-12 when curated cards showed "Île-de-France" under Eiffel Tower and "Lazio" under Colosseum. Worked around in v1 via `CuratedSpot.displayCity(forPlaceId:dbCity:)` (see `Spots.Test/Constants/CuratedSpots.swift`) — this TODO removes the workaround and fixes the root cause.

**Effort:** Human ~1-2 days / CC ~4-6 hours. Steps: (1) add `locality TEXT` column to spots, (2) backfill from `address_components.locality.longText` via a one-off script that re-parses existing rows or re-fetches via Google Places, (3) update `NearbySpot.toNearbySpot()` to populate `locality`, (4) audit display callsites and choose per-context which column to render, (5) remove the `CuratedSpot.displayCity` workaround.

**Priority:** P2. **Depends on:** v1 onboarding shipped (don't block on this); decide on rename strategy (keep `city` as region alias vs full rename with read-side compatibility).

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
