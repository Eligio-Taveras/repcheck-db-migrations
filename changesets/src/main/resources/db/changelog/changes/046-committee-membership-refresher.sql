-- Migration 046: Committee-membership-refresher pipeline support
--
-- Evolves the existing committees, committee_members, and
-- bill_committee_referrals tables (created in migration 002, standardized in
-- 011, enum-typed in 013) to support the new committee-membership-refresher
-- pipeline. That pipeline ingests master committee data from Congress.gov API
-- and temporal per-congress membership from chamber XML feeds.
--
-- Changes:
--   1. committees: add is_current flag for active/inactive tracking
--   2. committee_members: add side, rank, congress columns; widen UNIQUE
--      constraint to include congress (membership is per-congress, not global)
--   3. bill_committee_referrals: add report_date; widen UNIQUE constraint
--      to include activity_name (a bill can have multiple referral activities)
--   4. amendments: add sponsor_committee_id FK to committees
--
-- All statements use IF NOT EXISTS / IF EXISTS guards for idempotency.

-- ===========================================================================
-- 1. COMMITTEES — add is_current flag
--    Tracks whether a committee is currently active. NULL for rows that
--    predate the refresher pipeline; the pipeline sets TRUE/FALSE on every
--    sync cycle based on the Congress.gov API isCurrent field.
-- ===========================================================================

ALTER TABLE committees ADD COLUMN IF NOT EXISTS is_current BOOLEAN;

COMMENT ON COLUMN committees.is_current IS
    'Whether the committee is currently active per Congress.gov API isCurrent field. NULL for legacy rows not yet touched by the committee-membership-refresher pipeline.';

-- ===========================================================================
-- 2. COMMITTEE_MEMBERS — add temporal membership columns
--    The refresher pipeline ingests membership per-congress from chamber
--    XML feeds. Each row represents one member's role on one committee
--    during one congress. The existing UNIQUE (committee_id, member_id)
--    must be widened to (committee_id, member_id, congress) because a
--    member can serve on the same committee across multiple congresses
--    with different positions/sides/ranks.
-- ===========================================================================

-- 2a. New columns
ALTER TABLE committee_members ADD COLUMN IF NOT EXISTS side    TEXT;
ALTER TABLE committee_members ADD COLUMN IF NOT EXISTS rank    INT;
ALTER TABLE committee_members ADD COLUMN IF NOT EXISTS congress INT;

COMMENT ON COLUMN committee_members.side IS
    'Majority/Minority side assignment from chamber XML feeds. NULL when not available (e.g., Joint committees).';
COMMENT ON COLUMN committee_members.rank IS
    'Seniority rank within the committee for this congress. Lower numbers = more senior. NULL when not provided.';
COMMENT ON COLUMN committee_members.congress IS
    'Congress number (e.g., 118, 119) for this membership record. Enables temporal queries — same member can serve on same committee across multiple congresses.';

-- 2b. Widen unique constraint: (committee_id, member_id) -> (committee_id, member_id, congress)
--     The old constraint blocks multi-congress membership rows for the same
--     (committee, member) pair. Drop it and replace with the wider variant.
ALTER TABLE committee_members DROP CONSTRAINT IF EXISTS uq_committee_members;

CREATE UNIQUE INDEX IF NOT EXISTS uq_committee_members_congress
    ON committee_members (committee_id, member_id, congress);

-- 2c. Index on congress for temporal queries
CREATE INDEX IF NOT EXISTS idx_committee_members_congress
    ON committee_members (congress);

-- ===========================================================================
-- 3. BILL_COMMITTEE_REFERRALS — add report_date; widen UNIQUE
--    A bill can be referred to the same committee multiple times with
--    different activities (e.g., 'Referred to' then 'Hearings Held'
--    then 'Markup'). The existing UNIQUE (bill_id, committee_id) blocks
--    this. Widen to (bill_id, committee_id, activity_name).
-- ===========================================================================

ALTER TABLE bill_committee_referrals ADD COLUMN IF NOT EXISTS report_date DATE;

COMMENT ON COLUMN bill_committee_referrals.report_date IS
    'Date the committee reported the bill (filed its report). NULL when no report has been filed.';

-- Widen unique constraint: (bill_id, committee_id) -> (bill_id, committee_id, activity_name)
ALTER TABLE bill_committee_referrals DROP CONSTRAINT IF EXISTS uq_bill_committee_referrals;

CREATE UNIQUE INDEX IF NOT EXISTS uq_bill_committee_referrals_activity
    ON bill_committee_referrals (bill_id, committee_id, activity_name);

-- ===========================================================================
-- 4. AMENDMENTS — add sponsor_committee_id FK
--    Some amendments are sponsored by committees rather than individual
--    members. The existing sponsor_member_id covers member sponsors;
--    this column covers committee sponsors.
-- ===========================================================================

ALTER TABLE amendments ADD COLUMN IF NOT EXISTS sponsor_committee_id BIGINT;

ALTER TABLE amendments
    ADD CONSTRAINT amendments_sponsor_committee_id_fkey
    FOREIGN KEY (sponsor_committee_id) REFERENCES committees(id);

CREATE INDEX IF NOT EXISTS idx_amendments_sponsor_committee_id
    ON amendments (sponsor_committee_id) WHERE sponsor_committee_id IS NOT NULL;

COMMENT ON COLUMN amendments.sponsor_committee_id IS
    'FK to committees(id) when the amendment sponsor is a committee rather than an individual member. Mutually exclusive with sponsor_member_id in practice, but not enforced by CHECK (some amendments list both).';
