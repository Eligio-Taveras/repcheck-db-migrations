-- Migration 025: vote_positions.vote_cast_candidate_name column + CHECK + VIEW update
--
-- Follows migration 024 (which added 'Candidate' to vote_cast_type). Stores the
-- candidate name a member voted for on Speaker-election-style votes — only
-- populated when `position = 'Candidate'`, NULL otherwise. Enforced by a CHECK
-- constraint so malformed rows can't land.
--
-- Mirrors the column on vote_history_positions so archives preserve the full
-- fidelity of the original vote — a Speaker-election vote archived to
-- vote_history needs the candidate names too, else we lose data on reprocess.
--
-- Also updates the vote_positions_resolved VIEW (introduced in migration 023)
-- to include the new column so scoring consumers see it without having to
-- re-join.
--
-- ==Rationale for the CHECK==
--
-- The column is a semantic invariant on the voteCast enum:
--   position='Candidate'  -> vote_cast_candidate_name required
--   position <> 'Candidate' (any other value) -> vote_cast_candidate_name NULL
--   position IS NULL (unresolved / pending) -> vote_cast_candidate_name NULL
--
-- Without the CHECK we'd rely on application-level enforcement in the Scala
-- converters — fine in principle but a future bug could produce orphan rows
-- where voteCast='Yea' but vote_cast_candidate_name='Scalise'. The CHECK
-- closes that loop at the DB boundary.

-- ----------------------------------------------------------------------------
-- vote_positions: add column + CHECK
-- ----------------------------------------------------------------------------

ALTER TABLE vote_positions ADD COLUMN vote_cast_candidate_name TEXT NULL;

ALTER TABLE vote_positions ADD CONSTRAINT chk_vp_candidate_name CHECK (
    (position = 'Candidate' AND vote_cast_candidate_name IS NOT NULL) OR
    (position <> 'Candidate' AND vote_cast_candidate_name IS NULL) OR
    (position IS NULL AND vote_cast_candidate_name IS NULL)
);

-- ----------------------------------------------------------------------------
-- vote_history_positions: mirror for archive fidelity
-- ----------------------------------------------------------------------------

ALTER TABLE vote_history_positions ADD COLUMN vote_cast_candidate_name TEXT NULL;

ALTER TABLE vote_history_positions ADD CONSTRAINT chk_vhp_candidate_name CHECK (
    (position = 'Candidate' AND vote_cast_candidate_name IS NOT NULL) OR
    (position <> 'Candidate' AND vote_cast_candidate_name IS NULL) OR
    (position IS NULL AND vote_cast_candidate_name IS NULL)
);

-- ----------------------------------------------------------------------------
-- vote_positions_resolved VIEW: drop-and-recreate with the new column
-- ----------------------------------------------------------------------------
-- The VIEW from migration 023 can't be ALTERed to add a column; PG requires
-- DROP + CREATE (or CREATE OR REPLACE, but the arity change means CREATE OR
-- REPLACE rejects it here). Consumers reading the view must re-plan queries;
-- there are none in production yet — scoring engine hasn't consumed it.

DROP VIEW IF EXISTS vote_positions_resolved;

CREATE VIEW vote_positions_resolved AS
SELECT vp.id, vp.vote_id, vp.member_id,
       NULL::BIGINT AS lis_member_id,
       vp.position, vp.party_at_vote, vp.state_at_vote,
       vp.vote_cast_candidate_name,
       vp.created_at
FROM vote_positions vp
WHERE vp.member_id IS NOT NULL
UNION ALL
SELECT vp.id, vp.vote_id, mlm.member_id,
       vp.lis_member_id,
       vp.position, vp.party_at_vote, vp.state_at_vote,
       vp.vote_cast_candidate_name,
       vp.created_at
FROM vote_positions vp
INNER JOIN member_lis_mapping mlm ON vp.lis_member_id = mlm.lis_member_id
WHERE vp.lis_member_id IS NOT NULL;
