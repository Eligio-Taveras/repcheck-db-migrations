-- Migration 039: Amendment text version ingestion columns — non-destructive ALTERs
--
-- Aligns amendment_text_versions with the amendments-pipeline (Component 7)
-- writers derived from AmendmentTextItemDTO + AmendmentFormatDTO in
-- repcheck-shared-models PR #44.
--
-- Design rule applied here: REUSE existing columns rather than introduce
-- parallel near-synonyms. The earlier draft of this migration added
-- `source_url`, `version_type_code`, and `published_date` alongside the
-- existing `url`, `version_type`, and `version_date` columns from migration
-- 007. That created two columns per concept (source URL, version code,
-- published date), forcing every reader to know which to consult. Reuse is
-- safer: amendment_text_versions has 0 rows in every environment, so we can
-- repurpose the existing columns without data migration.
--
-- Mapping AmendmentTextItemDTO + AmendmentFormatDTO → existing columns:
--   * AmendmentFormatDTO.url       → existing `url TEXT NOT NULL` (migration 007 comment: "source URL from Congress.gov")
--   * AmendmentTextItemDTO.type    → existing `version_type TEXT NOT NULL`, converted in this migration to the dedicated `amendment_text_version_code_type` enum (per plan §L3)
--   * AmendmentTextItemDTO.date    → existing `version_date TIMESTAMPTZ NOT NULL`
--   * AmendmentFormatDTO.formatType → existing `format_type format_type_enum`
--   * fetched_at                   → existing `fetched_at TIMESTAMPTZ` (already nullable)
--
-- New columns (genuinely new — no existing column carries this concept):
--   * download_url — rewritten api.govinfo.gov URL the downloader fetches.
--                    Distinct from `url` because the Congress.gov-emitted URL
--                    is the source-of-record while the api.govinfo.gov URL is
--                    a derived value the downloader resolves at fetch time.
--   * text_length  — character length of the downloaded plaintext.

-- ===========================================================================
-- 1. Add genuinely new columns
-- ===========================================================================

ALTER TABLE amendment_text_versions ADD COLUMN IF NOT EXISTS download_url TEXT;
ALTER TABLE amendment_text_versions ADD COLUMN IF NOT EXISTS text_length  INT;

COMMENT ON COLUMN amendment_text_versions.download_url IS
    'api.govinfo.gov URL the amendment-text-pipeline actually fetches. Derived from `url` (the Congress.gov source URL) by AmendmentTextDownloader''s URL-rewriter. May equal `url` when no rewrite is required.';
COMMENT ON COLUMN amendment_text_versions.text_length IS
    'Character length of the downloaded plaintext. Used by the chunker to size raw_amendment_text inserts and surfaced in observability metrics. NULL until the downloader stores text.';

-- ===========================================================================
-- 2. Convert existing version_type TEXT → amendment_text_version_code_type enum
-- ===========================================================================
--
-- Per plan §L3 amendment text version codes have a dedicated enum
-- (amendment_text_version_code_type — created in migration 037, values
-- 'Submitted' and 'Modified'). The amendment_text_versions table currently
-- has 0 rows in dev and is not populated in any environment, so the cast is
-- trivial — the USING clause just tells PostgreSQL how to coerce any rows
-- that might exist (none do).
ALTER TABLE amendment_text_versions
    ALTER COLUMN version_type TYPE amendment_text_version_code_type
    USING version_type::amendment_text_version_code_type;

COMMENT ON COLUMN amendment_text_versions.version_type IS
    'Discriminator from AmendmentTextItemDTO.type — "Submitted" or "Modified". Typed as the dedicated amendment_text_version_code_type enum (per plan §L3) to keep the value space cleanly separated from the bill-side text_version_code_type.';

-- ===========================================================================
-- 3. Partial indexes on fetched_at to drive the text-availability scheduler
-- ===========================================================================
--
-- The text-availability checker scans rows split by fetched_at IS NULL (rows
-- still needing a download) vs fetched_at IS NOT NULL (rows already fetched,
-- candidates for re-check on update). Partial indexes keep both halves
-- cheap to scan; full-table indexes would bloat with the dominant half.

CREATE INDEX IF NOT EXISTS idx_amendment_text_versions_fetched_null
    ON amendment_text_versions (amendment_id) WHERE fetched_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_amendment_text_versions_fetched_not_null
    ON amendment_text_versions (amendment_id, fetched_at DESC) WHERE fetched_at IS NOT NULL;
