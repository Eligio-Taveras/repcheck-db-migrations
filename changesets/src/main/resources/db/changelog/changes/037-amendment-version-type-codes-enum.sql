-- Migration 037: Add amendment text-version codes to text_version_code_type enum
--
-- The amendments-pipeline (Component 7) writes amendment text-version rows whose
-- `version_type_code` discriminator (per Congress.gov /amendment/{c}/{t}/{n}/text)
-- is "Submitted" or "Modified". These are NOT bill-style short codes — they're
-- the literal version-type strings the API emits for amendments.
--
-- Failure mode without this migration:
--   ERROR: invalid input value for enum text_version_code_type: "Submitted"
--   when the amendment-text pipeline tries to insert a row with
--   amendment_text_versions.version_type_code = 'Submitted'.
--
-- Also adds 'HTML' to format_type_enum — the amendment-text DTOs surface
-- AmendmentFormatDTO.type values "PDF" or "HTML", and the existing
-- format_type_enum {Formatted Text, PDF, Formatted XML} cannot store "HTML".
-- Without this addition the format_type column for amendment text rows would
-- reject API-sourced format strings.
--
-- Both ALTER TYPE ADD VALUE statements use IF NOT EXISTS for idempotency.
-- They run within Liquibase's default per-changeset transaction — PostgreSQL
-- 12+ allows ALTER TYPE ADD VALUE inside a transaction; the new values just
-- can't be USED in the same transaction. Subsequent migrations (038, 039,
-- 040) that reference these values commit cleanly because this migration
-- commits first.
--
-- Precedent: migrations 016, 021, 030 (text_version_code expansions) and 033
-- (party_type expansion) follow the same in-transaction pattern.

ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'Submitted';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'Modified';

ALTER TYPE format_type_enum ADD VALUE IF NOT EXISTS 'HTML';
