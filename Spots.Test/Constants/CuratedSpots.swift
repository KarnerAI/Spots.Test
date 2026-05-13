//
//  CuratedSpots.swift
//  Spots.Test
//
//  Hardcoded 12-spot starter set surfaced on onboarding screens 2 (bucket
//  list) and 3 (favorites). The mix is tuned for the Maya ICP — NYC-based
//  aspirational planner — and balances local resonance, global icons, and
//  food-as-destination picks. See the post-signup onboarding plan for the
//  curation rationale.
//
//  ┌──────────────────────────────────────────────────────────────────┐
//  │ ORDERING MATTERS — the 2-column grid renders top-to-bottom.       │
//  │ #1 (Joe's Pizza) is intentionally first to land NYC resonance     │
//  │ immediately. #12 (Pierre Hermé) closes by pairing with #5 to make │
//  │ "a Paris trip" feel plannable, not just iconic.                   │
//  └──────────────────────────────────────────────────────────────────┘
//
//  Place IDs were resolved on 2026-05-12 by saving each spot through
//  the app's PlacesAPIService and copying the resulting place_id rows
//  out of the spots table. Photos + addresses + lat/lng / types /
//  city / country / rating live in the Supabase spots table — this
//  Swift file is documentation-only after the curated_seed_order
//  migration runs (see SQL/add_curated_seed_order.sql). The
//  onboarding screens query the DB for full data; this file just
//  pins the ordered set so reviewers can see the curation at a
//  glance.
//

import Foundation

struct CuratedSpot: Identifiable, Hashable {
    /// Stable identifier — same value as `googlePlaceId` so we can use
    /// either as the dictionary key without ambiguity.
    let id: String
    let googlePlaceId: String
    let name: String
    let city: String
    let photoURL: URL?
    let category: Category

    enum Category: String, Hashable {
        case food
        case landmark
        case nature
        case travel
    }

    init(
        googlePlaceId: String,
        name: String,
        city: String,
        photoURL: URL? = nil,
        category: Category
    ) {
        self.id = googlePlaceId
        self.googlePlaceId = googlePlaceId
        self.name = name
        self.city = city
        self.photoURL = photoURL
        self.category = category
    }
}

extension CuratedSpot {
    /// Returns the display city for a curated spot's place_id, falling back to
    /// the provided DB-stored value when the place_id isn't in the curated set.
    ///
    /// Why this exists: the `spots.city` column in Supabase is misnamed — it
    /// stores `administrative_area_level_1` (state/region/province) per
    /// NearbySpot.swift:253-259. That's intentional for the Travel Map's
    /// region-grouping feature but produces awkward labels on the onboarding
    /// cards ("Île-de-France" instead of "Paris", "Lazio" instead of "Rome").
    ///
    /// Until the broader `locality` vs `region` schema fix lands
    /// (see TODOS.md "Fix spots.city vs locality naming"), `CuratedSpotCard`
    /// calls this helper to swap in the cleaner display value for the 12
    /// curated rows. All other spots app-wide keep current behavior.
    ///
    /// Lookup is keyed by `googlePlaceId` (the array's `id`), making the
    /// static `all` array the authoritative override source.
    static func displayCity(forPlaceId placeId: String, dbCity: String?) -> String {
        all.first { $0.googlePlaceId == placeId }?.city ?? dbCity ?? ""
    }
}

extension CuratedSpot {
    /// Curated set for onboarding screens 2 and 3. Both screens render the
    /// same array; the difference is which list the SaveSpotButton writes
    /// to (bucket vs starred).
    ///
    /// To refresh place IDs and photo URLs:
    ///   1. Save the desired spots through the app (custom list keeps them
    ///      isolated from your real bucket-list).
    ///   2. Query `spots` table in Supabase, pull each row's `place_id`.
    ///   3. Update the entries below and re-run the curated_seed_order
    ///      migration with the new place_ids.
    ///
    /// Slot 7 (Tsukiji), 9 (Oia), 12 (Pierre Hermé) were swapped during
    /// /plan-design-review on 2026-05-11 — see plan file for rationale.
    static let all: [CuratedSpot] = [
        // ── NYC local resonance (1-4) ────────────────────────────────
        CuratedSpot(
            googlePlaceId: "ChIJ8Q2WSpJZwokRQz-bYYgEskM",
            name: "Joe's Pizza",
            city: "New York",
            category: .food
        ),
        CuratedSpot(
            googlePlaceId: "ChIJCar0f49ZwokR6ozLV-dHNTE",
            name: "Katz's Delicatessen",
            city: "New York",
            category: .food
        ),
        CuratedSpot(
            googlePlaceId: "ChIJK3vOQyNawokRXEa9errdJiU",
            name: "Brooklyn Bridge",
            city: "New York",
            category: .landmark
        ),
        CuratedSpot(
            googlePlaceId: "ChIJmSvG_ZFZwokRTOFeiLXzkmA",
            name: "Carbone",
            city: "New York",
            category: .food
        ),

        // ── Global iconic (5-9) ──────────────────────────────────────
        CuratedSpot(
            googlePlaceId: "ChIJLU7jZClu5kcR4PcOOO6p3I0",
            name: "Eiffel Tower",
            city: "Paris",
            category: .landmark
        ),
        CuratedSpot(
            googlePlaceId: "ChIJrRMgU7ZhLxMRxAOFkC7I8Sg",
            name: "Colosseum",
            city: "Rome",
            category: .landmark
        ),
        CuratedSpot(
            googlePlaceId: "ChIJWZ2zdav40YURFvsU_rU3uaE",
            name: "Pujol",
            city: "Mexico City",
            category: .food
        ),
        CuratedSpot(
            googlePlaceId: "ChIJk_s92NyipBIRUMnDG8Kq2Js",
            name: "Sagrada Família",
            city: "Barcelona",
            category: .landmark
        ),
        CuratedSpot(
            googlePlaceId: "ChIJcWA7cPFuARURkSKaZwj5mxk",
            name: "Petra",
            city: "Jordan",
            category: .travel
        ),

        // ── Nature counter-balance (10-11) ───────────────────────────
        CuratedSpot(
            googlePlaceId: "ChIJe6hluYWP2oAR4p3rOqftdxk",
            name: "Joshua Tree National Park",
            city: "California",
            category: .nature
        ),
        CuratedSpot(
            googlePlaceId: "ChIJsQi20Aldd1MRLrdJuq17Zx0",
            name: "Lake Louise",
            city: "Banff",
            category: .nature
        ),

        // ── Paris pairing closer (12) ────────────────────────────────
        CuratedSpot(
            googlePlaceId: "ChIJlz74sd5x5kcRJKnMHqMw2x8",
            name: "Le Comptoir du Relais",
            city: "Paris",
            category: .food
        )
    ]
}
