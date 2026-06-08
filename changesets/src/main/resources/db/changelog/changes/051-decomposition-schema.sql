-- Migration 051: Decomposition schema for the meaning-bearing pipeline (D2)
--
-- Reshapes the (empty) decomposition tables to the target for the sections -> concept-groups
-- -> taxonomy pipeline (master plan section 8):
--   * bill_text_sections: + sub_index (O6 sub-split unit) + updated_at; uniqueness per
--     (version_id, section_index, sub_index) — each row is one clustering unit. embedding is
--     already vector(1024) (the raw-section embedding we cluster on).
--   * bill_concept_groups: drop the retired votr columns (group_id/title/simplified_text —
--     "simplified" is cut) and add label + concept_summary + taxonomy_version + updated_at.
--   * concept_taxonomy (NEW): OUR LLM-built taxonomy — name / parent_id (hierarchy) / description /
--     embedding / version / status (proposed|active). Seeds the reserved 'unclassified' node,
--     which must exist before the first classify.
--   * bill_concept_group_taxonomy (NEW): scored multi-label junction group -> taxonomy node.
--
-- All four tables are EMPTY today, so the bill_concept_groups reshape loses no data and the new
-- NOT NULL columns add cleanly. Additive to the naive chunk/embedding path (raw_bill_text et al.
-- are untouched).
--
-- IF [NOT] EXISTS-guarded + index-based uniqueness per repo convention so Liquibase can replay
-- against hot-patched dev/local databases.

-- bill_text_sections: clustering-unit columns ------------------------------------------------
ALTER TABLE bill_text_sections ADD COLUMN IF NOT EXISTS sub_index INT NOT NULL DEFAULT 0;
ALTER TABLE bill_text_sections ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
CREATE UNIQUE INDEX IF NOT EXISTS uq_bill_text_sections_unit
    ON bill_text_sections (version_id, section_index, sub_index);

-- bill_concept_groups: reshape to label / concept_summary / taxonomy_version ------------------
ALTER TABLE bill_concept_groups ADD COLUMN IF NOT EXISTS label TEXT NOT NULL;
ALTER TABLE bill_concept_groups ADD COLUMN IF NOT EXISTS concept_summary TEXT NOT NULL;
ALTER TABLE bill_concept_groups ADD COLUMN IF NOT EXISTS taxonomy_version INT;
ALTER TABLE bill_concept_groups ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE bill_concept_groups DROP COLUMN IF EXISTS group_id;
ALTER TABLE bill_concept_groups DROP COLUMN IF EXISTS title;
ALTER TABLE bill_concept_groups DROP COLUMN IF EXISTS simplified_text;

-- concept_taxonomy: OUR LLM-built taxonomy ---------------------------------------------------
CREATE TABLE IF NOT EXISTS concept_taxonomy (
    id          BIGSERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    parent_id   BIGINT REFERENCES concept_taxonomy(id),
    description TEXT NOT NULL,
    embedding   vector(1024),
    version     INT NOT NULL,
    status      TEXT NOT NULL CHECK (status IN ('proposed', 'active'))
);

CREATE INDEX IF NOT EXISTS idx_concept_taxonomy_embedding
    ON concept_taxonomy USING hnsw (embedding vector_cosine_ops);

-- The reserved node every concept group falls back to when it matches no taxonomy node.
INSERT INTO concept_taxonomy (name, description, version, status)
SELECT 'unclassified', 'Reserved node for concept groups that match no taxonomy node.', 0, 'active'
WHERE NOT EXISTS (SELECT 1 FROM concept_taxonomy WHERE name = 'unclassified');

-- bill_concept_group_taxonomy: scored multi-label junction -----------------------------------
CREATE TABLE IF NOT EXISTS bill_concept_group_taxonomy (
    group_id         BIGINT NOT NULL REFERENCES bill_concept_groups(id) ON DELETE CASCADE,
    taxonomy_node_id BIGINT NOT NULL REFERENCES concept_taxonomy(id),
    score            REAL NOT NULL CHECK (score >= 0 AND score <= 1),
    PRIMARY KEY (group_id, taxonomy_node_id)
);

CREATE INDEX IF NOT EXISTS idx_bcg_taxonomy_node
    ON bill_concept_group_taxonomy (taxonomy_node_id);
