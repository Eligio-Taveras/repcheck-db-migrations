-- Migration 040: amendment_text_chunks — chunked amendment text + per-chunk embeddings
--
-- Mirror of raw_bill_text (migration 026) for the amendments-pipeline. Same
-- shape, same constraints, same HNSW vector index pattern. Created from
-- scratch — no existing table to migrate, so this is purely additive.
--
-- The amendment-text-pipeline downloads a plaintext rendering of an amendment
-- text version, splits it into embedding-model-sized chunks (qwen3-embedding,
-- 1024 dims via truncated MRL output — same model and dim count as raw_bill_text
-- after migration 028's shrink), and inserts one row per chunk. Each row is
-- independently vector-indexable via HNSW so downstream search does
-- `MIN(embedding <=> $query)` GROUP BY amendment_id (or version_id) without
-- having to unnest an array of vectors in-memory.
--
-- pgvector + HNSW: the `vector` extension is already enabled in all
-- environments (loaded by migration 001 as a prerequisite for bill_subjects
-- and the rest of the embedding columns); HNSW indexes are already in use
-- across raw_bill_text, bill_analyses, amendment_concept_summaries, etc. No
-- CREATE EXTENSION step required here.
--
-- version_id is nullable on the same rationale as raw_bill_text.version_id:
-- chunks can exist attached to an amendment even before the parent
-- amendment_text_versions row has been linked (e.g., when a download succeeds
-- but the version-row insert is retried).

CREATE TABLE IF NOT EXISTS amendment_text_chunks (
    id           BIGSERIAL PRIMARY KEY,
    amendment_id BIGINT      NOT NULL REFERENCES amendments(id) ON DELETE CASCADE,
    version_id   BIGINT               REFERENCES amendment_text_versions(id) ON DELETE CASCADE,
    chunk_index  INT         NOT NULL,
    content      TEXT        NOT NULL,
    embedding    vector(1024),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_amendment_text_chunks_chunk_index_nonneg CHECK (chunk_index >= 0)
);

COMMENT ON TABLE amendment_text_chunks IS
    'Chunked amendment text with per-chunk embeddings. One amendment version produces N rows, one per chunk of at most the embedding model input size. Mirrors raw_bill_text.';

COMMENT ON COLUMN amendment_text_chunks.chunk_index IS
    'Zero-based sequence index within the parent (amendment_id, version_id). Chunks are ordered to allow reconstruction of the full amendment text by ORDER BY chunk_index.';

COMMENT ON COLUMN amendment_text_chunks.content IS
    'Raw text for this chunk, sized to fit the embedding model input limit. Naive byte-split with pipeline-configured overlap.';

COMMENT ON COLUMN amendment_text_chunks.embedding IS
    'Vector embedding of this chunk only (1024 dims, qwen3-embedding:0.6b via truncated MRL — matches raw_bill_text and the unified-embeddings target from migration 029). Nullable to allow the row to be inserted atomically even if the embedding call fails (retried on next pipeline tick).';

-- Uniqueness on (version_id, chunk_index) where version_id is set — lets a
-- version be re-processed idempotently (DELETE by version_id then INSERT the
-- new chunks) without spurious constraint violations for chunks that lack a
-- version linkage yet. Mirrors uq_raw_bill_text_version_chunk.
CREATE UNIQUE INDEX IF NOT EXISTS uq_amendment_text_chunks_version_chunk
    ON amendment_text_chunks (version_id, chunk_index)
    WHERE version_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_amendment_text_chunks_amendment
    ON amendment_text_chunks (amendment_id);
CREATE INDEX IF NOT EXISTS idx_amendment_text_chunks_version
    ON amendment_text_chunks (version_id);

-- HNSW vector index with cosine distance — same pattern as
-- idx_raw_bill_text_embedding (migration 026) and the rest of the
-- vector-indexed columns post migration 029.
CREATE INDEX IF NOT EXISTS idx_amendment_text_chunks_embedding
    ON amendment_text_chunks
    USING hnsw (embedding vector_cosine_ops);
