-- Migration 024: Expand vote_cast_type + vote_type_enum for Speaker-election support
--
-- House Speaker elections (roll call #2 at the start of each Congress, plus any
-- mid-term vacancy vote) have two unusual properties the existing enums can't
-- represent:
--   1. members.results[].voteCast contains CANDIDATE NAMES ("Jeffries",
--      "Scalise", "Johnson (LA)") rather than Yea/Nay/Present/NotVoting/Absent.
--   2. The vote isn't any of the 8 existing VoteType values (Passage, Amendment,
--      etc.) — it's an officer election.
--
-- This migration adds:
--   - 'Candidate' to vote_cast_type: represents "member voted for a candidate"
--     with the candidate's name stored in a separate column (see migration 025).
--   - 'Election' to vote_type_enum: covers Speaker elections today + any future
--     officer-election vote (Clerk, Sergeant-at-Arms, etc.).
--
-- Isolated from migration 025 (which adds the vote_cast_candidate_name column +
-- CHECK constraint using 'Candidate') because ALTER TYPE ADD VALUE in PostgreSQL
-- 12+ can run inside a transaction but the new value cannot be used in the same
-- transaction. Splitting ensures each changeset is commit-clean.

ALTER TYPE vote_cast_type ADD VALUE IF NOT EXISTS 'Candidate';
ALTER TYPE vote_type_enum ADD VALUE IF NOT EXISTS 'Election';
