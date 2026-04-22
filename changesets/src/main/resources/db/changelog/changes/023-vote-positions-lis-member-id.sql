-- =============================================================================
-- Migration 023: Dual-identity vote_positions (member_id XOR lis_member_id)
-- =============================================================================
-- House votes populate vote_positions.member_id (FK -> members.id).
-- Senate votes populate vote_positions.lis_member_id (FK -> lis_members.id).
-- Exactly one identity per row; the XOR CHECK enforces this.
--
-- Adds a read-side helper VIEW (vote_positions_resolved) that unifies both
-- chambers via member_lis_mapping so scoring consumers don't special-case.
--
-- NOTE: vote_positions already has `id BIGSERIAL PRIMARY KEY` (added in
-- migration 011) and `uq_vote_positions UNIQUE (vote_id, member_id)` as the
-- "natural" uniqueness constraint replacing the original composite PK. This
-- migration drops that UNIQUE constraint (partial indexes replace it) and
-- relaxes member_id so it can be NULL when a Senate row uses lis_member_id.
-- =============================================================================

-- 1. Drop the old (vote_id, member_id) UNIQUE constraint; it will be replaced
--    by two partial UNIQUE indexes that allow per-chamber identity columns.
ALTER TABLE vote_positions DROP CONSTRAINT uq_vote_positions;

-- 2. member_id becomes nullable; lis_member_id added with FK.
ALTER TABLE vote_positions ALTER COLUMN member_id DROP NOT NULL;
ALTER TABLE vote_positions ADD COLUMN lis_member_id BIGINT NULL
    REFERENCES lis_members(id);

-- 3. XOR: exactly one of member_id, lis_member_id populated.
ALTER TABLE vote_positions ADD CONSTRAINT chk_vp_xor_identity CHECK (
    (member_id IS NOT NULL AND lis_member_id IS NULL) OR
    (member_id IS NULL AND lis_member_id IS NOT NULL)
);

-- 4. Partial UNIQUE indexes replace the old composite UNIQUE semantics.
CREATE UNIQUE INDEX uq_vp_vote_member ON vote_positions (vote_id, member_id)
    WHERE member_id IS NOT NULL;
CREATE UNIQUE INDEX uq_vp_vote_lis ON vote_positions (vote_id, lis_member_id)
    WHERE lis_member_id IS NOT NULL;

-- 5. Lookup index for refresher (find all unmapped-senator positions fast).
CREATE INDEX idx_vp_lis_member ON vote_positions (lis_member_id)
    WHERE lis_member_id IS NOT NULL;

-- 6. Read-side helper VIEW for scoring consumers.
--    House arm: pass-through member_id.
--    Senate arm: resolve through member_lis_mapping.
--    Unmapped senators (no mapping entry) are excluded — scoring can't attribute them anyway.
CREATE VIEW vote_positions_resolved AS
SELECT vp.id, vp.vote_id, vp.member_id,
       NULL::BIGINT AS lis_member_id,
       vp.position, vp.party_at_vote, vp.state_at_vote, vp.created_at
FROM vote_positions vp
WHERE vp.member_id IS NOT NULL
UNION ALL
SELECT vp.id, vp.vote_id, mlm.member_id,
       vp.lis_member_id,
       vp.position, vp.party_at_vote, vp.state_at_vote, vp.created_at
FROM vote_positions vp
INNER JOIN member_lis_mapping mlm ON vp.lis_member_id = mlm.lis_member_id
WHERE vp.lis_member_id IS NOT NULL;
