-- Restore UNIQUE (member_id, start_year) on member_party_history.
--
-- Background: migration 001 created this table with
--   CONSTRAINT uq_member_party_history UNIQUE (member_id, start_year)
-- while member_id was TEXT. During migration 011's TEXT->BIGINT conversion
-- (members, etc.) the member_id column was dropped and rebuilt, which silently
-- removed the UNIQUE constraint that referenced it. Migration 011 never
-- recreated it. This migration restores the original intent.
--
-- The ingestion pipeline's party-history writer relies on this constraint for
-- idempotency via `INSERT ... ON CONFLICT (member_id, start_year) DO NOTHING`.

-- Defensive cleanup in case duplicates slipped in while the constraint was
-- missing. Keeps the row with the smallest id per (member_id, start_year).
DELETE FROM member_party_history a
USING member_party_history b
WHERE a.id > b.id
  AND a.member_id = b.member_id
  AND a.start_year = b.start_year;

ALTER TABLE member_party_history
    ADD CONSTRAINT uq_member_party_history UNIQUE (member_id, start_year);
