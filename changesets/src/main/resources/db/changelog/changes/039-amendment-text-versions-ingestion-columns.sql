-- Migration 039: Amendment text version ingestion columns — non-destructive ALTERs
--
-- Adds the columns the amendments-pipeline (Component 7) writes when ingesting
-- amendment text versions, derived from AmendmentTextItemDTO + AmendmentFormatDTO
-- in repcheck-shared-models PR #44.
--
-- Cohabitation strategy with existing columns (LEFT IN PLACE — see PR body):
--   The pre-existing columns version_type (TEXT), version_date (TIMESTAMPTZ),
--   url (TEXT), content (TEXT), format_type (format_type_enum), embedding,
--   fetched_at, created_at, amendment_id, id are NOT modified or dropped.
--   The amendment_text_versions table currently has 0 rows in dev and is not
--   populated in any environment, so cohabitation is purely a forward-compat
--   measure — the new pipeline writes only the new columns; the legacy columns
--   become dead weight to be dropped in a follow-up after consumer code is
--   verified to no longer reference them.
--
-- New columns (all nullable — text rows are inserted incrementally as the
-- text-availability checker → downloader → embedder pipeline progresses):
--   * source_url           — Congress.gov URL as returned by the API
--   * download_url         — rewritten api.govinfo.gov URL the downloader fetches
--   * version_type_code    — text_version_code_type discriminator (Submitted | Modified)
--   * published_date       — DATE parsed from AmendmentTextItemDTO.date
--   * text_length          — character length of the downloaded plaintext
--
-- The existing columns format_type and fetched_at already match the new
-- pipeline's needs (format_type_enum gained 'HTML' in migration 037; fetched_at
-- is already nullable TIMESTAMPTZ). They are reused as-is.

ALTER TABLE amendment_text_versions ADD COLUMN IF NOT EXISTS source_url        TEXT;
ALTER TABLE amendment_text_versions ADD COLUMN IF NOT EXISTS download_url      TEXT;
ALTER TABLE amendment_text_versions ADD COLUMN IF NOT EXISTS version_type_code text_version_code_type;
ALTER TABLE amendment_text_versions ADD COLUMN IF NOT EXISTS published_date    DATE;
ALTER TABLE amendment_text_versions ADD COLUMN IF NOT EXISTS text_length       INT;

COMMENT ON COLUMN amendment_text_versions.source_url IS
    'Congress.gov URL as returned by AmendmentFormatDTO.url. Rewritten downstream to api.govinfo.gov for the actual download — see download_url.';
COMMENT ON COLUMN amendment_text_versions.download_url IS
    'api.govinfo.gov URL the amendment-text-pipeline actually fetches. Derived from source_url by AmendmentTextDownloader''s URL-rewriter. May equal source_url when no rewrite is required.';
COMMENT ON COLUMN amendment_text_versions.version_type_code IS
    'Discriminator from AmendmentTextItemDTO.type — typically "Submitted" or "Modified". Added to text_version_code_type enum in migration 037.';
COMMENT ON COLUMN amendment_text_versions.published_date IS
    'DATE parsed from AmendmentTextItemDTO.date (an ISO datetime string, kept raw at the DTO layer per the L6 design rule). NULL when the API omits the date.';
COMMENT ON COLUMN amendment_text_versions.text_length IS
    'Character length of the downloaded plaintext. Used by the chunker to size raw_amendment_text inserts and surfaced in observability metrics. NULL until the downloader stores text.';

CREATE INDEX IF NOT EXISTS idx_amendment_text_versions_version_type_code
    ON amendment_text_versions (version_type_code) WHERE version_type_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_amendment_text_versions_published_date
    ON amendment_text_versions (amendment_id, published_date DESC) WHERE published_date IS NOT NULL;
