-- Migration 042: votes — split legislation_type into discriminator + per-kind subtype columns
--
-- Today the `votes` table has a single `legislation_type bill_type_enum`
-- column (originally TEXT in migration 001, retyped to bill_type_enum in
-- migration 013 §votes). That shape can only carry bill-side identifiers
-- — amendment votes (vote_type = 'Amendment' on a House/Senate roll where
-- the legislation is a SAMDT/HAMDT) cannot be stored with type fidelity.
--
-- The new shape is:
--   * legislation_type legislation_type_enum  -- discriminator: 'BILL' / 'AMENDMENT' (created in 041)
--   * bill_type        bill_type_enum         -- existing column, RENAMED from legislation_type (no data loss)
--   * amendment_type   amendment_type_enum    -- new
--
-- The CHECK constraint enforces the kind/subtype invariant: the subtype
-- column matching the discriminator must be populated, the other one must
-- be NULL. All-NULL is also allowed (procedural votes with no associated
-- legislation — vote_type = 'Cloture' on a motion, etc.).
--
-- Backfill: pre-existing rows have their old legislation_type populated iff
-- the vote was tied to a bill. Renaming legislation_type -> bill_type
-- preserves that data verbatim. The UPDATE then sets the new discriminator
-- to 'BILL' for any row carrying a bill_type, leaving rows with no
-- legislation (procedural votes) at NULL/NULL/NULL — all three states are
-- valid under the CHECK.
--
-- Coordinated with the parallel repcheck-shared-models bump that introduces
-- LegislationType + adds legislationType / billType / amendmentType to
-- VoteDO. Repository-level SELECTs use explicit column lists per CLAUDE.md
-- "no SELECT *", so the physical column order added below is harmless to
-- downstream Doobie auto-derived Read[VoteDO].

-- ===========================================================================
-- 1. Rename existing legislation_type column to bill_type — preserves all data
-- ===========================================================================
--
-- The pre-013 column was TEXT; 013 retyped it to bill_type_enum. The semantic
-- name matching its actual content (a bill_type_enum value) is `bill_type`,
-- so the rename brings the schema in line with reality. RENAME COLUMN is
-- a metadata-only operation and preserves all rows verbatim.
ALTER TABLE votes RENAME COLUMN legislation_type TO bill_type;

-- ===========================================================================
-- 2. Add the new amendment_type and legislation_type columns
-- ===========================================================================
--
-- Both are nullable: legislation_type=NULL is the canonical "no legislation"
-- state (procedural votes); amendment_type=NULL is required whenever the
-- discriminator isn't 'AMENDMENT'.
ALTER TABLE votes ADD COLUMN amendment_type   amendment_type_enum;
ALTER TABLE votes ADD COLUMN legislation_type legislation_type_enum;

-- ===========================================================================
-- 3. Backfill the discriminator before the CHECK is added
-- ===========================================================================
--
-- Any existing row with bill_type populated implicitly described a vote on a
-- bill — set legislation_type='BILL' so those rows pass the CHECK. Rows
-- with bill_type IS NULL stay at legislation_type IS NULL — that's the
-- all-NULL branch of the CHECK and represents votes with no associated
-- legislation (procedural / motion votes). Must run BEFORE the CHECK is
-- added so the constraint validates clean.
UPDATE votes SET legislation_type = 'BILL' WHERE bill_type IS NOT NULL;

-- ===========================================================================
-- 4. Enforce the kind/subtype invariant
-- ===========================================================================
--
-- The CHECK enforces "exactly one subtype column populated, matching the
-- discriminator" — three valid shapes:
--   (NULL, NULL, NULL)                   — no legislation (procedural / motion vote)
--   ('BILL',      NOT NULL, NULL)        — bill vote
--   ('AMENDMENT', NULL,     NOT NULL)    — amendment vote
--
-- Encoded as a CASE expression so the result is always a definite boolean.
-- A naive `OR`-of-three-AND-clauses CHECK would let a row like
-- (legislation_type=NULL, bill_type='hr', amendment_type=NULL) slip through:
-- branch 1 evaluates to FALSE (because bill_type IS NULL is FALSE), but
-- branches 2/3 contain `legislation_type = 'BILL'` / `'AMENDMENT'` which
-- evaluate to NULL (UNKNOWN) when legislation_type IS NULL. FALSE OR NULL
-- OR NULL is NULL, and PostgreSQL CHECK constraints accept any non-FALSE
-- value (including NULL). The CASE form sidesteps the trap.
ALTER TABLE votes ADD CONSTRAINT votes_legislation_type_subtype_check CHECK (
    CASE
        WHEN legislation_type IS NULL        THEN bill_type IS NULL     AND amendment_type IS NULL
        WHEN legislation_type = 'BILL'       THEN bill_type IS NOT NULL AND amendment_type IS NULL
        WHEN legislation_type = 'AMENDMENT'  THEN bill_type IS NULL     AND amendment_type IS NOT NULL
        ELSE FALSE
    END
);

COMMENT ON COLUMN votes.legislation_type IS
    'Discriminator: BILL | AMENDMENT | NULL. NULL means the vote has no associated legislation (procedural / motion votes). When non-NULL, the matching subtype column (bill_type or amendment_type) must be populated and the other must be NULL — enforced by votes_legislation_type_subtype_check.';
COMMENT ON COLUMN votes.bill_type IS
    'Bill type code (formerly legislation_type) — populated iff legislation_type = BILL. Renamed in migration 042 to disambiguate from the new legislation_type discriminator.';
COMMENT ON COLUMN votes.amendment_type IS
    'Amendment type code — populated iff legislation_type = AMENDMENT. Lets the votes pipeline store amendment votes (HAMDT/SAMDT/SUAMDT) with full type fidelity instead of cramming them into a bill-shaped column.';
