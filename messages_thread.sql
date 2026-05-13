-- Migration: add reply threading to dots, mirroring the flare thread
-- pattern (50 chars per reply, 500 chars total shared budget) but with
-- a different participation rule:
--
--   - Anyone can reply (no continent gate)
--   - No back-to-back replies from the same device
--   - The dot author cannot post the first reply (an empty thread treats
--     the author as the implicit "last voice")
--
-- Run this in the Supabase SQL editor.
--
-- Steps:
--   1. Add planter_id to messages so the dot author is server-visible.
--   2. Create message_responses table + RLS.
--   3. Create insert_message_response RPC — atomic budget enforcement +
--      no-back-to-back + owner-can't-go-first.
--   4. Update midnight cron to TRUNCATE message_responses.

-- 1. Add planter_id to messages. Nullable so older client builds that
-- don't send it still insert successfully during the rollout window.
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS planter_id text;

-- 2. message_responses table.
CREATE TABLE IF NOT EXISTS message_responses (
  id           uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id   uuid        NOT NULL,
  responder_id text        NOT NULL,
  text         text        NOT NULL,
  created_at   timestamptz DEFAULT now(),
  CONSTRAINT message_responses_text_check
    CHECK (char_length(text) BETWEEN 1 AND 50)
);

CREATE INDEX IF NOT EXISTS message_responses_message_id_idx
  ON message_responses (message_id);

ALTER TABLE message_responses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anyone can read message responses" ON message_responses;
CREATE POLICY "anyone can read message responses" ON message_responses
  FOR SELECT USING (true);

-- All inserts must go through the RPC below. No direct INSERT policy.

-- 3. Atomic insert with budget + no-back-to-back + owner-can't-go-first.
--
-- Locks the parent messages row, sums existing response char_lengths,
-- checks the most recent responder_id, and refuses to insert if:
--   - the new reply would push the thread past 500 chars (P0002)
--   - the new reply's responder_id matches the most recent reply's
--     responder_id (P0003 back_to_back)
--   - the thread is empty AND the new responder_id matches the dot's
--     planter_id (P0004 owner_first — owner can't open their own thread)
--
-- Returns the inserted message_responses row on success.
CREATE OR REPLACE FUNCTION insert_message_response(
  p_message_id   uuid,
  p_responder_id text,
  p_text         text
) RETURNS message_responses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_used        integer;
  v_new_len     integer;
  v_last_id     text;
  v_planter_id  text;
  v_row         message_responses;
BEGIN
  v_new_len := char_length(coalesce(p_text, ''));
  IF v_new_len < 1 OR v_new_len > 50 THEN
    RAISE EXCEPTION 'reply_invalid_length' USING ERRCODE = 'P0001';
  END IF;

  -- Serialize budget + last-replier reads/writes by locking the
  -- parent message row.
  SELECT planter_id INTO v_planter_id
    FROM messages
    WHERE id = p_message_id
    FOR UPDATE;

  SELECT COALESCE(SUM(char_length(text)), 0)
    INTO v_used
    FROM message_responses
    WHERE message_id = p_message_id;

  IF v_used + v_new_len > 500 THEN
    RAISE EXCEPTION 'thread_full' USING ERRCODE = 'P0002';
  END IF;

  -- Most recent responder_id in this thread, if any.
  SELECT responder_id INTO v_last_id
    FROM message_responses
    WHERE message_id = p_message_id
    ORDER BY created_at DESC
    LIMIT 1;

  IF v_last_id IS NOT NULL AND v_last_id = p_responder_id THEN
    RAISE EXCEPTION 'back_to_back' USING ERRCODE = 'P0003';
  END IF;

  -- Empty thread + responder is the dot's author → reject.
  -- (When planter_id is NULL — pre-migration messages — the guard is
  -- skipped; those rows can't be identified as owned.)
  IF v_last_id IS NULL
     AND v_planter_id IS NOT NULL
     AND v_planter_id = p_responder_id THEN
    RAISE EXCEPTION 'owner_first' USING ERRCODE = 'P0004';
  END IF;

  INSERT INTO message_responses (message_id, responder_id, text)
  VALUES (p_message_id, p_responder_id, p_text)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION insert_message_response(uuid, text, text)
  TO anon, authenticated;

-- 4. Midnight cron — include message_responses in the nightly TRUNCATE.
-- pg_cron's cron.schedule replaces an existing job with the same name.
-- Keep this list in sync with cron.sql / the rest of the daily-wipe set.
SELECT cron.schedule(
  'midnight-utc-reset',
  '0 0 * * *',
  $$ TRUNCATE TABLE reports, tile_reports, casts, cast_turns, flare_responses, flares, message_responses, messages, chest_claims, tiles; $$
);
