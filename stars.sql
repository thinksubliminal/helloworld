-- Migration: stars + star_responses for the space realm.
--
-- Stars are flare-shaped objects planted in the "space" region of the
-- map (the gallery longitude band). Differences vs. flares:
--
--   - No GPS / continent. Plant location is wherever the visitor
--     clicks on the map after entering placement mode.
--   - Planting requires NO dot today. Anyone can plant.
--   - Replying requires the visitor to have planted a star today
--     (parallel to dots-need-a-dot, but using stars-need-a-star —
--     "you're a space-dweller after planting your own").
--   - No back-to-back replies from the same device.
--   - The star author cannot post the first reply on their own star.
--   - 100 chars on the opener, 50 chars per reply, 500 chars total
--     across all replies. Atomic budget enforcement via RPC.
--
-- Run this in the Supabase SQL editor.
--
-- Steps:
--   1. stars table + RLS (read/insert open; updates not allowed).
--   2. star_responses table + RLS (read open; inserts via RPC only).
--   3. insert_star_response RPC — atomic budget + no-back-to-back +
--      owner-can't-go-first.
--   4. Update midnight cron to TRUNCATE stars + star_responses.

-- 1. stars table.
CREATE TABLE IF NOT EXISTS stars (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  text       text        NOT NULL CHECK (char_length(text) BETWEEN 1 AND 100),
  lat        double precision NOT NULL,
  lng        double precision NOT NULL,
  planter_id text        NOT NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE stars ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anyone can read stars" ON stars;
CREATE POLICY "anyone can read stars" ON stars
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "anyone can insert stars" ON stars;
CREATE POLICY "anyone can insert stars" ON stars
  FOR INSERT WITH CHECK (
    length(trim(text)) > 0
    AND length(trim(planter_id)) > 0
  );

-- 2. star_responses table.
CREATE TABLE IF NOT EXISTS star_responses (
  id           uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  star_id      uuid        NOT NULL,
  responder_id text        NOT NULL,
  text         text        NOT NULL,
  created_at   timestamptz DEFAULT now(),
  CONSTRAINT star_responses_text_check
    CHECK (char_length(text) BETWEEN 1 AND 50)
);

CREATE INDEX IF NOT EXISTS star_responses_star_id_idx
  ON star_responses (star_id);

ALTER TABLE star_responses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anyone can read star responses" ON star_responses;
CREATE POLICY "anyone can read star responses" ON star_responses
  FOR SELECT USING (true);

-- All inserts must go through the RPC. No direct INSERT policy.

-- 3. Atomic insert with budget + no-back-to-back + owner-can't-go-first.
--
-- Locks the parent stars row, sums existing response char_lengths,
-- checks the most recent responder_id, and refuses to insert if:
--   - the new reply would push the thread past 500 chars (P0002)
--   - the new reply's responder_id matches the most recent reply's
--     responder_id (P0003 back_to_back)
--   - the thread is empty AND the new responder_id matches the star's
--     planter_id (P0004 owner_first — author can't open their own thread)
--
-- Returns the inserted star_responses row on success.
CREATE OR REPLACE FUNCTION insert_star_response(
  p_star_id      uuid,
  p_responder_id text,
  p_text         text
) RETURNS star_responses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_used        integer;
  v_new_len     integer;
  v_last_id     text;
  v_planter_id  text;
  v_row         star_responses;
BEGIN
  v_new_len := char_length(coalesce(p_text, ''));
  IF v_new_len < 1 OR v_new_len > 50 THEN
    RAISE EXCEPTION 'reply_invalid_length' USING ERRCODE = 'P0001';
  END IF;

  -- Serialize budget + last-replier reads/writes by locking the
  -- parent star row.
  SELECT planter_id INTO v_planter_id
    FROM stars
    WHERE id = p_star_id
    FOR UPDATE;

  SELECT COALESCE(SUM(char_length(text)), 0)
    INTO v_used
    FROM star_responses
    WHERE star_id = p_star_id;

  IF v_used + v_new_len > 500 THEN
    RAISE EXCEPTION 'thread_full' USING ERRCODE = 'P0002';
  END IF;

  -- Most recent responder_id in this thread, if any.
  SELECT responder_id INTO v_last_id
    FROM star_responses
    WHERE star_id = p_star_id
    ORDER BY created_at DESC
    LIMIT 1;

  IF v_last_id IS NOT NULL AND v_last_id = p_responder_id THEN
    RAISE EXCEPTION 'back_to_back' USING ERRCODE = 'P0003';
  END IF;

  -- Empty thread + responder is the star's author → reject.
  IF v_last_id IS NULL
     AND v_planter_id IS NOT NULL
     AND v_planter_id = p_responder_id THEN
    RAISE EXCEPTION 'owner_first' USING ERRCODE = 'P0004';
  END IF;

  INSERT INTO star_responses (star_id, responder_id, text)
  VALUES (p_star_id, p_responder_id, p_text)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION insert_star_response(uuid, text, text)
  TO anon, authenticated;

-- 4. Midnight cron — add stars + star_responses to the nightly TRUNCATE.
-- pg_cron's cron.schedule replaces an existing job with the same name.
-- Keep this list in sync with cron.sql.
SELECT cron.schedule(
  'midnight-utc-reset',
  '0 0 * * *',
  $$
    TRUNCATE TABLE
      reports,
      flare_responses, flares,
      message_responses, messages,
      star_responses, stars,
      chest_claims;
  $$
);
