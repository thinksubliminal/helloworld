# Hello, World

A world map where people drop a colored dot at their GPS location once a day
with a short message. Map resets at midnight UTC. No algorithm, no followers,
no likes.

## Stack
- Single index.html
- Leaflet.js for the map
- Supabase JS for the backend (database only — realtime subscriptions
  removed in favor of 30s polling; see Supabase section below)
- MyMemory API for translation (free, CORS, no signup — see Translation
  section below)
- localStorage for one-dot-per-day client check

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
  (text column is capped at 280 chars).
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
- Mobile (<768px): collapses to a small list-icon toggle button.
- Hidden entirely when there are no messages today.

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
