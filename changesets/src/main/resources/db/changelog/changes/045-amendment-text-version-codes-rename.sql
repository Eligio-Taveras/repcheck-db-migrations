-- Migration 045: Rename amendment_text_version_code_type values to short codes
--
-- Per amendments-pipeline §7.6 spec L3 the dedicated amendment text version
-- enum stores the short codes ('SUB', 'MOD'). Migration 037 created the enum
-- with the long-form labels ('Submitted', 'Modified') from the upstream
-- Congress.gov /amendment/.../text "type" field; that placed the wire-format
-- translation at the DB boundary, which forced §7.6 to add a translation shim
-- (AmendmentTextVersionTypeMapping) just to bridge short→long on insert.
--
-- This migration aligns the enum with the spec by renaming the values in place.
-- ALTER TYPE ... RENAME VALUE updates only the catalog (O(1)); existing rows
-- referencing the values automatically pick up the new label, so there is no
-- data rewrite. Combined with the fact that amendment_text_versions has zero
-- rows in every environment today, the rename is fully safe.
--
-- The §7.5 selector already emits the short codes on the wire, so after this
-- migration lands the §7.6 shim becomes dead code (handled in the data-ingestion
-- follow-up PR). The DTO boundary at AmendmentTextItemDTO.type continues to
-- carry the upstream long-form value — the §7.5 selector translates that to
-- the short code at the wire-format boundary, which is distinct from the DB
-- enum value space.

ALTER TYPE amendment_text_version_code_type RENAME VALUE 'Submitted' TO 'SUB';
ALTER TYPE amendment_text_version_code_type RENAME VALUE 'Modified'  TO 'MOD';
