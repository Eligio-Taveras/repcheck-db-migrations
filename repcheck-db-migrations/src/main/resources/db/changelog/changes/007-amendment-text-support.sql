-- =============================================================================
-- RepCheck Database Schema — V7 Amendment Text Support
-- =============================================================================
-- Adds text ingestion infrastructure for amendments, mirroring bill text
-- versioning. Enables amendment text to flow through the same pipeline as
-- bill text: availability checking → downloading → storage → analysis.
--
-- Changes:
--   1. amendments: add text fields (denormalized latest-text reference)
--   2. amendment_text_versions: new table mirroring bill_text_versions
-- =============================================================================

-- ===========================================================================
-- 1. AMENDMENTS — Add text fields
--    Denormalized latest-text reference, mirroring the pattern on bills.
--    These fields are NULL on initial metadata ingestion. Populated when
--    the amendment-text-pipeline downloads text content.
-- ===========================================================================

ALTER TABLE amendments
    ADD COLUMN text_url TEXT,
    ADD COLUMN text_format TEXT,
    ADD COLUMN text_version_type TEXT,
    ADD COLUMN text_date TIMESTAMPTZ,
    ADD COLUMN text_content TEXT,
    ADD COLUMN latest_text_version_id UUID;

COMMENT ON COLUMN amendments.text_url IS
    'URL of the latest downloaded text version. NULL until text is ingested.';
COMMENT ON COLUMN amendments.text_format IS
    'Format of the latest text: "Formatted Text", "Formatted XML", or "PDF".';
COMMENT ON COLUMN amendments.text_version_type IS
    'Version type of the latest text, e.g., "Submitted", "Engrossed".';
COMMENT ON COLUMN amendments.text_date IS
    'Date of the latest text version.';
COMMENT ON COLUMN amendments.text_content IS
    'Full extracted plain text of the latest version. NULL until text is downloaded and extracted.';
COMMENT ON COLUMN amendments.latest_text_version_id IS
    'FK to amendment_text_versions.version_id — points to the latest text version row.';

-- ===========================================================================
-- 2. AMENDMENT_TEXT_VERSIONS — Append-only text version storage
--    Mirrors bill_text_versions. Each downloaded text version gets an
--    immutable row. The amendments row's text fields point to the latest.
--    Used by Component 10 §10.11 for amendment decomposition and analysis.
-- ===========================================================================

CREATE TABLE amendment_text_versions (
    version_id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    amendment_id         TEXT        NOT NULL REFERENCES amendments(amendment_id),
    version_type         TEXT        NOT NULL,           -- e.g., "Submitted", "Engrossed"
    version_date         TIMESTAMPTZ NOT NULL,
    format_type          TEXT        NOT NULL,           -- "Formatted Text", "Formatted XML", "PDF"
    url                  TEXT        NOT NULL,           -- source URL from Congress.gov
    content              TEXT,                           -- full extracted plain text
    embedding            vector(1536),                   -- populated by analysis pipeline
    fetched_at           TIMESTAMPTZ,                    -- when content was downloaded
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_amendment_text_versions_amendment ON amendment_text_versions (amendment_id);
CREATE INDEX idx_amendment_text_versions_date ON amendment_text_versions (amendment_id, version_date DESC);

-- HNSW index for amendment text similarity search
CREATE INDEX idx_amendment_text_versions_embedding ON amendment_text_versions
    USING hnsw (embedding vector_cosine_ops);

COMMENT ON TABLE amendment_text_versions IS
    'Append-only storage for amendment text versions. Each download creates a new immutable row. Mirrors bill_text_versions.';

-- FK from amendments.latest_text_version_id → amendment_text_versions.version_id
-- Added after the table exists to avoid circular dependency.
ALTER TABLE amendments
    ADD CONSTRAINT fk_amendments_latest_text_version
    FOREIGN KEY (latest_text_version_id) REFERENCES amendment_text_versions(version_id);
