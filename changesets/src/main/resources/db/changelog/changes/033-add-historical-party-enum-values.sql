-- Migration 033: Add historical party affiliation values to party enums
--
-- Surfaced empirically when member-profile-pipeline began processing the full
-- members backlog from the recovered AlloyDB volume (~5400 members across 119
-- congresses). Joe Lieberman (L000304) caucused with Democrats but registered
-- as Independent from 2007–2013, and Congress.gov returns his party affiliation
-- for that period as "Independent Democrat" / "ID" — values that didn't exist
-- in the party_type and party_abbreviation_type enums declared in migration 013.
--
-- Failure mode without this migration:
--   ERROR: invalid input value for enum party_type: "Independent Democrat"
--   INSERT INTO member_party_history ... VALUES (..., 'Independent Democrat'::party_type, 'ID'::party_abbreviation_type, 2007)
--
-- The mapping is intentionally narrow — only the values currently observed in
-- the wild get added. If new historical labels surface later (Whig, Federalist,
-- Independent Republican, etc.) they get follow-up migrations rather than a
-- preemptive batch, since the long tail is hard to enumerate without seeing
-- which ones the API actually emits.

ALTER TYPE party_type ADD VALUE IF NOT EXISTS 'Independent Democrat';

ALTER TYPE party_abbreviation_type ADD VALUE IF NOT EXISTS 'ID';
