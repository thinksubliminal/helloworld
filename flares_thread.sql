-- Migration: convert flares from 1:1 first-responder-wins (last night's
-- model) to a continental multi-voice thread with a shared 500-char
-- budget and a 50-char-per-reply cap.
--
-- Run this in the Supabase SQL editor.
--
-- Steps:
--   1. Drop last night's UNIQUE(flare_id) constraint.
--   2. Add UNIQUE(flare_id, responder_id) so each device replies once.
--   3. Tighten the per-reply char cap to 50.
--   4. Create insert_flare_response() — atomic budget enforcement.

-- 1. Drop the 1:1 lock.
ALTER TABLE flare_responses
  DROP CONSTRAINT IF EXISTS flare_responses_one_per_flare;

-- 2. One reply per device per flare.
ALTER TABLE flare_responses
  DROP CONSTRAINT IF EXISTS flare_responses_one_per_visitor;
ALTER TABLE flare_responses
  ADD CONSTRAINT flare_responses_one_per_visitor UNIQUE (flare_id, responder_id);

-- 3. Tighten the per-reply char cap.
-- Note: existing constraint is the 280-char check from the original schema.
-- We replace it with the new 50-char rule. Name varies; drop any existing
-- text check first.
ALTER TABLE flare_responses
  DROP CONSTRAINT IF EXISTS flare_responses_text_check;
ALTER TABLE flare_responses
  ADD CONSTRAINT flare_responses_text_check
    CHECK (char_length(text) BETWEEN 1 AND 50);

-- 4. Atomic budget enforcement.
-- Locks the parent flare row, sums the existing response char_lengths,
-- and refuses to insert if the new reply would push the thread past 500
-- total chars. Two simultaneous inserts can't both succeed past the cap
-- because the lock serializes them.
--
-- Errors raised:
--   P0001 reply_invalid_length  → input text outside 1..50 chars
--   P0002 thread_full           → would exceed the 500-char budget
--
-- Returns the inserted flare_responses row on success.
CREATE OR REPLACE FUNCTION insert_flare_response(
  p_flare_id     uuid,
  p_responder_id text,
  p_text         text
) RETURNS flare_responses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_used    integer;
  v_new_len integer;
  v_row     flare_responses;
BEGIN
  v_new_len := char_length(coalesce(p_text, ''));
  IF v_new_len < 1 OR v_new_len > 50 THEN
    RAISE EXCEPTION 'reply_invalid_length' USING ERRCODE = 'P0001';
  END IF;

  -- Serialize budget reads/writes by locking the parent flare row.
  PERFORM 1 FROM flares WHERE id = p_flare_id FOR UPDATE;

  SELECT COALESCE(SUM(char_length(text)), 0)
    INTO v_used
    FROM flare_responses
    WHERE flare_id = p_flare_id;

  IF v_used + v_new_len > 500 THEN
    RAISE EXCEPTION 'thread_full' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO flare_responses (flare_id, responder_id, text)
  VALUES (p_flare_id, p_responder_id, p_text)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION insert_flare_response(uuid, text, text)
  TO anon, authenticated;
