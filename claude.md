# Hello, World

A world map where people drop a colored dot at their GPS location once a day
with a short message. Map resets at midnight UTC. No algorithm, no followers,
no likes.

## Stack
- Single index.html
- Leaflet.js for the map (initial view + maxBounds + popup edge
  behavior in the Map section below)
- Supabase JS for the backend (database only — realtime subscriptions
  removed in favor of 30s polling; see Supabase section below)
- **Cloudflare Worker** in front of Supabase for the boot read path
  (edge-cached aggregator at `dropadot-cache.thinksubliminal.workers.dev/loadAll`;
  see Cloudflare Worker section)
- MyMemory API for translation (free, CORS, no signup — see Translation
  section below)
- localStorage for one-dot-per-day client check, language preference,
  and personal-mute list
- Continent attribution for flares derives from
  `continentFromLatLng()` — see Continent classification section

## Map
- Leaflet map, `worldCopyJump: true`, `zoomSnap: 0` (fractional
  zoom for fluid trackpad/pinch), `maxZoom: 9`.
- `INITIAL_ZOOM`: **2.8 desktop, 1.9 mobile**. `INITIAL_CENTER`:
  `[20, 10]` (Atlantic-with-Europe-on-the-right framing). The
  initial view is set in one shot via the L.map `center`/`zoom`
  options — do NOT chain a second `setView` on boot or markers
  visibly jump between the two frames.
- `maxBounds: [[-VERT_BOUND, -HORIZ_BOUND], [VERT_BOUND, HORIZ_BOUND]]`
  with `maxBoundsViscosity: 1.0`. `VERT_BOUND = 85.05` clamps the
  view away from the poles; `HORIZ_BOUND = 1e6` is effectively
  unbounded so worldCopyJump still works horizontally.
- **Popup edge behavior**: dot and flare popups both use
  `autoPan: true`, `autoPanPadding: [20, 20]`, `keepInView: false`.
  This gives the same subtle "nudge" when a popup peeks past the
  left/right/bottom edge.
- The TOP edge is a special case. Popups open above their marker,
  so a top-edge popup wants the map to pan north to fit. With
  `maxBoundsViscosity: 1.0` clamping the visible top to `VERT_BOUND`
  at low zoom, autoPan returns zero movement and the popup stays
  clipped. **Both dot and flare click handlers compensate** by
  detecting the top-region case (top 25% of viewport, zoom < 5)
  and doing an explicit smooth `setView` (+0.5 zoom, 10% upward
  offset, 0.45s ease, NO bounce — `setView` not `flyTo`) before
  opening. Same fix in two places; if you change the threshold,
  change both.
- Both dot and flare click handlers also trigger the same `setView`
  for an outer-corner case at very low zoom (corner 18%, zoom < 3.5)
  where the popup is too big to fit even with autoPan's max shift.
- Both handlers additionally always pan-before-open on mobile
  (<768px): the marker is brought to ~65% down the screen so the
  popup opens cleanly above. Below `MIN_ZOOM=5` this is a single-
  motion `flyTo` (zoom + offset together); at or above it, a
  faster `panTo` with no zoom change.
- Dot popup widths, flare popup widths, and the Heard panel
  collapse threshold all share the same 768px mobile cutoff.

## Continent classification
- `continentFromLatLng(lat, lng)` returns a continent for any
  coord on Earth: bbox match if possible (`continentBBox`),
  nearest-continent centroid otherwise (`nearestContinent`).
- Bboxes are coarse axis-aligned rectangles in `(lat, w)` where
  `w = ((lng + 540) % 360) - 180` (lng wrap-normalized to ±180).
  Order matters — the cascade returns the first match, so more
  specific rules go above more general ones (e.g. Iceland is
  carved out before the Greenland rule below it).
- **Greenland exception**: the North America bbox stops at
  `w <= -50` (excludes Greenland's eastern half), and the
  centroid fallback pulls high-latitude coords to Europe — at
  high lat, `cos(lat)` shrinks longitude contributions so
  Europe (52, 15) ends up "closer" than NA (45, -100) for a
  point clearly above Greenland. A dedicated rule
  (`lat 60-90, w -75 to -10`) classifies Greenland and the
  polar Atlantic above it as North America. Iceland
  (`lat 63-67, w -25 to -13`) is carved out one rule earlier
  to keep it in Europe by convention.
- `oceanFromLatLng(lat, lng)` is a separate cascade for water:
  named seas/gulfs first, then polar oceans by lat, then
  Pacific/Atlantic/Indian by lng band. Used for the popup
  header label when reverse-geocode comes back empty.

## Character limits
The pattern across the site is "openers get 100, replies get 50,
conversations cap at 500 chars total." Specifically:

- **Dot message** — 100 chars.
- **Flare question** (the opener) — 100 chars. Not counted toward
  the 500-char thread budget.
- **Flare reply** — 50 chars per reply, 500 chars total across all
  replies on a flare. Atomic budget enforcement via the
  `insert_flare_response` RPC (see Flares section).

Client-side validation gates run at: `<textarea maxlength>`, the
visible counter, the submit-button enable check, and the final
pre-insert length guard. DB CHECK constraints back the per-message
caps (1..50 on `flare_responses.text`; 280 as a permissive backstop
on the older `messages.text` and `flares.text` columns — UI is the
strict surface there).

For thread-level budgets (the 500-char total), the RPCs are the
authoritative gate: client-side maxlength shrinks dynamically as
the budget runs out (`min(50, remaining)`), and the RPC raises
`P0002 thread_full` if a turn would push past the cap. Two
simultaneous inserts can't both succeed past the cap because the
RPC locks the parent row before reading the running total.

## Translation
- Backend is **MyMemory** (`https://api.mymemory.translated.net/get`).
  CORS-enabled, called directly from the browser. No API key, no secret,
  no Edge Function, no server-side component.
- Each request includes `&de=hello@dropadot.world` (the
  `MYMEMORY_CONTACT` constant), which raises the per-IP daily limit from
  5,000 to **50,000 chars/day per visitor**. Free tier, no signup —
  MyMemory just wants a contact email for high-usage IPs.
- Quota is per-user, not app-wide, so scale is not a concern.
- 500-byte limit per request — fine for individual dropadot messages
  (UI caps inputs at 100 chars; DB column allows up to 280 as a
  permissive backstop).
- Response shape: `{ responseStatus: 200, responseData: { translatedText: "..." } }`.
- Failures log `[translate:mymemory] failed: …` to the console.
  `translate()` returns `null` on any failure; callers fall back to the
  original untranslated text, so the UI degrades gracefully.
- Source language uses MyMemory's **`Autodetect`** pseudo-code
  (`DEFAULT_SOURCE_LANG` in `index.html`) so the server picks the source
  per request. Verified working for Spanish, Russian, Indonesian, English
  source text in our smoke tests; the response includes
  `responseData.detectedLanguage` for debugging. (`auto` is rejected by
  the API — only `Autodetect` is accepted.)
- Same-language edge case: when Autodetect resolves to the same code as
  the target, MyMemory returns `403 "PLEASE SELECT TWO DISTINCT
  LANGUAGES"`. `fetchMyMemory` recognizes that exact response and
  silently returns the original text (passed through `sanitizeProfanity`)
  instead of treating it as a failure — the UI shows the source text,
  no console warning.
- **Lingva and the circuit breaker were removed.** Lingva is permanently
  unreliable (all public mirrors share one broken Google scraping
  backend), and the breaker only existed to stop us from hammering dead
  mirrors. With MyMemory both problems no longer exist; keeping that
  code around as dormant fallbacks would be clutter, not insurance.

## Supabase
- Project URL: https://sxofvadbeznwgctdzbmk.supabase.co
- Publishable key is hardcoded in index.html (safe — RLS protects writes)
- Table: messages (id, text, lat, lng, loc, mood, created_at, continent)
- RLS: anyone can read, anyone can insert. UPDATE is NOT permitted directly.
- **Polling, not realtime.** All Supabase realtime websocket subscriptions
  were removed to control egress on free tier. The map is refreshed by a
  30-second incremental SELECT (see `POLL_INTERVAL_MS` and the polling
  cursor in `index.html`, around line 6410). New dots appear within 30s of
  insert instead of arriving instantly. Trade-off accepted in exchange for
  ~zero realtime quota usage and predictable scaling.

### One-time migration SQL (run in Supabase SQL editor)
```sql
ALTER TABLE messages ADD COLUMN IF NOT EXISTS continent text;
```

## Cloudflare Worker (edge cache for boot reads)
- URL: `https://dropadot-cache.thinksubliminal.workers.dev/loadAll`
- Hosted on Cloudflare Workers free tier (`*.workers.dev`, no DNS migration).
  DNS for `dropadot.world` itself stays on Namecheap → GitHub Pages.
- The Worker fires four parallel SELECTs on Supabase (messages, flares,
  flare_responses, chest_claims) for today's window, bundles them into one
  JSON response, and caches at the edge for **30 seconds** via
  `Cache-Control: public, max-age=30` plus an explicit `caches.default.put`.
- Goal: a viral-burst page-load surge (1000+ visitors in a window) collapses
  into ~2 Supabase queries per minute total, instead of 3 per visitor.
  Egress is the bottleneck on Supabase free tier (5 GB/mo); this pattern
  caps it at "however much one cached snapshot weighs × cache misses/min".
- Response includes `X-Cache: HIT` / `X-Cache: MISS` for debugging in the
  browser network tab. `Cf-Cache-Status: HIT` on the Cloudflare side
  confirms the response was served from CDN without invoking the Worker.
- **Client falls back to direct Supabase reads** if the Worker is
  unreachable or returns non-200 — see `WORKER_LOADALL_URL` and the bundle
  pattern in `index.html` around line 6336. So the site degrades gracefully
  if the Worker is down; visitors just lose the egress savings, not the
  functionality.
- Polling continues to hit Supabase directly (the polling endpoint is
  per-client cursor and small per call). `chest_claims` boot read also
  stays direct (single-row, narrow, not worth caching).
- **Canonical worker source: `worker.js` in this repo.** The live worker
  in the Cloudflare dashboard is a manual copy-paste from this file —
  the dashboard does NOT auto-sync with the repo. When you change
  `worker.js`, also paste it into dash.cloudflare.com → Workers & Pages
  → dropadot-cache → Edit code → Save and Deploy. (Keep both in sync,
  or the bundle that visitors actually hit will lag the source.)

## Flares
A second interaction type: a question/wish anchored to a continent. Visitors
on the same continent can each leave one short reply, building a multi-voice
thread that's bounded by a shared 500-character budget across all replies.
Once the budget is spent the thread locks for the day. The flare's question
itself is capped at 100 chars and is **not** counted against the 500. Each
individual reply is capped at 50 chars. **Both planting and responding
require a dropped dot today** — the response gate was tightened
2026-05-10 to match the rest of the site's "present today" rule
(previously only planting required a dot). One flare per day per
device. Reset at midnight UTC.

### Locked-state hint priority (responding)
- When the visitor hasn't dropped today, the locked-state message
  is **"drop a dot first to respond"** — this takes priority over
  the continent-mismatch hint. Rationale: a North American looking
  at a North America flare should see the actionable next step
  ("drop a dot") rather than the misleading "wrong continent" copy.
- Continent-mismatch hint only surfaces once the visitor has
  dropped today.

### Tables
- `flares` (id, text, lat, lng, loc, continent, planter_id, created_at). The
  flare itself: who planted it, where, what it says.
- `flare_responses` (id, flare_id, responder_id, text, created_at). The
  response lives in its own row — there is no longer a `responder_id` /
  `response` column on `flares`. (Older revisions of these docs described
  the response living on the `flares` row via UPDATE; that architecture is
  gone.)
- `planter_id` / `responder_id` are client-asserted text values from
  `hw-planter-id` in localStorage. NOT regenerated daily; rotatable by
  clearing storage. Server has no auth, so identity is honor-system.

### RLS / constraints — current state (2026-05-09)
- `flares`: SELECT public, INSERT public (`with_check = true`).
- `flare_responses`:
  - SELECT public.
  - INSERT requires `length(trim(responder_id)) > 0 AND length(trim(text)) > 0`
    — rejects empty / whitespace-only rows.
  - `CHECK (char_length(text) BETWEEN 1 AND 50)` enforces the per-reply
    50-char cap at the DB level. The UI matches it.
  - `UNIQUE (flare_id, responder_id)` enforces one reply per device per
    flare. A second attempt from the same device yields Postgres
    `23505 unique_violation`, surfaced as "you've already replied to
    this flare."
- All inserts go through the `insert_flare_response(p_flare_id,
  p_responder_id, p_text)` RPC, **not** a direct INSERT. The function:
  1. Validates the reply is 1–50 chars (raises `P0001
     reply_invalid_length` on violation).
  2. Locks the parent `flares` row with `SELECT ... FOR UPDATE` so two
     concurrent calls serialize.
  3. Sums `char_length(text)` across existing replies for the flare.
     If `existing + new > 500`, raises `P0002 thread_full` (surfaced
     as "this conversation is closed.").
  4. Otherwise inserts and returns the row.
- The 500-char shared budget is **replies-only**. The flare's question
  is separate. Atomic enforcement at the DB level is essential — without
  the row lock, two simultaneous replies could both think they have room
  and overflow the budget.

### Known security gap (PR-2, deferred)
- Continent verification is **client-side only**. Nothing in RLS verifies
  that the responder is actually on the continent the flare belongs to,
  because (a) `messages` has no `planter_id` column, so there is no
  server-visible link between a responder and a dot they dropped today,
  and (b) lat/lng on insert is fully client-asserted.
- Closing this gap requires a client change (sending `planter_id` on
  `messages` and `flare_responses` inserts) plus schema additions to both
  tables. Tracked as PR-2; do not pretend the current build enforces this.

### Updates
- Flares and responses are picked up by the same 30-second polling loop
  that handles dots — there are no realtime subscriptions on these tables
  either. New flares and incoming responses appear within 30s.

### Migration SQL (historical reference; current schema reflects all of these)
```sql
-- Original flares table.
create table flares (
  id uuid default gen_random_uuid() primary key,
  text text not null check (char_length(text) <= 280),
  lat double precision not null,
  lng double precision not null,
  loc text,
  continent text not null,
  planter_id text not null,
  created_at timestamptz default now()
);

-- Responses table (separate from flares).
create table flare_responses (
  id uuid default gen_random_uuid() primary key,
  flare_id uuid not null,
  responder_id text not null,
  text text not null,
  created_at timestamptz default now()
);

alter table flares enable row level security;
create policy "anyone can read flares" on flares for select using (true);
create policy "anyone can insert flares" on flares for insert with check (true);

alter table flare_responses enable row level security;
create policy "anyone can read flare responses" on flare_responses for select using (true);

-- PR-1 lockdown (2026-05-02):
create policy "anyone can insert flare responses" on flare_responses
  for insert with check (
    length(trim(responder_id)) > 0
    and length(trim(text)) > 0
  );
-- 1:1 lock (2026-05-08, superseded the next day):
-- alter table flare_responses
--   add constraint flare_responses_one_per_flare unique (flare_id);

-- Multi-voice thread migration (2026-05-09, current):
-- Drops the 1:1 lock, adds one-per-device, tightens reply length to 50,
-- adds the atomic budget-enforcing RPC. Full SQL in `flares_thread.sql`
-- in the repo root. Run via the Supabase SQL editor.
```

### Visual identity
- Triangle markers (vs dots), amber `#ff9e3d` color.
- Not full: rapid pulse animation (urgent beacon — still inviting voices).
- Full (500-char budget exhausted): dimmed, no animation, slightly smaller
  (settled). The canvas reads `answered = usedChars >= 500` to drive this.
- Mine: white stroke around the triangle (parallel to `.dot.mine`).

### Dev
- Console: `resetMyFlare()` clears today's flare lock.

## Stars (space realm)
A fourth interaction type that lives in the "space" view (the museum's
gallery longitude band, around `lng = -450`). Frames are turned off
(`SHOW_GALLERY_FRAMES = false` in `index.html`) so the wall is empty —
the space is for stars and stars only. Tap the rocket icon to travel
to the museum, then tap the white-star toolbar button to enter aim
mode, then click anywhere on the map to plant a star with a 100-char
question. Other space-dwellers reply 50 chars at a time, atomic
500-char total budget per thread.

### Gates
- **Planting requires NO dot today.** Anyone can plant a star.
  Reflects the "away from earth's problems" framing — space is
  decoupled from earth's rules.
- **Replying requires the visitor to have planted a star today.**
  Parallel to dots-need-a-dot, but using stars-need-a-star. You're
  a "space-dweller" only after planting your own.
- 1 star per day per device (`localStorage.hw-user-stars`, mirrors
  the flare daily-lock shape).
- **No back-to-back replies** from the same device on a single star.
- **Star author can't post the first reply** on their own star.
- Both rules enforced atomically in the `insert_star_response` RPC.

### Tables
- `stars (id, text, lat, lng, planter_id, created_at)`. No continent
  or `loc` columns — there's no continent in space, and the planter's
  GPS isn't captured. 100-char CHECK constraint on `text`.
- `star_responses (id, star_id, responder_id, text, created_at)`.
  1–50 char CHECK on `text`, mirrors `message_responses` and
  `flare_responses`. SELECT public; INSERT must go through the RPC.

### RPC — `insert_star_response(uuid, text, text)`
Mirrors `insert_message_response` exactly. Locks the parent `stars`
row with `SELECT ... FOR UPDATE`, sums existing response lengths,
applies all three guards:
- P0001 reply_invalid_length → reply outside 1..50 chars
- P0002 thread_full → would push past the 500-char budget
- P0003 back_to_back → same `responder_id` as the most recent reply
- P0004 owner_first → empty thread + responder is the star's planter

### Visual identity
- White 5-point SVG star marker, same two-stack drop-shadow recipe
  the chest uses but in white (`drop-shadow(0 0 2px white@0.55) +
  drop-shadow(0 0 9px white@0.22)`). Mine variant uses stronger
  drop-shadows for "this is yours" recognition.
- Markers live in a **custom Leaflet pane** named `stars`, created
  via `map.createPane('stars')`. The pane gets class
  `leaflet-stars-pane` which is opacity 0 by default and opacity 1
  under `body.in-gallery`. This makes stars exclusive to the space
  realm — they don't bleed onto earth and don't get hidden by the
  same in-gallery rule that fades out earthly markers.
- Toolbar in gallery mode swaps the earth-side buttons (drop, flare,
  museum) for the space-side pair: `#starBtn` (white star, left) and
  `#earthBackBtn` (globe icon, right — returns to earth). The pill
  chrome stays identical across both modes; only the buttons inside
  swap, via a hard `display: none / display: flex` toggle (no
  cross-fade). The snap toggle eliminated the ghostly bleed where
  both icon sets used to be briefly visible during transitions.

### Boot + polling
- Boot: direct Supabase SELECT for `stars` + `star_responses` on the
  current UTC day. The Cloudflare Worker's `loadAll` bundle does NOT
  carry stars yet — the boot does a `bundle?.stars ?? null` check,
  falls into direct Supabase if absent. Update the worker to bundle
  these later for the egress savings.
- Polling: `stars` and `star_responses` added to `pollOnce()`'s
  incremental SELECT batch alongside the existing tables. New star
  popups refresh in place via `refreshOpenStarPopup`.

### Daily reset
- `stars` and `star_responses` added to the midnight UTC TRUNCATE
  in `cron.sql`. Same wipe pattern as everything else.

### Toggle frames back on
- Set `SHOW_GALLERY_FRAMES = true` (single constant near the
  `renderGallery` IIFE in `index.html`) and the wall returns. The
  star feature works independently; both can coexist once we want
  them to.

### Dev
- Console (dev mode only): `resetMyStar()` clears today's star
  lock so a new star can be planted from the same browser.

## Heard Around the World panel
- Bottom-left frosted-glass card showing a rotating selection of dots,
  sampled with a **random-weighted-recent** algorithm (newer dots more
  likely to be surfaced, but every dot keeps a real chance). Re-rolls
  every 30s (`HW_ROTATE_MS`).
- Pool: most-recent 30 dots per continent (`HW_CANDIDATE_POOL`), up to 7
  rows displayed (`HW_MAX_ROWS`).
- Pure client-side: zero database round-trips, zero realtime traffic.
- Continent is derived in `continentFromLatLng()` (bbox cascade — no API).
  Stored on insert; client-side fallback handles older rows where the column
  is NULL.
- Click a row → flyTo the dot and open its popup.
- Mobile (<768px): renders as a collapsible carousel card. **Starts
  expanded on both desktop and mobile** (the previous mobile-
  collapsed-by-default boot toggle was removed). The chevron stays
  in place for anyone who wants to collapse manually. Auto-advance
  is still suppressed while collapsed (`startAutoAdvance` bails
  early on the `.collapsed` check) so the slide timer doesn't tick
  uselessly behind a hidden
  body.
- Hidden entirely when there are no messages today.

## Per-message actions menu (kebab on dot popups)
- Top-right of every dot popup is a kebab (three vertical dots) button
  that opens a small dropdown with **Share** (copies a deep-link to the
  clipboard) and **Report** (inserts into the public reports table).
  Flare and star popups carry the same kebab but with Share only —
  Report is on the roadmap once the reports table is generalized
  beyond `message_id`.
- Click-outside-to-close: the menu adds a `document` click listener on
  open and tears it down on close. The listener is added via
  `setTimeout(0)` so the same click that opens the menu doesn't
  immediately close it. Menu item handlers all call `closeMenu()`.
- Previously this menu also carried **Blur**, a personal-mute toggle
  whose only practical effect was filtering the Heard Around the World
  rotation. With Heard panel currently hidden (`#hwPanel { display:
  none !important; }`), Blur was removed 2026-05-19 — no DB or
  server-side traces, just dead local code. `localStorage.hw-muted-ids`
  values on old visitors are now harmless orphans.

### Report
- Tap **Report** → fire-and-forget INSERT into the public `reports`
  table (`kind` + `subject_id` + `created_at`), then inline status text
  in the kebab menu ("reported. thanks." on success, "report failed.
  try again." on any error). One-tap, no confirmation modal —
  accidental reports are cheap to ignore in the queue.
- `kind` is `'message'`, `'flare'`, or `'star'` and identifies which
  table `subject_id` references. Dots (messages), flares, and stars
  all use the same `reports` row shape. (The single-table approach
  beat the per-kind tables alternative: one triage query, one cron
  TRUNCATE line, one RLS policy.)
- RLS: anyone can INSERT. **No SELECT policy** → reports are admin-only
  via the Supabase dashboard; the public can never read who flagged
  what. No reason field in v1; if triage signal becomes needed, add
  a `reason text` column and an enum-style dropdown in the menu.
- `reports` is included in the midnight UTC TRUNCATE alongside
  `messages` / `flares` / etc. — reports older than 24h are useless
  context anyway (the underlying subject is gone).
- Triage workflow: scan `SELECT kind, subject_id, count(*) FROM reports
  GROUP BY kind, subject_id ORDER BY count(*) DESC` during launch /
  spike windows; `DELETE FROM messages WHERE id IN (...)` (or
  `flares` / `stars` per `kind`) for anything that needs to go.
- This is the moderation primitive on top of the three write-time
  blocks (hate-symbol codepoint, hate-phrase regex, single-word slur
  redactor). Those catch the obvious cases at insert; reports catch
  what slips past — including content that's policy-violating but
  not slur/hate-pattern-matching (spam, harassment, off-topic).

### One-time migration SQL (run in Supabase SQL editor)
```sql
-- Reports table (current schema).
CREATE TABLE IF NOT EXISTS reports (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  kind text NOT NULL CHECK (kind IN ('message','flare','star')),
  subject_id uuid NOT NULL,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anyone can insert reports" ON reports
  FOR INSERT WITH CHECK (true);
-- No SELECT policy on purpose: reports are admin-only signals.

-- If your `reports` predates the schema above (only had `message_id`),
-- run `reports_generalize.sql` in the repo root instead of the CREATE
-- above. It adds `kind`, renames `message_id` to `subject_id`, and is
-- idempotent so re-runs are safe.

-- Update the midnight cron to TRUNCATE reports too. Idempotent —
-- cron.schedule with an existing jobname replaces the schedule in
-- place. Run this even if reports already existed.
SELECT cron.schedule(
  'midnight-utc-reset',
  '0 0 * * *',
  $$ TRUNCATE TABLE reports, flare_responses, flares, messages, chest_claims; $$
);
```

## Treasure chest (chosen-dot rendering)
- Hourly mechanic: tapping the chest (when you've dropped today and no
  one has claimed this hour) inserts into `chest_claims` and transforms
  your dot into a gold-glowing mood emoji for the rest of the UTC hour.
- **Spawn bounds**: the curated `TREASURE_LAND_LOCATIONS` array is
  filtered to lat ∈ [-60, 70] and lng ∈ [-170, 170] so the chest
  always lands somewhere navigable and never below the visible map
  edge. Antarctica research stations (lat -77 to -90) were dropped
  for that reason. Cycle length follows `TREASURE_CONTINENTS.length`
  so adding/removing continents auto-adjusts the rotation.
- Visual size: `CHEST_ICON_PX = 20` (a JS constant near the
  `TREASURE_CHEST_SVG` definition). Both the chest icon (via
  `.treasure-chest` width/height in CSS) AND the chosen-dot mood emoji
  (via `ctx.font` size in canvas) reference this same value so they
  share visual weight. **The CSS `width`/`height` MUST be kept in sync
  manually with `CHEST_ICON_PX`** — there is no live link between CSS
  and JS.
- Chosen-dot canvas rendering (in `_drawDot`):
  - Gold pulse ring drawn first via `ctx.arc` at `(x - 1, y)` for the
    chosen state — the 1px leftward nudge is an empirical optical
    correction so the pulse appears centered on the emoji glyph (Apple
    Color Emoji ink renders slightly right of the (x, y) anchor).
  - Single warm-gold drop-shadow glow on the emoji (`shadowBlur: 24,
    rgba(255, 215, 0, 0.85)`). A previous wider+softer second pass was
    removed because it read as a stray ring with a slightly different
    color cast against the dark map.
  - Emoji draw uses bounding-box compensation (`x + dx, y + dy` from
    `measureText`) to push the visible ink toward the (x, y) anchor.

## Static legal/info pages
- `/terms`, `/privacy`, `/contact`, `/credits` — each is a folder with
  its own `index.html`, all sharing `assets/legal.css` (dark background,
  Inter heading, orange `#ff9e3d` link color).
- `/credits` lists icon attributions to The Noun Project (icon names
  link to the specific icon page; "The Noun Project" links to the
  homepage). Add new attribution lines there as needed.
- Linked from the Rules modal's bottom legal row (`#helpModal` in
  `index.html` around line 1989).

## Known limitations
- One-dot-per-day is localStorage-only (bypassable via incognito/clearing storage)
- No moderation tools yet
- No anonymous auth yet (next session)

## Midnight UTC reset
- Authoritative reset is server-side via Supabase `pg_cron`. Job
  `midnight-utc-reset` runs
  `TRUNCATE TABLE reports, flare_responses, flares, message_responses, messages, chest_claims`
  at `0 0 * * *` (00:00 UTC daily). pg_cron in Supabase runs in UTC.
  `cron.sql` is the canonical schedule.
- **Reset countdown amber-under-one-hour**: the visible countdown
  fades to flare amber `#ff9e3d` when less than one hour remains
  until midnight UTC. Ambient color cue only — no animation, no
  size change.
- Source of truth for the schedule lives at `cron.sql` in the repo root.
  If pg_cron is reinstalled or the project is migrated, run that file to
  restore the job.
- Client also calls `location.reload()` at midnight UTC (`index.html`,
  `scheduleMidnight()`). This is just to refresh any tabs open at the cut —
  it is NOT what enforces deletion.
- Client query filters (`.gte("created_at", todayMidnightUTC())`) are still
  in place as a belt-and-suspenders fallback for any window between the
  cron run and the client reload.
- To inspect or change the schedule:
  `SELECT * FROM cron.job WHERE jobname = 'midnight-utc-reset';`
  `SELECT cron.unschedule('midnight-utc-reset');`

## Dev
- Dev mode is gated behind `?dev=1` in the URL. Normal visitors never see
  the helpers. When active, the console prints a `[dev mode]` banner.
- Console (dev mode only): `resetMyDot()` clears localStorage to allow
  another drop for testing
- Console (dev mode only): `resetMyFlare()` clears today's flare lock
- Helpers are wired off `IS_DEV_MODE` near the top of the script in
  `index.html` — single source of truth, easy to extend if more dev-only
  tooling is needed later.
