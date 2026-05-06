-- Migration 043: vote_history — same legislation_type restructure as votes (042)
--
-- Mirrors migration 042 verbatim against the vote_history audit-trail table.
-- vote_history stores prior versions of votes rows; its column shape must
-- track the votes table so the archive process (DoobieVoteHistoryArchiver)
-- can copy a vote row over without translation.
--
-- See migration 042 for full design rationale; this migration is the exact
-- same set of operations targeting vote_history.

-- ===========================================================================
-- 1. Rename existing legislation_type column to bill_type
-- ===========================================================================
ALTER TABLE vote_history RENAME COLUMN legislation_type TO bill_type;

-- ===========================================================================
-- 2. Add the new amendment_type and legislation_type columns
-- ===========================================================================
ALTER TABLE vote_history ADD COLUMN amendment_type   amendment_type_enum;
ALTER TABLE vote_history ADD COLUMN legislation_type legislation_type_enum;

-- ===========================================================================
-- 3. Backfill the discriminator before the CHECK is added
-- ===========================================================================
UPDATE vote_history SET legislation_type = 'BILL' WHERE bill_type IS NOT NULL;

-- ===========================================================================
-- 4. Enforce the kind/subtype invariant (mirror of votes_legislation_type_subtype_check)
-- ===========================================================================
--
-- See migration 042 for the rationale on the CASE form (a naive OR of three
-- AND clauses leaks NULL CHECK results through, e.g. legislation_type=NULL
-- with bill_type populated would not be rejected).
ALTER TABLE vote_history ADD CONSTRAINT vote_history_legislation_type_subtype_check CHECK (
    CASE
        WHEN legislation_type IS NULL        THEN bill_type IS NULL     AND amendment_type IS NULL
        WHEN legislation_type = 'BILL'       THEN bill_type IS NOT NULL AND amendment_type IS NULL
        WHEN legislation_type = 'AMENDMENT'  THEN bill_type IS NULL     AND amendment_type IS NOT NULL
        ELSE FALSE
    END
);

COMMENT ON COLUMN vote_history.legislation_type IS
    'Discriminator: BILL | AMENDMENT | NULL. Mirrors votes.legislation_type — the archived snapshot must match the live row''s shape so DoobieVoteHistoryArchiver can copy without translation. Enforced by vote_history_legislation_type_subtype_check.';
COMMENT ON COLUMN vote_history.bill_type IS
    'Bill type code (formerly legislation_type) — populated iff legislation_type = BILL. Renamed in migration 043 to mirror votes.bill_type.';
COMMENT ON COLUMN vote_history.amendment_type IS
    'Amendment type code — populated iff legislation_type = AMENDMENT. Mirrors votes.amendment_type so amendment votes round-trip through the archive cleanly.';
