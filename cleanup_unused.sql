-- ─────────────────────────────────────────────────────────────────────────
-- dropadot — drop unused tables, columns, and RPCs (2026-05-12)
-- ─────────────────────────────────────────────────────────────────────────
-- Run this once in the Supabase SQL editor to remove server-side artifacts
-- for features that were deleted from the client:
--   - Drawing Realm  → drops tiles, tiles_archive, tile_reports
--   - Cast           → drops casts, cast_turns + the insert_cast_turn RPC
--   - Dormant view_count column + RPC on messages (unreachable since
--     2026-05-03; tracked as item #7 in pending_audit.md)
--
-- Safe to re-run: every statement uses IF EXISTS. Update cron.sql first
-- (or run it after this) so the midnight TRUNCATE no longer references
-- the dropped tables — otherwise the next midnight job will error out.
-- ─────────────────────────────────────────────────────────────────────────

-- Drawing Realm
DROP TABLE IF EXISTS tile_reports;
DROP TABLE IF EXISTS tiles;
DROP TABLE IF EXISTS tiles_archive;

-- Cast
DROP FUNCTION IF EXISTS insert_cast_turn(uuid, text, text);
DROP TABLE IF EXISTS cast_turns;
DROP TABLE IF EXISTS casts;

-- Dormant view_count column + RPC on messages
ALTER TABLE messages DROP COLUMN IF EXISTS view_count;
DROP FUNCTION IF EXISTS increment_message_view_count(uuid);
