-- =============================================================================
-- RepCheck Database Schema — V3 Text Sections & Concept Groups
-- =============================================================================
-- Adds section-level bill text storage and decouples concept groups from
-- analysis runs so decomposition artifacts belong to the text version.
--
-- New tables:
--   - bill_text_sections: individual sections parsed from bill XML (§1.4)
--   - bill_concept_groups: concept groups from clustering, tied to text version
--   - bill_concept_group_sections: junction linking groups to sections
--
-- Refactors:
--   - bill_concept_summaries: drops decomposition fields (group_id, title,
--     section_references, simplified_text), adds concept_group_id FK
--     to reference the new bill_concept_groups table
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. bill_text_sections — Individual sections parsed from bill XML (§1.4)
--    Each row = one structural section from the bill text.
--    Sections are immutable once parsed from a text version.
--    Embedding enables per-section semantic search.
-- ---------------------------------------------------------------------------

CREATE TABLE bill_text_sections (
    section_id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    version_id           UUID        NOT NULL REFERENCES bill_text_versions(version_id) ON DELETE CASCADE,
    bill_id              BIGINT      NOT NULL REFERENCES bills(id),
    section_index        INT         NOT NULL,     -- ordinal position in the bill (0-based)
    section_identifier   TEXT,                     -- e.g., "Sec. 101", "Title I", "§2(a)"
    heading              TEXT,                     -- section heading/title (NULL if untitled)
    content              TEXT        NOT NULL,     -- section text content
    embedding            vector(1536),             -- for per-section semantic search
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_section_per_version UNIQUE (version_id, section_index)
);

CREATE INDEX idx_text_sections_version ON bill_text_sections (version_id);
CREATE INDEX idx_text_sections_bill ON bill_text_sections (bill_id);

-- HNSW index for per-section semantic search
CREATE INDEX idx_text_sections_embedding ON bill_text_sections
    USING hnsw (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- 2. bill_concept_groups — Concept groups from decomposition (clustering)
--    Tied to a text version, NOT an analysis run.
--    Multiple analysis runs can reference the same concept groups.
--    The simplified_text is the Haiku-produced coherent summary of the group.
-- ---------------------------------------------------------------------------

CREATE TABLE bill_concept_groups (
    concept_group_id     UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    version_id           UUID        NOT NULL REFERENCES bill_text_versions(version_id) ON DELETE CASCADE,
    bill_id              BIGINT      NOT NULL REFERENCES bills(id),
    group_id             TEXT        NOT NULL,     -- stable identifier, e.g., "transportation-funding"
    title                TEXT        NOT NULL,     -- human-readable concept name
    simplified_text      TEXT        NOT NULL,     -- Haiku-produced coherent summary of grouped sections
    embedding            vector(1536),             -- embedding of simplified_text for semantic search
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_concept_group_per_version UNIQUE (version_id, group_id)
);

CREATE INDEX idx_concept_groups_version ON bill_concept_groups (version_id);
CREATE INDEX idx_concept_groups_bill ON bill_concept_groups (bill_id);

-- HNSW index for concept group semantic search
CREATE INDEX idx_concept_groups_embedding ON bill_concept_groups
    USING hnsw (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- 3. bill_concept_group_sections — Junction: which sections belong to which
--    concept group. A section can belong to exactly one group.
-- ---------------------------------------------------------------------------

CREATE TABLE bill_concept_group_sections (
    concept_group_id     UUID        NOT NULL REFERENCES bill_concept_groups(concept_group_id) ON DELETE CASCADE,
    section_id           UUID        NOT NULL REFERENCES bill_text_sections(section_id) ON DELETE CASCADE,

    PRIMARY KEY (concept_group_id, section_id)
);

CREATE INDEX idx_cg_sections_section ON bill_concept_group_sections (section_id);

-- ---------------------------------------------------------------------------
-- 4. Refactor bill_concept_summaries — Decouple from decomposition
--    Remove fields that now live in bill_concept_groups.
--    Add concept_group_id FK to link analysis results to concept groups.
-- ---------------------------------------------------------------------------

-- Add FK to concept groups
ALTER TABLE bill_concept_summaries ADD COLUMN concept_group_id UUID REFERENCES bill_concept_groups(concept_group_id);

-- Drop decomposition fields that moved to bill_concept_groups
-- Note: dropping group_id automatically drops uq_concept_per_analysis (which includes group_id)
ALTER TABLE bill_concept_summaries DROP COLUMN group_id;
ALTER TABLE bill_concept_summaries DROP COLUMN title;
ALTER TABLE bill_concept_summaries DROP COLUMN section_references;
ALTER TABLE bill_concept_summaries DROP COLUMN simplified_text;

-- Add new unique constraint based on concept_group_id (old one was auto-dropped with group_id)
ALTER TABLE bill_concept_summaries ADD CONSTRAINT uq_concept_summary_per_analysis UNIQUE (analysis_id, concept_group_id);

-- Index for concept group lookups
CREATE INDEX idx_concept_summaries_group ON bill_concept_summaries (concept_group_id);
