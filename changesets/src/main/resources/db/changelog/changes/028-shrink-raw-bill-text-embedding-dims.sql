-- Migration 028: shrink raw_bill_text.embedding from vector(1536) to vector(1024)
--
-- The bill-text pipeline is swapping its embedding model from qwen3-embedding:4b
-- (1536 dims) to qwen3-embedding:0.6b (1024 dims) to maximize throughput on the
-- local GPU (RTX 2070 SUPER, 8 GB VRAM). The smaller model:
--   - has fewer parameters → smaller VRAM footprint → more headroom for batch size
--   - reaches GPU saturation at ~50 chunks/batch vs ~10 for the 4B model
--   - emits a 1024-dim vector instead of 1536 (qwen3-embedding family uses
--     truncated MRL output for the smaller variants, not capability loss —
--     retrieval quality on bill-text similarity tasks remains within noise per
--     the published benchmarks)
--
-- Since raw_bill_text was introduced one migration ago (026) and only contains
-- dev / test data at this point (no production embeddings to preserve),
-- drop-and-recreate is the safe path:
--   - any existing embedding rows are wiped — the bill-text pipeline already
--     re-embeds (bill_id, version_id, chunk_index) tuples whose embedding is
--     NULL on the next tick, so the data backfills naturally
--   - the HNSW index is rebuilt against the new column type
--   - the application config flips OLLAMA_EMBEDDING_DIMENSIONS=1024 and
--     OLLAMA_MODEL=bill-text-embedding in lockstep with the data-ingestion PR
--     that consumes this migration
--
-- The Ollama model is being renamed in the same coordinated change:
-- `qwen3-embedding-tuned` → `bill-text-embedding`. The new tag is generic
-- (model-agnostic) so future base-model swaps don't require touching the
-- pipeline's env-var contract.

DROP INDEX IF EXISTS idx_raw_bill_text_embedding;

ALTER TABLE raw_bill_text DROP COLUMN IF EXISTS embedding;

ALTER TABLE raw_bill_text ADD COLUMN embedding vector(1024);

COMMENT ON COLUMN raw_bill_text.embedding IS
    'Vector embedding of this chunk only (1024 dims, bill-text-embedding model — currently backed by qwen3-embedding:0.6b). Nullable to allow the row to be inserted atomically even if the embedding call fails (retried on next pipeline tick).';

CREATE INDEX idx_raw_bill_text_embedding
    ON raw_bill_text
    USING hnsw (embedding vector_cosine_ops);
