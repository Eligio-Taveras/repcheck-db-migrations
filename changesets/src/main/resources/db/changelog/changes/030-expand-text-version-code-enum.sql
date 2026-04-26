-- Migration 030: Expand text_version_code_type enum (third batch)
--
-- Adds 6 short codes encountered in Congress.gov API responses but not yet
-- declared in the enum. Surfaced empirically in the local stack via
-- `invalid input value for enum text_version_code_type: "..."` errors when
-- bill-text-availability-checker tried to insert text-version rows for bills
-- whose latest version came back with descriptive types we hadn't mapped to
-- short codes.
--
--   EAH (Engrossed Amendment House)    — counterpart to EAS already in enum
--   LTH (Laid on Table in House)        — surfaced empirically; procedural
--   LTS (Laid on Table in Senate)       — preemptive counterpart to LTH
--   PRL (Private Law)                   — surfaced empirically; counterpart to PL (Public Law)
--   RCS (Reference Change Senate)       — preemptive counterpart to RCH already in enum
--   RIH (Referral Instructions House)   — preemptive counterpart to RIS already in enum
--
-- Coordinated with a data-ingestion follow-up that adds the long-form →
-- short-code mappings to TextVersionSelector.VersionTypeToCode (e.g.,
-- "Engrossed Amendment House" → "EAH"). Without that follow-up the long-form
-- names would continue to fall through the conversion unchanged. The two
-- changes are gated by this migration's runner-version bump.

ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'EAH';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'LTH';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'LTS';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'PRL';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'RCS';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'RIH';
