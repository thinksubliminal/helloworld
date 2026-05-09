-- Migration: convert casts from one-question / one-answer to a 1:1
-- back-and-forth thread between sender and receiver, with the same
-- character budget mechanic flares now use.
--
-- Design:
--   - The cast's question stays on `casts.question` (the opener — same
--     role as flares.text).
--   - Every back-and-forth turn after the opener lives in a new
--     `cast_turns` table. 50 chars per turn, 500 chars total across
--     all turns (the opener is NOT counted toward the budget — same
--     rule as flares).
--   - Turn alternation (sender → receiver → sender → ...) is enforced
--     client-side. The DB only enforces the budget atomically.
--   - `casts.answer` is left as a deprecated dead column. Daily wipe
--     handles cleanup; we don't migrate existing answers backward
--     (low traffic, regression lasts <24h until midnight UTC).
--
-- Run this in the Supabase SQL editor.

-- 1. Cast turns table.
CREATE TABLE IF NOT EXISTS cast_turns (
  id          uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  cast_id     uuid        NOT NULL,
  speaker_id  text        NOT NULL,
  text        text        NOT NULL,
  created_at  timestamptz DEFAULT now(),
  CONSTRAINT cast_turns_text_check CHECK (char_length(text) BETWEEN 1 AND 50),
  CONSTRAINT cast_turns_speaker_check CHECK (length(trim(speaker_id)) > 0)
);

-- Index for cheap "all turns for this cast in order" queries.
CREATE INDEX IF NOT EXISTS cast_turns_cast_id_created_at_idx
  ON cast_turns (cast_id, created_at);

-- 2. RLS — public read.
ALTER TABLE cast_turns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anyone can read cast turns" ON cast_turns;
CREATE POLICY "anyone can read cast turns" ON cast_turns
  FOR SELECT USING (true);

-- INSERTs only via the RPC below — no direct INSERT policy. Keeps the
-- atomic budget enforcement the only path in.

-- 3. Atomic budget enforcement function.
-- Locks the parent cast row, sums existing turn char_lengths, and
-- refuses to insert if the new turn would push the thread past 500
-- total chars. Two simultaneous inserts can't both succeed past the
-- cap because the lock serializes them.
--
-- Errors:
--   P0001 reply_invalid_length → text outside 1..50 chars
--   P0002 thread_full          → would exceed 500-char budget
CREATE OR REPLACE FUNCTION insert_cast_turn(
  p_cast_id    uuid,
  p_speaker_id text,
  p_text       text
) RETURNS cast_turns
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_used    integer;
  v_new_len integer;
  v_row     cast_turns;
BEGIN
  v_new_len := char_length(coalesce(p_text, ''));
  IF v_new_len < 1 OR v_new_len > 50 THEN
    RAISE EXCEPTION 'reply_invalid_length' USING ERRCODE = 'P0001';
  END IF;

  -- Serialize budget reads/writes by locking the parent cast row.
  PERFORM 1 FROM casts WHERE id = p_cast_id FOR UPDATE;

  SELECT COALESCE(SUM(char_length(text)), 0)
    INTO v_used
    FROM cast_turns
    WHERE cast_id = p_cast_id;

  IF v_used + v_new_len > 500 THEN
    RAISE EXCEPTION 'thread_full' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO cast_turns (cast_id, speaker_id, text)
  VALUES (p_cast_id, p_speaker_id, p_text)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION insert_cast_turn(uuid, text, text)
  TO anon, authenticated;

-- 4. Add cast_turns to the midnight-UTC reset cron. cron.schedule is
-- idempotent — the existing job is replaced in place when the
-- jobname matches.
SELECT cron.schedule(
  'midnight-utc-reset',
  '0 0 * * *',
  $$ TRUNCATE TABLE reports, casts, cast_turns, flare_responses, flares, messages, chest_claims, tiles; $$
);

-- 5. Drop the now-unused UPDATE policy on casts. The new client never
-- updates casts.answer; everything goes through insert_cast_turn.
DROP POLICY IF EXISTS "anyone can answer an unanswered cast" ON casts;
