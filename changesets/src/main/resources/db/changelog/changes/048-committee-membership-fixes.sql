-- Migration 048: Committee-membership-refresher runtime fixes
--
-- Two gaps surfaced running the committee-membership-refresher pipeline
-- against live Congress.gov / senate.gov data:
--   1. committee_members lacks created_at/updated_at columns that
--      DoobieCommitteeMemberRepository writes on every insert/upsert. The
--      table (migration 002) and the 046 evolution never added them.
--   2. committee_type_enum (migration 013) omits 'Task Force', a real
--      committeeTypeCode returned by Congress.gov for some committees
--      (e.g. HZGO34). The enum rejected it, failing the refresher's upsert.
--
-- All statements use IF NOT EXISTS guards. The local/dev databases were
-- hot-patched with these exact changes during debugging, so this changeset
-- must tolerate their pre-existence when Liquibase replays it there.

-- ===========================================================================
-- 1. committee_type_enum — add 'Task Force'
--    Congress.gov returns committeeTypeCode 'Task Force' for some committees.
--    runInTransaction: false in the changelog matches the existing ALTER TYPE
--    convention (see migration 045); ADD VALUE cannot run inside a tx block on
--    older PostgreSQL and the new value must not be referenced in the same tx.
-- ===========================================================================

ALTER TYPE committee_type_enum ADD VALUE IF NOT EXISTS 'Task Force';

-- ===========================================================================
-- 2. committee_members — add audit timestamp columns
--    DoobieCommitteeMemberRepository's INSERT and ON CONFLICT ... DO UPDATE
--    SET write created_at / updated_at, but the table never had them.
-- ===========================================================================

ALTER TABLE committee_members ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE committee_members ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

COMMENT ON COLUMN committee_members.created_at IS
    'Row creation timestamp. Set by DoobieCommitteeMemberRepository on insert.';
COMMENT ON COLUMN committee_members.updated_at IS
    'Last update timestamp. Refreshed to NOW() on every upsert by DoobieCommitteeMemberRepository.';
