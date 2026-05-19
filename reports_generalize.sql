-- Generalize the `reports` table so flares and stars can be reported alongside
-- dots. Run this once in the Supabase SQL editor before deploying the matching
-- index.html change; until the schema is in place, report inserts from
-- non-message popups will fail with "column subject_id does not exist".
--
-- Before:
--   reports(id, message_id uuid NOT NULL, created_at)
-- After:
--   reports(id, kind text NOT NULL CHECK (kind IN ('message','flare','star')),
--           subject_id uuid NOT NULL, created_at)
--
-- The triage query in CLAUDE.md becomes:
--   SELECT kind, subject_id, count(*) FROM reports
--   GROUP BY kind, subject_id ORDER BY count(*) DESC;
-- Then DELETE FROM the matching kind's table by id.

BEGIN;

-- 1. Add the kind column with the legacy default so old rows are valid.
ALTER TABLE reports ADD COLUMN IF NOT EXISTS kind text;
UPDATE reports SET kind = 'message' WHERE kind IS NULL;
ALTER TABLE reports ALTER COLUMN kind SET NOT NULL;

-- 2. Constrain to known kinds. Idempotent guard so re-runs don't blow up.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reports_kind_check'
  ) THEN
    ALTER TABLE reports
      ADD CONSTRAINT reports_kind_check CHECK (kind IN ('message','flare','star'));
  END IF;
END $$;

-- 3. Rename the column. Skip if the rename has already happened.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'reports' AND column_name = 'message_id'
  ) THEN
    ALTER TABLE reports RENAME COLUMN message_id TO subject_id;
  END IF;
END $$;

COMMIT;
