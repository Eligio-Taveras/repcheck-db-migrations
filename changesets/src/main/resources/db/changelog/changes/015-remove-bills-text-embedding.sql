-- =============================================================================
-- RepCheck Database Schema — V15 Remove Redundant text_embedding from bills
-- =============================================================================
-- The text_embedding column on bills duplicates the embedding stored in
-- bill_text_versions.embedding (linked via latest_text_version_id FK).
-- This duplication caused sync bugs and wastes ~6KB per row.
--
-- This migration:
-- 1. Drops the HNSW index and column from bills
-- 2. Creates an HNSW index on bill_text_versions.embedding instead
-- =============================================================================

-- Drop the redundant HNSW index on bills.text_embedding
DROP INDEX IF EXISTS idx_bills_text_embedding;

-- Drop the redundant column
ALTER TABLE bills DROP COLUMN IF EXISTS text_embedding;

-- Create HNSW index on the canonical embedding location
CREATE INDEX idx_btv_embedding ON bill_text_versions
    USING hnsw (embedding vector_cosine_ops);
