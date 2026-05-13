-- ─────────────────────────────────────────────────────────────────────────
-- dropadot — pg_cron schedule
-- ─────────────────────────────────────────────────────────────────────────
-- Source of truth for the daily midnight-UTC reset that backs the privacy
-- policy promise ("Everything you post is deleted at midnight UTC each
-- day"). If pg_cron is reinstalled, the project is migrated, or the cron
-- job is dropped, run this file in the Supabase SQL editor to restore it.
--
-- The job runs as the postgres superuser and bypasses RLS. TRUNCATE is
-- used (not DELETE) because it is atomic, fast, and does not flood
-- realtime subscribers with one DELETE event per row. Open clients pick
-- up the cleared state via the `scheduleMidnight()` reload in index.html.
--
-- Inspect:    SELECT * FROM cron.job WHERE jobname = 'midnight-utc-reset';
-- Run log:    SELECT * FROM cron.job_run_details WHERE jobid =
--             (SELECT jobid FROM cron.job WHERE jobname = 'midnight-utc-reset')
--             ORDER BY start_time DESC LIMIT 5;
-- Remove:     SELECT cron.unschedule('midnight-utc-reset');
-- ─────────────────────────────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- cron.schedule() with an existing jobname updates the schedule in place
-- on current pg_cron versions, so re-running this file is idempotent.
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
