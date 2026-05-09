-- Migration 044: Unique constraint on amendment_text_versions natural key
--
-- Per amendments-pipeline §7.6 spec ("Schema additions"):
--     UNIQUE (amendment_id, version_type_code, format_type)
--
-- Column names in the deployed schema differ from the spec text — migration 039
-- reused the existing `version_type` column (renamed from migration 007) instead
-- of introducing the spec's `version_type_code`. The constraint is therefore
-- defined against (amendment_id, version_type, format_type), which is the same
-- (amendment, code, format) tuple the spec calls out.
--
-- Why this matters: the §7.6 processor's idempotent upsert wants the canonical
--   INSERT ... ON CONFLICT (amendment_id, version_type, format_type) DO UPDATE
-- form. Postgres requires a matching unique constraint to use that conflict
-- target — without one, the statement errors at runtime. The §7.6 PR worked
-- around the gap by composing a SELECT-then-INSERT/UPDATE inside one
-- ConnectionIO; this migration removes the need for that workaround.
--
-- Safety: amendment_text_versions has 0 rows in every environment (verified per
-- migration 039 comment + dev DB inspection), so the constraint addition cannot
-- conflict with existing data.
--
-- Naming: matches the existing convention (`uq_<table>_<columns-or-purpose>`)
-- used by uq_member_party_history, uq_bills_natural_key, uq_section_per_version,
-- etc.

ALTER TABLE amendment_text_versions
    ADD CONSTRAINT uq_amendment_text_versions_amendment_type_format
    UNIQUE (amendment_id, version_type, format_type);

COMMENT ON CONSTRAINT uq_amendment_text_versions_amendment_type_format ON amendment_text_versions IS
    'Natural key per amendments-pipeline §7.6: one row per (amendment, version code, format). Backs the canonical ON CONFLICT upsert in the §7.6 processor.';
