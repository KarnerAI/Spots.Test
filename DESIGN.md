# Spots — Design System

> Source of truth for visual and interaction design. Read this before touching any UI. If you deviate, document why. Aim for "wouldn't even notice it" — the design serves the content, not itself.

---

## 1. Product context

- **What it is**: location-saving iOS app. Save, organize, and share real-world places.
- **Who it's for** (ICP): **Maya** — 31, Brooklyn, taste-driven traveler. Saves places on Instagram and Google Maps today but loses them in the graveyard.
- **Positioning**: "Save the places you actually want to go." Daily-use intimacy, not occasional-use planning.
- **Real competitors**: iPhone Notes file, Instagram Saved folder, Google Maps starred lists.
- **The strategic frame**: see `/Users/shaon/Library/CloudStorage/GoogleDrive-hussain@karnerblu.com/Shared drives/6. Spots 2.0/0. Strategy/spots-strategy-brief.html`.

## 2. Aesthetic direction — Modern + Utility

Picked 2026-05-23 over Warm/Personal (A) and Confident/Editorial (B).

**Inspiration**: Linear, Notion 3.0, Things 3. Clean, system-driven, restrained. Gets out of the way. Calm surface hierarchy. Trust earned through consistency and respect for the user's content, not visual flourish.

**Mood in three sentences:**
> Spots feels like a well-built tool. Crisp white space, clear hierarchy, real photography that makes places look like themselves. Nothing decorative. Nothing in the way.

**Why this direction:**
- Maya doesn't want a craft-fair journal feel (A) — that's precious and gets in the way of fast daily save behavior.
- She doesn't want an editorial magazine feel (B) — that's beautiful for one-time browsing but tiring for daily use.
- She wants something that respects her saves and gets out of the way. Modern utility = the spotlight is on the places, not the chrome.

**What this means in practice:**
- Real photography is the visual identity. Type and color are restrained so photos sing.
- One accent color (cool blue). No secondary accent.
- Sentence-case labels. No tracked all-caps. No serif headlines.
- Generous whitespace, tight typography.
- Minimal decoration. No gradients, no shadows except subtle elevation on floating elements.

## 3. Typography

**Family**: [Geist](https://fonts.google.com/specimen/Geist) — Vercel's modern grotesque sans. One family, multiple weights.

```css
@import url('https://fonts.googleapis.com/css2?family=Geist:wght@300;400;500;600;700&display=swap');
```

**Weights in use**:
- 700 (Bold) — wordmark only
- 600 (SemiBold) — display titles, screen heads, primary CTAs
- 500 (Medium) — labels, secondary CTAs, active tab states
- 400 (Regular) — body, descriptions, list rows
- 300 (Light) — reserved, currently unused

**Type scale** (px):

| Token | Size | Line-height | Letter-spacing | Use |
|---|---|---|---|---|
| `display-xl` | 52 | 1.0 | -0.04em | Welcome hero wordmark |
| `display-lg` | 32 | 1.05 | -0.02em | Profile name, list-detail hero title |
| `display-md` | 26 | 1.05 | -0.02em | Screen heads (Spots wordmark, Spot Detail title) |
| `display-sm` | 19 | 1.2 | -0.02em | Section titles ("Lists", "The List", "Save to lists") |
| `body-lg` | 17 | 1.45 | 0 | Featured body text (rare) |
| `body` | 14 | 1.45 | 0 | Default body, card text, descriptions |
| `body-sm` | 13 | 1.4 | 0 | Meta, addresses, dense list rows |
| `caption` | 12 | 1.45 | 0 | Captions, timestamps, secondary metadata |
| `label` | 11 | 1 | 0 | Tab bar labels, small metadata |
| `micro` | 10 | 1 | 0 | Numbered list prefixes (use `ui-monospace` font) |

**Italics**: never. Geist's italic is rarely needed; sentence-case labels remove the need.

**Wordmark**: `Spots` in Geist Bold 700, -4% letter-spacing, `--text` color. Never italicized, never colored except in the Welcome hero where it sits in `--text`.

## 4. Color

CSS variables (use these tokens exclusively — never raw hex):

| Token | Hex | Use |
|---|---|---|
| `--bg` | `#FFFFFF` | App background |
| `--surface` | `#FFFFFF` | Cards, sheets, elevated surfaces (same as bg for flatness; differentiate via border) |
| `--text` | `#0A0A0A` | Primary text |
| `--text-muted` | `#6B6B6B` | Secondary text, captions, meta |
| `--text-subtle` | `#9B9B9B` | Tertiary, timestamps, ghost prompts |
| `--accent` | `#2563EB` | Primary actions, links, active state, focus |
| `--accent-soft` | `#EFF4FE` | Accent-tinted backgrounds (category pills, picker context strip) |
| `--border` | `#EEEEEE` | Hairline dividers, default card borders |
| `--border-strong` | `#D1D5DB` | Input focus, stronger separation when needed |

**Semantic**:
- Success: `#16A34A`
- Warning: `#D97706`
- Error: `#DC2626`
- Info: same as `--accent`

**Rules**:
- Only ONE accent color. Resist adding a secondary accent.
- White on white is fine — differentiate via `--border`, not bg color.
- Status colors only for status (errors, warnings). Not for category coding.

**Dark mode** (future, Phase 2+): invert `--bg`/`--text`, reduce `--accent` saturation 15%, keep accent hue at 217°. Don't tackle this until after launch.

## 5. Spacing

**Base unit**: 4px. All spacing snaps to multiples of 4.

**Scale**: `4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 56 / 80`

**Density**: comfortable (not compact, not airy).

**Side gutters on phone screens**:
- 16px for full-width content (most lists, sheets)
- 24px for hero / display content (profile top, list-detail hero, card outer padding)

**Vertical rhythm**: section dividers use 16-24px above + 8-12px below the section label.

## 6. Layout

- **Grid**: single column on phone. No multi-column except horizontal-scroll lists (profile list cards).
- **Max content width**: edge-to-edge (393px iPhone width, no inset).
- **Tab bar height**: 78px (includes safe-area).
- **Border-radius scale**:
  - `radius-sm`: 6px — inputs, chip filters, small thumbs, pills
  - `radius-md`: 10px — cards, primary buttons, sheets top edge in middle states
  - `radius-lg`: 14px — featured cards (rare)
  - `radius-xl`: 16-18px — bottom sheets top edge in resting state
  - `radius-full`: 9999px — avatars, follow buttons, pill tab groups

## 7. Components

### 7.1 Wordmark
- Text: `Spots`
- Font: Geist Bold 700, 26-52px depending on context, -4% letter-spacing
- Color: `--text` (not accent — restrained)

### 7.2 Tab bar (bottom navigation)
- Height: 78px
- Background: `--surface` with 1px top `--border`
- 3 tabs: Feed, Explore, Profile
- Icon (22px stroke 1.8) + label (Geist Medium 11px, sentence case, NO tracking)
- Active state: icon stroke + label both `--accent`, label becomes Geist SemiBold

### 7.3 Cards
- Background: `--surface`
- Border: 1px `--border`
- Border-radius: 10px (`radius-md`)
- Padding: 16px default
- Margin between cards: 14px

### 7.4 Buttons
- **Primary CTA**:
  - Background: `--accent`
  - Text: white, Geist SemiBold 15px
  - Border-radius: 10px (`radius-md`)
  - Padding: 14px vertical, full width unless contextual
- **Secondary**:
  - Background: `--surface`
  - Border: 1.5px `--border`
  - Text: `--text`, Geist SemiBold 14px
  - Same radius / padding
- **Ghost / link**:
  - Text-only, `--accent`, Geist Medium 13px
- **Destructive**: same shape as primary, background `#DC2626`

### 7.5 Pills (category labels, filter chips, segmented controls)
- **Category pill** (e.g., "Attractions"): `--accent` text only, no background, Geist Medium 11px, sentence case
- **Active filter chip**: `--accent-soft` background, `--accent` text, 6px radius, 8px×4px padding
- **Inactive filter chip**: no background, `--text-muted` text
- **Segmented control** (e.g., Spots / Friends): `--accent-soft` track, white pill with subtle shadow for active

### 7.6 List rows
- Padding: 12px vertical, 24px horizontal (or 16px in sheets)
- Divider: 1px `--border` between rows (no divider when row has a thumbnail)
- Thumbnail: 44-72px square, 6-8px radius
- Tap area: full row

### 7.7 Bottom sheets
- Background: `--surface`
- Top corners: 16-18px radius
- Drag handle: 36×4px, `--border` color, 12px from top edge, centered
- Backdrop: 50% black with 2px blur on map screens
- Sheet header: Geist SemiBold 19px, sentence case
- Sheet enters from bottom, 320ms ease-out

### 7.8 Forms / inputs
- Background: `--surface`
- Border: 1px `--border`, 1.5px `--border-strong` on focus
- Border-radius: 10px
- Padding: 12px×14px
- Text: 14px Geist Regular, color `--text`
- Placeholder: `--text-subtle`

### 7.9 Avatars
- Circular (`radius-full`)
- Sizes: 24px (proof avatars), 32-40px (inline), 72-84px (profile hero)
- Fallback: solid `--accent-soft` background with initials in `--accent`

### 7.10 Map (Explore)
- Stylized illustrated map, NOT raw Google Maps tile screenshots
- Light gray land (`#F3F4F6`), light blue water (`#DBEAFE`)
- Pin: 16-22px filled circle in `--accent`, 3px white border, soft shadow
- Selected pin: same + pulsing accent ring (1.6s loop)

## 8. Iconography

- **Default**: SF Symbols (system iOS icons)
- **Stroke width**: 1.8px for line icons; 2.2px only for very small icons (search field clear, etc.)
- **Style**: outline for "off" / inactive state; filled for "on" / active state
- **Custom SVG**: only when SF Symbols doesn't carry the meaning (rare)
- **Bookmark**: SF `bookmark` (outline) → `bookmark.fill` when saved
- **Heart**: SF `heart` → `heart.fill`
- **Map pin**: SF `mappin.circle` or custom (matching §7.10)

## 9. Photography

- **Real photography for all place imagery.** Never illustrations, never generic stock.
- **Aspect ratios**:
  - List hero / cover: 16:10 or 4:3
  - Spot thumbnail (rows): 1:1
  - Card image (in newsfeed): 4:3 or 5:4
  - Avatar: 1:1
- **Treatment**: full color, no filters, no opacity overlays except 0-55% black gradient on hero text overlays (top-down)
- **Sources** (in order of preference):
  1. User-uploaded photos (Spot Detail user notes)
  2. Google Places Photos API (canonical place imagery)
  3. Unsplash (curated seed content for editorial lists)
  4. Placeholder: `--accent-soft` square (only when no photo available)

## 10. Motion

- **Approach**: minimal-functional. Only animations that aid comprehension.
- **Easing**:
  - Enter (sheet opens, card appears): `ease-out` (cubic-bezier(0, 0, 0.2, 1))
  - Exit (sheet dismisses, fades): `ease-in` (cubic-bezier(0.4, 0, 1, 1))
  - Move (tab switch, scroll-driven): `ease-in-out`
- **Duration**:
  - Micro (toggle, tap feedback, ripple): 100ms
  - Short (sheet open, fade, hover): 200ms
  - Medium (screen push, sheet expand): 320ms
  - Long (rare; major state change): 500ms
- **No bouncy springs.** No decorative scroll-linked animations. No parallax.

## 11. Voice & copy

- **Labels**: sentence case. Always.
  - ✅ "Save to lists"
  - ❌ "SAVE TO LISTS"
- **Buttons**: verb-first, short. "Save", "Share", "Get started", "Save list".
- **Tone**: utility-first, clear, no marketing fluff.
  - ✅ "Save list"
  - ❌ "✨ Save to your favorites!"
- **Numbers**: bold (Geist SemiBold or Bold), not display weights. Timestamps use `ui-monospace` for tabular alignment.
- **Empty states**: a clear primary action + a single short explanation. No mascots, no jokes.
  - "No saved spots yet" + "Save your first" button.

## 12. The "would I notice?" test

A finished Spots screen should feel invisible to design. If a user pauses to think about the chrome, the design has failed. Test every new screen against:

1. Does the photography sing, or does the chrome distract from it?
2. Could I remove 20% of the visible elements without losing function?
3. If I cover the wordmark, is this clearly a tool (not a toy)?
4. Is the primary action obvious within 1 second of looking?

If any answer is no, simplify.

---

## Approved mockups (reference)

The chosen direction was rendered as live HTML mockups across 10 screens:

- File: `~/.gstack/projects/SpotsTest/designs/html-mockups-20260523-125847/index.html`
- Direction D column shows the canonical visual interpretation of every screen.
- Treat these as design intent, not pixel-perfect specs. When in doubt, match the spirit (calm, restrained, photo-forward) over the letter.

## Decisions log

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-23 | Adopted **Direction D — Modern + Utility** over A (Warm) and B (Editorial) | Best fit for Maya's daily-use intimacy; lowest decorative risk; respects content (real photography) over chrome; ages best |
| 2026-05-23 | Geist as the single typeface | One family covers display + body + UI; modern grotesque pairs naturally with photography; available on Google Fonts |
| 2026-05-23 | Cool blue (`#2563EB`) as the single accent | Trustworthy, system-aligned, restrained; supports utility positioning |
| 2026-05-23 | Sentence case for all labels | Editorial all-caps tracking (Direction B) was rejected to keep the calm utility feel |
| 2026-05-23 | No serif headlines | Geist throughout, no Fraunces/Instrument Serif. Photography carries any "warmth"; type stays disciplined |

## Open questions (revisit when relevant)

- Dark mode color treatment (Phase 2+)
- Whether to introduce a second accent for paid/premium features
- Custom map style (Mapbox styling for the Explore tab) — needs design exploration when Phase 1.5 starts
