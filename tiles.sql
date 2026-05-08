-- ─────────────────────────────────────────────────────────────────────────
-- dropadot — Drawing Realm tiles table
-- ─────────────────────────────────────────────────────────────────────────
-- Stores each visitor's contribution to today's collaborative 10×10 mosaic.
-- Each row is one tile (one visitor's drawing) at a fixed grid index 0–99.
-- The table is wiped at midnight UTC alongside messages/flares/casts/etc.
-- (the daily reset promise).
--
-- Concurrency model: the UNIQUE constraint on tile_index is the trick
-- that makes "next empty tile" assignment race-free without locks. Two
-- visitors who simultaneously think tile #42 is free will both try to
-- INSERT it; Postgres lets exactly one through and rejects the other
-- with a 23505 unique_violation. The client catches that error and
-- retries with the next empty index. Atomic, no advisory locks needed.
--
-- Run this file in the Supabase SQL editor once. Re-running is safe.
-- ─────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS tiles (
  id          uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  tile_index  smallint    NOT NULL CHECK (tile_index >= 0 AND tile_index < 100),
  stroke_data jsonb       NOT NULL,
  mood        text,
  created_at  timestamptz DEFAULT now()
);

-- Phase 2 migration: each tile now records its artist's mood so the
-- mosaic can paint the tile's background in the matching mood color.
-- Idempotent — safe to re-run; ALTER ... ADD COLUMN IF NOT EXISTS is
-- a no-op when the column already exists.
ALTER TABLE tiles ADD COLUMN IF NOT EXISTS mood text;

-- One tile per index per day. The midnight TRUNCATE clears the table,
-- so this constraint naturally resets each UTC day.
CREATE UNIQUE INDEX IF NOT EXISTS tiles_tile_index_unique
  ON tiles (tile_index);

ALTER TABLE tiles ENABLE ROW LEVEL SECURITY;

-- DROP-then-CREATE makes the file safe to re-run. CREATE POLICY has no
-- IF NOT EXISTS clause, so without the DROPs a second run errors with
-- 42710 ("policy already exists") even though everything is fine.
DROP POLICY IF EXISTS "anyone can read tiles" ON tiles;
CREATE POLICY "anyone can read tiles" ON tiles
  FOR SELECT USING (true);

-- Strict insert: tile_index in valid range, stroke_data must be a JSON
-- array (not an object/string/null). Empty array is allowed — the
-- grid considers a row claimed regardless of stroke count.
DROP POLICY IF EXISTS "anyone can insert tiles" ON tiles;
CREATE POLICY "anyone can insert tiles" ON tiles
  FOR INSERT WITH CHECK (
    tile_index >= 0
    AND tile_index < 100
    AND jsonb_typeof(stroke_data) = 'array'
  );

-- ─────────────────────────────────────────────────────────────────────────
-- Phase 3: persistent archive of each day's collective canvas.
-- ─────────────────────────────────────────────────────────────────────────
-- The daily-reset promise still applies to dots/messages/flares/casts —
-- those are wiped wholesale at midnight UTC. The drawing canvas is the
-- one exception: at midnight, the day's tiles are copied into
-- `tiles_archive` before the active `tiles` table is truncated. The
-- archived rows carry no user-identifying data (no IP, no device ID,
-- no planter_id) — only the strokes, the artist's mood color, and the
-- date the canvas was made. Privacy promise is preserved as long as
-- nothing identifying ever lands on this table.
--
-- Storage estimate: ~5KB/tile × 100 tiles/day × 365 days ≈ 180MB/year.
-- Free-tier comfortable for years.

CREATE TABLE IF NOT EXISTS tiles_archive (
  id                  uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  day                 date        NOT NULL,
  tile_index          smallint    NOT NULL,
  stroke_data         jsonb       NOT NULL,
  mood                text,
  original_created_at timestamptz NOT NULL,
  archived_at         timestamptz DEFAULT now()
);

-- One row per (day, tile_index). Prevents accidental duplicate archives
-- if the cron ever runs twice in a window without a fresh truncate.
CREATE UNIQUE INDEX IF NOT EXISTS tiles_archive_day_index_unique
  ON tiles_archive (day, tile_index);

-- Day-keyed lookup index for "show me this day's canvas" queries.
CREATE INDEX IF NOT EXISTS tiles_archive_day_idx
  ON tiles_archive (day);

ALTER TABLE tiles_archive ENABLE ROW LEVEL SECURITY;

-- Public-read so a future "view past canvases" feature can query
-- without requiring auth. No INSERT/UPDATE/DELETE policy: only the
-- midnight cron (running as the postgres superuser, bypassing RLS)
-- writes to this table.
DROP POLICY IF EXISTS "anyone can read tiles archive" ON tiles_archive;
CREATE POLICY "anyone can read tiles archive" ON tiles_archive
  FOR SELECT USING (true);

-- ─────────────────────────────────────────────────────────────────────────
-- Update the midnight cron: copy → truncate.
-- INSERT first, TRUNCATE second. ON CONFLICT on (day, tile_index) makes
-- it safe if the cron somehow fires twice on the same UTC day.
-- ─────────────────────────────────────────────────────────────────────────

SELECT cron.schedule(
  'midnight-utc-reset',
  '0 0 * * *',
  $$
    INSERT INTO tiles_archive (day, tile_index, stroke_data, mood, original_created_at)
    SELECT created_at::date, tile_index, stroke_data, mood, created_at
    FROM tiles
    ON CONFLICT (day, tile_index) DO NOTHING;

    TRUNCATE TABLE reports, casts, flare_responses, flares, messages, chest_claims, tiles;
  $$
);
