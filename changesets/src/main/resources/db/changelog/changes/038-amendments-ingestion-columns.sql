-- Migration 038: Amendment ingestion columns — non-destructive ALTERs to amendments
--
-- Aligns the live `amendments` schema with the AmendmentDO contract from
-- repcheck-shared-models PR #44 (the canonical target for the amendments-pipeline,
-- Component 7 §7.3). Adds the columns the new pipeline writes; leaves the
-- legacy denormalized text-fields (text_url, text_format, text_version_type,
-- text_date, text_content, latest_text_version_id) untouched — those will be
-- deprecated in a follow-up after the new pipeline is live and consumers
-- have migrated.
--
-- Field-by-field rationale (mapping AmendmentDO → amendments table):
--   * amendmentId            (Long, PK)              → existing `id BIGSERIAL`
--   * naturalKey             (String)                → existing `natural_key`
--   * congress               (Int)                   → existing `congress`
--   * amendmentType          (Option[AmendmentType]) → existing `amendment_type` (still NOT NULL — DO is Option but live table is stricter; leaving the constraint alone is safe because both ingestion paths produce a value)
--   * number                 (String)                → existing `number INT` widened to TEXT (live table has 0 rows; DO contract is String for both bills and amendments)
--   * billId                 (Option[Long])          → existing `bill_id` — populated with the RESOLVED ANCESTOR bill at ingest time (computed by walking parent_amendment_id chain). One column, one meaning.
--   * chamber                (Chamber, NOT NULL)     → existing `chamber chamber_type` tightened to NOT NULL (live table currently nullable; AmendmentDO PR #44 made it required)
--   * description, purpose, sponsorMemberId, submittedDate, latestActionDate, latestActionText, updateDate, apiUrl → existing columns
--   * latestActionTime       (Option[String])        → NEW `latest_action_time TEXT`
--   * parentAmendmentId      (Option[Long])          → NEW `parent_amendment_id BIGINT REFERENCES amendments(id)` (sub-amendment chain — tracks the IMMEDIATE parent only; the ancestor bill is recorded directly on bill_id)
--   * lastTextCheckAt        (Option[Instant])       → NEW `last_text_check_at TIMESTAMPTZ` (set on successful text check per §7.5)
--   * createdAt, updatedAt   → existing columns
--
-- Note: there is NO `proposed_date` column. The Congress.gov AmendmentNumber
-- schema has only `submittedDate` + `updateDate` (verified against
-- docs/reference/congress-gov-api.yaml). The shared-models PR #44 was revised
-- in parallel to drop `proposedDate` from AmendmentDO.
--
-- Note: there is NO `effective_bill_id` column. The earlier draft introduced
-- both `bill_id` (immediate parent's bill) and `effective_bill_id` (resolved
-- ancestor); these were functionally redundant. The simplified design uses
-- `bill_id` for the resolved ancestor and `parent_amendment_id` for the
-- immediate amendment parent. One column per concept.
--
-- Liquibase tracks changesets by ID and guarantees single execution, so each
-- statement runs exactly once. ADD COLUMN uses IF NOT EXISTS as a defensive
-- guard against partial-application drift (other migrations in the repo follow
-- the same pattern — see migration 012 §2 and migration 015).

-- ===========================================================================
-- 1. Add new columns
-- ===========================================================================

ALTER TABLE amendments ADD COLUMN IF NOT EXISTS latest_action_time    TEXT;
ALTER TABLE amendments ADD COLUMN IF NOT EXISTS parent_amendment_id   BIGINT;
ALTER TABLE amendments ADD COLUMN IF NOT EXISTS last_text_check_at    TIMESTAMPTZ;

COMMENT ON COLUMN amendments.latest_action_time IS
    'Time-of-day component of the latest action (e.g., "14:30:00"), kept as a raw string. Pairs with latest_action_date. Per LatestActionDTO.actionTime added in shared-models PR #44.';
COMMENT ON COLUMN amendments.parent_amendment_id IS
    'FK to amendments(id) when this row is an amendment-to-an-amendment (Senate floor sub-amendments). NULL for top-level amendments. Tracks the IMMEDIATE parent only — the resolved ancestor bill is recorded directly on bill_id.';
COMMENT ON COLUMN amendments.last_text_check_at IS
    'Timestamp of the most recent successful amendment-text-availability check. NULL until the text pipeline has confirmed at least one text version exists. Drives text-poll scheduling per §7.5.';

-- ===========================================================================
-- 2. Add foreign key for the new linkage column
-- ===========================================================================

-- Self-referential FK for parent_amendment_id (sub-amendment chain).
ALTER TABLE amendments
    ADD CONSTRAINT amendments_parent_amendment_id_fkey
    FOREIGN KEY (parent_amendment_id) REFERENCES amendments(id);

CREATE INDEX IF NOT EXISTS idx_amendments_parent_amendment_id
    ON amendments (parent_amendment_id) WHERE parent_amendment_id IS NOT NULL;

-- ===========================================================================
-- 3. Widen amendments.number INT -> TEXT to match AmendmentDO.number: String
-- ===========================================================================
--
-- The DO has been String since the original definition (mirroring BillDO).
-- The live column is INTEGER, which means INSERTs from Doobie auto-derived
-- Write[AmendmentDO] would have failed at runtime; the live amendments table
-- in dev has 0 rows confirming the column has never been written successfully.
-- INT -> TEXT is a widening cast that cannot lose data, even if rows existed.
ALTER TABLE amendments
    ALTER COLUMN number TYPE TEXT USING number::TEXT;

-- ===========================================================================
-- 4. Tighten amendments.chamber to NOT NULL
-- ===========================================================================
--
-- AmendmentDO PR #44 changed `chamber: Option[Chamber]` to `chamber: Chamber`.
-- Both ingestion paths (Congress.gov detail responses; Senate XML) deterministically
-- produce a chamber via AmendmentConversions.resolveChamber — explicitly from
-- the DTO when present, else derived from amendment_type
-- (HAMDT -> House, SAMDT/SUAMDT -> Senate). The placeholder uses Chamber.House
-- as a benign sentinel.
--
-- Defensive backfill (no-op against the empty live table; protects against
-- future re-application or stray NULL rows in any environment): derive chamber
-- from amendment_type for any row missing it. Then tighten the column.
UPDATE amendments
   SET chamber = CASE amendment_type
                     WHEN 'hamdt'  THEN 'House'::chamber_type
                     WHEN 'samdt'  THEN 'Senate'::chamber_type
                     WHEN 'suamdt' THEN 'Senate'::chamber_type
                 END
 WHERE chamber IS NULL;

ALTER TABLE amendments ALTER COLUMN chamber SET NOT NULL;
