-- Widen uq_member_party_history from (member_id, start_year) to
-- (member_id, start_year, party_name).
--
-- Background: a member of Congress can legally switch parties at any time
-- during their term, with no restriction on how many switches per year. While
-- rare in practice (~20 switches in the 50 years 1947–1997), Congress.gov's
-- /member/{bioguideId} response models this with a partyHistory[] array where
-- each entry carries (partyName, partyAbbreviation, startYear). Two entries in
-- the same startYear with different partyName values are valid.
--
-- The previous 2-column constraint would collapse such a mid-year switch into
-- a single row (the writer uses INSERT ... ON CONFLICT DO NOTHING, so the
-- second party in the same year would be silently dropped). The 3-column
-- constraint preserves every reported party affiliation.
--
-- The ingestion pipeline's party-history writer must also widen its
-- ON CONFLICT target from (member_id, start_year) to
-- (member_id, start_year, party_name) to match.

-- Defensive: no actual data should need cleanup here (2-col UNIQUE was
-- restored only one migration ago and no production data has been written
-- against it that the widening would invalidate). We simply drop the old
-- constraint and add the wider one.
ALTER TABLE member_party_history
    DROP CONSTRAINT uq_member_party_history;

ALTER TABLE member_party_history
    ADD CONSTRAINT uq_member_party_history UNIQUE (member_id, start_year, party_name);
