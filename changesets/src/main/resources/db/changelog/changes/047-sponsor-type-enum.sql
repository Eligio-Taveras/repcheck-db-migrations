-- Migration 047: Add sponsor_type discriminator to amendments
--
-- The amendments table already has two mutually exclusive sponsor FK
-- columns (sponsor_member_id → members, sponsor_committee_id → committees,
-- both nullable). This migration adds a sponsor_type_enum discriminator so
-- consumers can filter/query by sponsor kind without checking NULLs on
-- both FK columns.
--
-- Changes:
--   1. CREATE TYPE sponsor_type_enum ('member', 'committee')
--   2. ALTER TABLE amendments ADD COLUMN sponsor_type sponsor_type_enum
--   3. Backfill from existing FK columns (member takes precedence if both set)

-- ===========================================================================
-- 1. Create the enum type
-- ===========================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sponsor_type_enum') THEN
        CREATE TYPE sponsor_type_enum AS ENUM ('member', 'committee');
    END IF;
END
$$;

-- ===========================================================================
-- 2. Add sponsor_type column
-- ===========================================================================

ALTER TABLE amendments ADD COLUMN IF NOT EXISTS sponsor_type sponsor_type_enum;

COMMENT ON COLUMN amendments.sponsor_type IS
    'Discriminator for the sponsor FK columns. ''member'' when sponsor_member_id is set, ''committee'' when sponsor_committee_id is set, NULL when no sponsor. Enables clean filtering without NULL-checking two columns.';

-- ===========================================================================
-- 3. Backfill existing rows
-- ===========================================================================

UPDATE amendments SET sponsor_type = 'member'::sponsor_type_enum
WHERE sponsor_member_id IS NOT NULL AND sponsor_type IS NULL;

UPDATE amendments SET sponsor_type = 'committee'::sponsor_type_enum
WHERE sponsor_committee_id IS NOT NULL AND sponsor_member_id IS NULL AND sponsor_type IS NULL;
