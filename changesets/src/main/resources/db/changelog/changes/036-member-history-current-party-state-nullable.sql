-- Migration 036: member_history.current_party and state nullable for placeholder support
--
-- Follow-on to migration 035 (member_history.update_date, first_name, last_name nullable). 035
-- caught three of the columns that needed the placeholder-safety relaxation but missed two:
-- current_party and state. members table allows NULL for both (per migration 012 §1, "Relax NOT
-- NULL constraints for placeholder support") but member_history was historically more strict — a
-- design asymmetry that breaks the archive INSERT chain whenever the source row is a placeholder.
--
-- Empirically: the round-trip integration test in data-ingestion (MemberPlaceholderRoundTrip
-- IntegrationSpec) failed against the v0.1.32 runner with `null value in column "current_party"
-- of relation "member_history" violates not-null constraint`, after migration 035 fixed the
-- update_date / first_name / last_name asymmetry. This migration closes the remaining gap so
-- member_history's nullability mirrors members exactly.
--
-- Verified via:
--   SELECT m.column_name, m.is_nullable, h.is_nullable
--   FROM information_schema.columns m
--   JOIN information_schema.columns h USING (column_name)
--   WHERE m.table_name='members' AND h.table_name='member_history'
--     AND m.is_nullable != h.is_nullable;
-- which after this migration returns zero rows.
--
-- Pairs with: data-ingestion test PR <pending> (archiver fix + round-trip test) and the in-DB
-- ALTER applied as a one-shot to the dev AlloyDB.

ALTER TABLE member_history ALTER COLUMN current_party DROP NOT NULL;
ALTER TABLE member_history ALTER COLUMN state         DROP NOT NULL;
