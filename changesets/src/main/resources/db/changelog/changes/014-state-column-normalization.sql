-- =============================================================================
-- RepCheck Database Schema — V14 State Column Normalization
-- =============================================================================
-- Normalizes all state columns to store 2-letter codes (matching the
-- us_states.state_code PK and the Scala UsState Doobie Put which now
-- writes .code instead of .fullName).
--
-- Converts existing full-name values (e.g., "California") to 2-letter codes
-- (e.g., "CA") using a JOIN against the us_states reference table.
--
-- Adds FK constraints to us_states.state_code on non-history tables.
-- History tables use codes but intentionally have NO FK constraints
-- (by design — archived data must survive reference changes).
--
-- Depends on: 013-enum-type-constraints.sql
-- =============================================================================

-- ===========================================================================
-- PHASE 1: Convert existing full-name values to 2-letter codes
-- Uses us_states.state_name → state_code lookup. NULL values are preserved.
-- Values that are already 2-letter codes (LENGTH <= 2) are left as-is.
-- ===========================================================================

-- members.state — was "full state name from API"
UPDATE members m
SET state = us.state_code
FROM us_states us
WHERE m.state IS NOT NULL
  AND LENGTH(m.state) > 2
  AND UPPER(m.state) = UPPER(us.state_name);

-- member_terms.state_code — comment said "two-letter code" but Doobie wrote fullName
UPDATE member_terms mt
SET state_code = us.state_code
FROM us_states us
WHERE mt.state_code IS NOT NULL
  AND LENGTH(mt.state_code) > 2
  AND UPPER(mt.state_code) = UPPER(us.state_name);

-- member_terms.state_name — normalize to full name from reference table
-- (leave as TEXT, no conversion needed — already stores full names)

-- vote_positions.state_at_vote
UPDATE vote_positions vp
SET state_at_vote = us.state_code
FROM us_states us
WHERE vp.state_at_vote IS NOT NULL
  AND LENGTH(vp.state_at_vote) > 2
  AND UPPER(vp.state_at_vote) = UPPER(us.state_name);

-- member_history.state
UPDATE member_history mh
SET state = us.state_code
FROM us_states us
WHERE mh.state IS NOT NULL
  AND LENGTH(mh.state) > 2
  AND UPPER(mh.state) = UPPER(us.state_name);

-- member_term_history.state_code
UPDATE member_term_history mth
SET state_code = us.state_code
FROM us_states us
WHERE mth.state_code IS NOT NULL
  AND LENGTH(mth.state_code) > 2
  AND UPPER(mth.state_code) = UPPER(us.state_name);

-- vote_history_positions.state_at_vote
UPDATE vote_history_positions vhp
SET state_at_vote = us.state_code
FROM us_states us
WHERE vhp.state_at_vote IS NOT NULL
  AND LENGTH(vhp.state_at_vote) > 2
  AND UPPER(vhp.state_at_vote) = UPPER(us.state_name);

-- user_legislator_pairings.state — comment said "two-letter state code"
-- Should already be 2-letter codes, but normalize just in case
UPDATE user_legislator_pairings ulp
SET state = us.state_code
FROM us_states us
WHERE ulp.state IS NOT NULL
  AND LENGTH(ulp.state) > 2
  AND UPPER(ulp.state) = UPPER(us.state_name);

-- ===========================================================================
-- PHASE 2: Add FK constraints on non-history tables
-- History tables intentionally have NO FK constraints by design.
-- ===========================================================================

ALTER TABLE members
    ADD CONSTRAINT fk_members_state
    FOREIGN KEY (state) REFERENCES us_states(state_code);

ALTER TABLE member_terms
    ADD CONSTRAINT fk_member_terms_state_code
    FOREIGN KEY (state_code) REFERENCES us_states(state_code);

ALTER TABLE vote_positions
    ADD CONSTRAINT fk_vote_positions_state_at_vote
    FOREIGN KEY (state_at_vote) REFERENCES us_states(state_code);

ALTER TABLE user_legislator_pairings
    ADD CONSTRAINT fk_user_legislator_pairings_state
    FOREIGN KEY (state) REFERENCES us_states(state_code);
