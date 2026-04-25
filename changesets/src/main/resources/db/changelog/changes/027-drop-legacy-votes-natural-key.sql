-- Migration 027: replace the legacy `uq_votes_natural_key` with a session-aware composite key
--
-- Background
-- ----------
-- Migration 001 declared `uq_votes_natural_key UNIQUE (congress, chamber, roll_number)` as the
-- "natural key" of a vote — but Senate roll-call numbers RESET at the start of each session,
-- so (congress=118, chamber='Senate', roll_number=22) appears in BOTH session 1 and session 2
-- of the 118th Congress. House numbering also restarts per congress / session. The 3-tuple is
-- therefore not a true natural key.
--
-- Migration 011 (`011-pk-standardization.sql`) introduced a `natural_key` TEXT column on the
-- `votes` table with its own `uq_votes_natural_key_pk` UNIQUE constraint. The application code
-- (votes-pipeline `DoobieVoteRepository`) writes the canonical
-- `{congress}-{chamber}-{session}-{rollNumber}` form into that column and uses
-- `INSERT ... ON CONFLICT (natural_key) DO UPDATE` for idempotent upserts. The string form
-- includes the session number and is the correct identity. 011 added that constraint but
-- never dropped the legacy 3-tuple one — they coexisted.
--
-- Postgres evaluates ALL unique constraints during INSERT regardless of which one ON CONFLICT
-- targets, so re-ingesting Congress 118 session 2 (whose roll-numbers overlap session 1) hit
-- the legacy constraint with a duplicate-key error even though the application's
-- ON CONFLICT (natural_key) clause would have correctly produced an UPDATE if the legacy
-- constraint hadn't fired first.
--
-- Fix
-- ---
-- 1. Drop the legacy 3-tuple constraint (semantically wrong).
-- 2. Tighten `session_number` to NOT NULL — the DTO→DO conversion always populates it from the
--    fetch URL, so every existing row already has a value (verified pre-migration with
--    `SELECT COUNT(*) FROM votes WHERE session_number IS NULL` → 0). Making it NOT NULL is a
--    no-op for current data and lets us declare a clean composite key without `NULLS NOT
--    DISTINCT`.
-- 3. Add a session-aware composite UNIQUE on (congress, chamber, session_number, roll_number).
--    This is the TRUE natural key of a vote — defense in depth alongside the existing TEXT
--    natural_key constraint. If any future code regression ever produces an inconsistent
--    natural_key string, the composite still catches the underlying duplicate at the column
--    level instead of letting it slip through to corrupt downstream tables.
--
-- The application code does NOT need to change: ON CONFLICT (natural_key) keeps working
-- because the natural_key string remains the single conflict target during idempotent
-- upserts. The composite constraint is purely a guard rail.
--
-- Surfaced via P6 docker-compose validation when votes-pipeline iterated congress 118
-- session 2 and hit duplicate-key errors against rows ingested under session 1 in the
-- same run.

ALTER TABLE votes DROP CONSTRAINT IF EXISTS uq_votes_natural_key;

ALTER TABLE votes ALTER COLUMN session_number SET NOT NULL;

ALTER TABLE votes
    ADD CONSTRAINT uq_votes_congress_chamber_session_roll
        UNIQUE (congress, chamber, session_number, roll_number);
