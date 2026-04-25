-- Migration 026: raw_bill_text — chunked raw text + per-chunk embeddings
--
-- The embedding model (Ollama qwen3-embedding, 1536 dims) has a finite context
-- window. Bill text is regularly larger than that window (e.g., the Statutes
-- at Large 1968 reprint 90-HR-5037 is 14 MB). Pre-this-migration, the
-- bill-text pipeline held a single `content` + `embedding` pair per
-- `bill_text_versions` row, which forced a hard size cap and silently failed
-- on oversized bills.
--
-- raw_bill_text stores the text split into chunks of at most the embedding
-- model's max input size, with one embedding per chunk. Each row is
-- independently vector-indexable via HNSW — downstream vector search does
-- `MIN(embedding <=> $query)` GROUP BY bill_id or version_id to find the
-- bill whose any-chunk is closest to a query, without having to unnest an
-- array of vectors in-memory.
--
-- This table is distinct from `bill_text_sections` (migration 003), which is
-- reserved for the upcoming structured-section pipeline (parsing bills into
-- `SEC. 1`, `SEC. 2`, etc. with heading metadata). raw_bill_text holds the
-- mechanical byte-split chunks that are the fallback indexing substrate until
-- structured sections exist for a given version.
--
-- ==Schema change on bill_text_versions==
--
-- content (TEXT) and embedding (vector(1536)) are removed from
-- bill_text_versions. The version row becomes pure metadata: which version
-- code exists, where its canonical URL lives, when it was fetched. The actual
-- text + embeddings live in raw_bill_text, joined by version_id (nullable so
-- chunks can exist attached to a bill even before a parent version row is
-- created — e.g. if the availability checker hasn't linked a URL yet).

-- ----------------------------------------------------------------------------
-- bill_text_versions: drop content + embedding (and the embedding's HNSW index)
-- ----------------------------------------------------------------------------

DROP INDEX IF EXISTS idx_btv_embedding;

ALTER TABLE bill_text_versions
    DROP COLUMN IF EXISTS content,
    DROP COLUMN IF EXISTS embedding;

-- ----------------------------------------------------------------------------
-- raw_bill_text: chunked text + per-chunk embeddings
-- ----------------------------------------------------------------------------

CREATE TABLE raw_bill_text (
    id          BIGSERIAL PRIMARY KEY,
    bill_id     BIGINT      NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    version_id  BIGINT               REFERENCES bill_text_versions(id) ON DELETE CASCADE,
    chunk_index INT         NOT NULL,
    content     TEXT        NOT NULL,
    embedding   vector(1536),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_raw_bill_text_chunk_index_nonneg CHECK (chunk_index >= 0)
);

COMMENT ON TABLE raw_bill_text IS
    'Chunked raw bill text with per-chunk embeddings. One bill version produces N rows, one per chunk of at most the embedding model input size. version_id is nullable so chunks can exist attached to a bill even before a parent bill_text_versions row is created.';

COMMENT ON COLUMN raw_bill_text.chunk_index IS
    'Zero-based sequence index within the parent (bill_id, version_id). Chunks are ordered to allow reconstruction of the full document by ORDER BY chunk_index.';

COMMENT ON COLUMN raw_bill_text.content IS
    'Raw text for this chunk, sized to fit the embedding model input limit. Not split on sentence boundaries — naive byte-split with pipeline-configured overlap.';

COMMENT ON COLUMN raw_bill_text.embedding IS
    'Vector embedding of this chunk only (1536 dims, qwen3-embedding). Nullable to allow the row to be inserted atomically even if the embedding call fails (retried on next pipeline tick).';

-- Uniqueness on (version_id, chunk_index) where version_id is set — lets a
-- version be re-processed idempotently (DELETE by version_id then INSERT the
-- new chunks) without spurious constraint violations for chunks that lack a
-- version linkage yet.
CREATE UNIQUE INDEX uq_raw_bill_text_version_chunk
    ON raw_bill_text (version_id, chunk_index)
    WHERE version_id IS NOT NULL;

CREATE INDEX idx_raw_bill_text_bill    ON raw_bill_text (bill_id);
CREATE INDEX idx_raw_bill_text_version ON raw_bill_text (version_id);

-- HNSW vector index with cosine distance — matches the pattern used on
-- bill_text_versions.embedding pre-migration (idx_btv_embedding, dropped
-- above). Rebuilt here on the new storage site.
CREATE INDEX idx_raw_bill_text_embedding
    ON raw_bill_text
    USING hnsw (embedding vector_cosine_ops);
