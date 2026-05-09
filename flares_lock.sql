-- One-time migration: lock flares to first-responder-wins.
-- Run this in the Supabase SQL editor.
--
-- Step 1 deletes any duplicate responses that exist today, keeping the
-- earliest per flare. Necessary because the unique constraint can't be
-- created while duplicates exist.
--
-- Step 2 adds the UNIQUE constraint that enforces "one response per flare"
-- atomically at the database level.
--
-- Step 3 is a sanity-check query you can run after to confirm.

-- Step 1: dedupe (keep earliest response per flare).
DELETE FROM flare_responses
WHERE id IN (
  SELECT id FROM (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY flare_id ORDER BY created_at ASC) AS rn
    FROM flare_responses
  ) t
  WHERE t.rn > 1
);

-- Step 2: add the constraint.
ALTER TABLE flare_responses
  ADD CONSTRAINT flare_responses_one_per_flare UNIQUE (flare_id);

-- Step 3 (optional sanity check): every flare should now have at most one row.
-- The query below should return zero rows.
-- SELECT flare_id, COUNT(*) FROM flare_responses GROUP BY flare_id HAVING COUNT(*) > 1;
