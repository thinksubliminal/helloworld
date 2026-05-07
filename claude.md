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
  personal-mute list, and one-cast-per-day client lock
- Continent attribution for flares/casts derives from
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
- Flares additionally trigger this `setView` for an outer-corner
  case at very low zoom (corner 18%, zoom < 3.5) where the flare
  popup is too big to fit even with autoPan's max shift.
- Cast lines, dot popup widths, flare popup widths, and the
  Heard panel collapse threshold all share the same 768px
  mobile cutoff.

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
- All text inputs (dot messages, flares, flare responses, cast
  questions, cast answers) are capped at **100 characters** in the
  client UI. Validation gates run at: `<textarea maxlength>`, the
  visible counter, the submit-button enable check, and the final
  pre-insert length guard. The DB CHECK constraints on `text`/
  `question`/`answer` columns remain at the original 280 as a
  permissive backstop — UI is the strict surface.

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
- Table: messages (id, text, lat, lng, loc, mood, created_at, view_count, continent)
  — note: `view_count` is no longer read or written by the client (see Heard
  Around the World panel below). The column and the
  `increment_message_view_count(uuid)` RPC remain in the schema as historical
  artifacts; they can stay or be dropped without affecting the app.
- RLS: anyone can read, anyone can insert. UPDATE is NOT permitted directly.
- **Polling, not realtime.** All Supabase realtime websocket subscriptions
  were removed to control egress on free tier. The map is refreshed by a
  30-second incremental SELECT (see `POLL_INTERVAL_MS` and the polling
  cursor in `index.html`, around line 6410). New dots appear within 30s of
  insert instead of arriving instantly. Trade-off accepted in exchange for
  ~zero realtime quota usage and predictable scaling.

### One-time migration SQL (run in Supabase SQL editor)
```sql
ALTER TABLE messages ADD COLUMN IF NOT EXISTS view_count integer NOT NULL DEFAULT 0;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS continent text;

CREATE OR REPLACE FUNCTION increment_message_view_count(msg_id uuid)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE messages SET view_count = view_count + 1 WHERE id = msg_id
  RETURNING view_count;
$$;

GRANT EXECUTE ON FUNCTION increment_message_view_count(uuid) TO anon, authenticated;
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
- Worker code lives in the Cloudflare dashboard — not in this repo. The
  full source is `dropadot-cache` on dash.cloudflare.com; if it ever needs
  recreation, the canonical version was committed alongside the wiring
  in `2032cd4 Wire boot path to Cloudflare Worker for cached loadAll`.

## Flares
A second interaction type: a question/wish anchored to a continent. Only one
person from that continent can answer; first responder wins. Flares unlock
once the user has dropped a dot today. One flare per day per device. Reset at
midnight UTC.

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

### RLS — current state (2026-05-02)
- `flares`: SELECT public, INSERT public (`with_check = true`).
- `flare_responses`:
  - SELECT public.
  - INSERT requires `length(trim(responder_id)) > 0 AND length(trim(text)) > 0`
    — rejects empty / whitespace-only rows.
  - **`UNIQUE (flare_id)` constraint** at the table level enforces
    first-responder-wins atomically. Two concurrent inserts for the same
    `flare_id` will produce exactly one success; the loser receives a
    Postgres `23505 unique_violation`. The client surfaces this as
    "someone answered first." This is the DB-level guarantee — there is
    no UPDATE policy involved, because nothing is updated.

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

### Visual identity
- Triangle markers (vs dots), amber `#ff9e3d` color.
- Unanswered: rapid pulse animation (urgent beacon).
- Answered: dimmed, no animation, slightly smaller (settled).
- Mine: white stroke around the triangle (parallel to `.dot.mine`).

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
alter table flare_responses
  add constraint flare_responses_one_per_flare unique (flare_id);
```

### Visual identity
- Triangle markers (vs dots), amber `#ff9e3d` color.
- Unanswered: rapid pulse animation (urgent beacon).
- Answered: dimmed, no animation, slightly smaller (settled).
- Mine: white stroke around the triangle (parallel to `.dot.mine`).

### Dev
- Console: `resetMyFlare()` clears today's flare lock.

## Cast
A third interaction type, in the same family as flares. A user opens
someone else's dot popup, taps the cast button in the bottom toolbar,
asks one question, and that dot's owner gets exactly one chance to
reply back. A gold dashed line connects the two dots on the map for
both pending and answered casts (marching ants throughout; answered
state just fades the color and opacity). One cast per sender per day,
one cast per receiver per day, cross-continental only.

### Feature flag
- `IS_CAST_ENABLED` defaults to **true** for all visitors. The URL
  flag `?cast=0` is kept as an emergency kill switch (e.g., if a
  bug ships and we need to disable cast UI without a redeploy).
- Internal naming: previously called "ping"; renamed everywhere
  (variables, functions, CSS, DB table, localStorage keys). No code
  references to the old name remain.

### Tables
- `casts` (id, sender_dot_id, receiver_dot_id, question, answer,
  created_at). The cast itself: who sent, to whom, the question,
  and the (possibly null) answer.
- `sender_dot_id` and `receiver_dot_id` reference `messages.id` by
  convention (no FK constraint — same client-trust pattern as
  flares).
- Daily reset: `casts` is included in the midnight UTC TRUNCATE
  cron job alongside `flare_responses`, `flares`, `messages`.

### RLS
- `casts` SELECT public, INSERT public (`question` non-empty,
  sender/receiver non-null).
- UPDATE policy is restricted: only rows where `answer IS NULL` can
  be updated, and the new row must satisfy `answer IS NOT NULL`.
  This makes "first answer wins" atomic at the database level —
  two concurrent answer attempts on the same cast produce exactly
  one success.
- DB-level constraints enforce the rules:
  - `UNIQUE (sender_dot_id)` → one cast per sender per day (since
    each user has at most one dot per day).
  - `UNIQUE (receiver_dot_id)` → each dot can be cast to at most
    once per day.
  - `CHECK (sender_dot_id != receiver_dot_id)` → can't cast to
    your own dot.

### Cross-continental rule
- Sender's dot and receiver's dot must be on different continents.
  Continent is derived via `continentFromLatLng(lat, lng)` for both
  dots (with `msg.continent` field used as primary if present, the
  derived fallback used otherwise — `saveUserMessages()` strips
  `continent` from localStorage so the user's own dot needs the
  fallback after reload).
- Enforcement is **client-side only** — no RLS policy verifies the
  continents. A determined attacker could insert a same-continent
  cast directly via the Supabase REST API. Same security gap as
  flares (PR-2 deferred).

### UI flow
- Cast button is the **4th button** in the bottom toolbar, between
  the flare and the globe. Dormant by default (dim, not-allowed
  cursor); gets the `.active` class — gold tint, full opacity,
  pointer cursor — only when:
  1. A dot popup is currently open (`currentOpenDotId` set)
  2. It's not the viewer's own dot
  3. The viewer has dropped a dot today
  4. The viewer has not cast today (`hw-casted-today`)
  5. The target dot has not been cast to yet
  6. The two dots are on different continents
- Tapping the dormant button when conditions fail surfaces a
  context-appropriate `flashHint(...)` toast in the same
  toolbar-status style as flares' "you've shot a flare today":
  - No dot dropped → "drop a dot before casting your line"
  - Already cast today → "your line is already in the water"
  - No popup open → "open a dot across the ocean to cast"
- Tapping the active button sets `castFormOpenForId` and rebuilds
  the open dot popup, which now renders the cast respond-area
  inline. Q&A reuses the flare-popup classes (`.flare-popup-q`,
  `.flare-popup-respond-area`, etc.) so the visual treatment
  matches flare answers exactly.

### Q&A visibility (public)
- The cast Q&A is visible to **every visitor** opening the receiver
  dot's popup, not just the sender or receiver. Same model as
  flare Q&A (anyone viewing a flare popup sees the question and
  the response). The polyline on the map was already public; the
  Q&A is now public to match.
- `buildCastSection` cases:
  - **A** — viewer is the receiver (`isMine` and `incoming`):
    show the question + answer form (so the receiver can answer
    on the device that owns the dot's `mine` flag).
  - **B** — viewer is the sender (`myCast.receiver_dot_id ===
    msg.id` via the `hw-casted-today` localStorage key): show
    the question + the answer (or "awaiting reply to cast"
    placeholder).
  - **C** — viewer is a potential sender who tapped the toolbar
    `#castBtn` for this dot: show the inline send form.
  - **D** — none of the above, but `castsByReceiver` has an
    entry for this dot: render the question + answer (or the
    "awaiting reply" placeholder) **read-only**. This is the
    catch-all that makes the Q&A public to third-party visitors
    AND to the same person viewing from a second device (since
    identity is localStorage-bound and there's no cross-device
    auth — without case D, the marching-ants line draws but the
    Q&A is silently blank from any browser other than the one
    that originally sent or received it).
- This is the right default for the app: see the public-by-
  default principle in the project memory. Action capability
  (sending, answering) stays scoped to the device that holds
  the relevant localStorage; only **content visibility** is
  universal.

### Map line rendering
- Polyline drawn in `castLayer` (Leaflet layer group). Endpoints
  shortened **7 pixels short** of each dot center along the line's
  own direction (computed in pixel space via `map.project/unproject`,
  recomputed on every `zoomend` so the offset stays visually
  consistent at any zoom).
- Pending: bright gold `#F5B842`, opacity 0.85, dasharray "3 4",
  marching-ants animation via the `.cast-line-pending` class.
- Answered: muted gold `#A87C32`, opacity 0.5 — same dasharray and
  marching animation, just dimmer color + lower opacity. The
  marching never stops, by design (the animation is part of the
  feature's identity, not a "still pending" indicator).
- Send animation: when sendCast() succeeds,
  `playCastLineDrawAnimation` tweens the polyline's second endpoint
  from sender to receiver in lat/lng space over 700ms (ease-out
  cubic). The marching ants run throughout the draw, so the line
  appears to extend across the map progressively rather than flash
  in as a solid line.
- Antimeridian: lines use the dots' raw longitudes — no ±360
  shift to take the geographically shortest path across ±180°.
  An earlier version did the shift so e.g. LA↔Tokyo would draw
  across the Pacific, but visually the line "left" the map at
  one edge and reappeared in an off-screen world copy. Drawing
  in raw lng space keeps every cast line inside one visible
  rectangle. Tradeoff: true antipodal pairs draw the long way
  around (LA↔Tokyo via Atlantic+Eurasia). Acceptable — staying
  on one rectangle reads better in this UI.

### Toolbar icon
- `assets/cast-icon.svg` (Focus Tool icon attribution: Design Circle,
  The Noun Project) recreated as a stroked SVG: filled center dot
  + outer dashed ring (`pathLength="80"`, `dasharray="3 7"` → exactly
  8 dashes). Marching-ants animation runs continuously on the ring
  via the `castIconMarch` keyframe, regardless of the button's
  active state — visually links the toolbar icon to the cast lines
  on the map.

### One-time migration SQL (pings → casts rename, run if any
### environment still has the old table name)
```sql
ALTER TABLE pings RENAME TO casts;

SELECT cron.unschedule('midnight-utc-reset');
SELECT cron.schedule(
  'midnight-utc-reset',
  '0 0 * * *',
  'TRUNCATE TABLE flare_responses, flares, messages, casts;'
);

ALTER POLICY "anyone can read pings"               ON casts RENAME TO "anyone can read casts";
ALTER POLICY "anyone can insert pings"             ON casts RENAME TO "anyone can insert casts";
ALTER POLICY "anyone can answer an unanswered ping" ON casts RENAME TO "anyone can answer an unanswered cast";
```

### Dev
- Console: `resetMyDot()` and `resetMyFlare()` already exist.
  No `resetMyCast()` helper yet — clear `localStorage.hw-casted-today`
  manually if needed during dev.

## Heard Around the World panel
- Bottom-left frosted-glass card showing a rotating selection of dots,
  sampled with a **random-weighted-recent** algorithm (newer dots more
  likely to be surfaced, but every dot keeps a real chance). Re-rolls
  every 30s (`HW_ROTATE_MS`).
- Pool: most-recent 30 dots per continent (`HW_CANDIDATE_POOL`), up to 7
  rows displayed (`HW_MAX_ROWS`).
- Replaced the previous "most-viewed dot per continent" model — that
  required a `view_count` UPDATE realtime broadcast on every popup open,
  which was the dominant source of realtime quota burn. Random-weighted-
  recent is purely client-side: zero database round-trips, zero realtime
  traffic.
- Continent is derived in `continentFromLatLng()` (bbox cascade — no API).
  Stored on insert; client-side fallback handles older rows where the column
  is NULL.
- Click a row → flyTo the dot and open its popup.
- Mobile (<768px): renders as a collapsible carousel card. **Starts
  collapsed on first load** (just the header bar with a chevron) so
  the panel doesn't cover the map; tap the chevron to expand. The
  `wireCarouselCollapse` IIFE applies the `.collapsed` class on init
  for `innerWidth < 768`. Desktop keeps its default expanded state
  since there's room for both. Auto-advance is suppressed while
  collapsed (`startAutoAdvance` bails early on the `.collapsed`
  check) so the slide timer doesn't tick uselessly behind a hidden
  body.
- Hidden entirely when there are no messages today.
- **Muted dots are excluded from the candidate pool** — see Personal mute
  section below.

## Personal mute (eye icon on dot popups)
- Tap the eye icon (top-right of any dot popup) → message text blurs,
  eye toggles to closed. Tap again → unblurs, eye reopens. Pure visual
  toggle, dot stays on the map either way.
- **Local only.** Stored in `localStorage` under key `hw-muted-ids` as
  a JSON array of message UUIDs. No Supabase column, no server state,
  no record exists that anyone muted anything.
- Other visitors are completely unaffected — they see the dot normally
  in popups and in their own Heard panel rotation.
- Muted IDs are also filtered out of the Heard Around the World pool so
  the side panel respects the same gesture (`renderHeardPanel()` check).
- Daily UTC midnight reset deletes the underlying messages, so any stale
  IDs in the localStorage list become harmless dead weight (no cleanup
  needed; the list naturally caps at "today's muted dots").
- Constants: `MUTED_KEY`, `mutedIds` Set, `MUTE_ICON_OPEN`,
  `MUTE_ICON_CLOSED`, `loadMutedIds()`, `saveMutedIds()`, `toggleMuted()`
  all live just before `buildPopup()`.
- This is a **personal mute, not a report.** It hides the message from
  YOUR view; it does not flag the dot for moderation or affect what
  other visitors see. If genuine moderation is ever needed, that's a
  separate path (manual delete in Supabase per the terms).

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
  `midnight-utc-reset` runs `TRUNCATE TABLE flare_responses, flares, messages`
  at `0 0 * * *` (00:00 UTC daily). pg_cron in Supabase runs in UTC.
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
