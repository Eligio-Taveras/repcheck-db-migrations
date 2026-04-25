-- Migration 029: unify ALL embedding columns to vector(1024) for schema consistency
--
-- Following migration 028 (which dropped and recreated raw_bill_text.embedding from
-- vector(1536) to vector(1024) for the qwen3-embedding:0.6b swap), the rest of the schema
-- still carries vector(1536) columns from earlier migrations. The user direction is to
-- standardize ALL embedding columns to vector(1024) so a single embedding service (the
-- bill-text-embedding model, currently backed by qwen3-embedding:0.6b) can populate any
-- column in the schema without dim mismatches.
--
-- Why drop-and-recreate instead of in-place ALTER:
--   - pgvector does not support `ALTER TYPE` on the vector type to change dimension —
--     the column has to be dropped and recreated.
--   - Every one of these 17 columns is currently EMPTY in production (no pipeline writes
--     to them yet, except raw_bill_text which 028 already handled). The downstream
--     pipelines that will populate these (LLM analysis, scoring engine, user-stance
--     materialization, etc.) are still in design / not yet shipping data. So losing the
--     existing rows' NULL embeddings is a no-op semantically.
--   - HNSW indexes need rebuilding regardless because they're tied to the column type.
--
-- The 17 columns being unified (table → column → index name to recreate):
--   1.  bill_subjects.embedding                       → idx_bill_subjects_embedding
--   2.  amendment_findings.embedding                  → idx_amendment_findings_embedding
--   3.  bill_analyses.embedding                       → idx_bill_analyses_embedding
--   4.  bill_findings.embedding                       → idx_bill_findings_embedding
--   5.  user_preferences.embedding                    → idx_user_preferences_embedding
--   6.  bill_concept_summaries.embedding              → idx_concept_summaries_embedding
--   7.  bill_text_sections.embedding                  → idx_text_sections_embedding
--   8.  bill_concept_groups.embedding                 → idx_concept_groups_embedding
--   9.  amendment_analyses.embedding                  → idx_amendment_analyses_embedding
--   10. amendment_concept_summaries.embedding         → idx_amendment_concept_summaries_embedding
--   11. amendment_text_versions.embedding             → idx_amendment_text_versions_embedding
--   12. scores.reasoning_embedding                    → idx_scores_reasoning_embedding
--   13. score_history.reasoning_embedding             → idx_score_history_reasoning_embedding
--   14. member_bill_stance_topics.reasoning_embedding → idx_stance_topics_reasoning_embedding
--   15. user_bill_alignments.reasoning_embedding      → idx_user_bill_align_reasoning_embedding
--   16. user_amendment_alignments.reasoning_embedding → idx_user_amend_align_reasoning_embedding
--   17. bill_subject_history.embedding                → (no index; mirrors bill_subjects but added later w/o one)
--
-- raw_bill_text.embedding is intentionally NOT in this list — migration 028 already
-- handled it.

-- ============================================================================
-- 1. bill_subjects.embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_bill_subjects_embedding;
ALTER TABLE bill_subjects DROP COLUMN IF EXISTS embedding;
ALTER TABLE bill_subjects ADD COLUMN embedding vector(1024);
CREATE INDEX idx_bill_subjects_embedding ON bill_subjects USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- 2. amendment_findings.embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_amendment_findings_embedding;
ALTER TABLE amendment_findings DROP COLUMN IF EXISTS embedding;
ALTER TABLE amendment_findings ADD COLUMN embedding vector(1024);
CREATE INDEX idx_amendment_findings_embedding ON amendment_findings USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- 3. bill_analyses.embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_bill_analyses_embedding;
ALTER TABLE bill_analyses DROP COLUMN IF EXISTS embedding;
ALTER TABLE bill_analyses ADD COLUMN embedding vector(1024);
CREATE INDEX idx_bill_analyses_embedding ON bill_analyses USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- 4. bill_findings.embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_bill_findings_embedding;
ALTER TABLE bill_findings DROP COLUMN IF EXISTS embedding;
ALTER TABLE bill_findings ADD COLUMN embedding vector(1024);
CREATE INDEX idx_bill_findings_embedding ON bill_findings USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- 5. user_preferences.embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_user_preferences_embedding;
ALTER TABLE user_preferences DROP COLUMN IF EXISTS embedding;
ALTER TABLE user_preferences ADD COLUMN embedding vector(1024);
CREATE INDEX idx_user_preferences_embedding ON user_preferences USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- 6. bill_concept_summaries.embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_concept_summaries_embedding;
ALTER TABLE bill_concept_summaries DROP COLUMN IF EXISTS embedding;
ALTER TABLE bill_concept_summaries ADD COLUMN embedding vector(1024);
CREATE INDEX idx_concept_summaries_embedding ON bill_concept_summaries USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- 7. bill_text_sections.embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_text_sections_embedding;
ALTER TABLE bill_text_sections DROP COLUMN IF EXISTS embedding;
ALTER TABLE bill_text_sections ADD COLUMN embedding vector(1024);
CREATE INDEX idx_text_sections_embedding ON bill_text_sections USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- 8. bill_concept_groups.embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_concept_groups_embedding;
ALTER TABLE bill_concept_groups DROP COLUMN IF EXISTS embedding;
ALTER TABLE bill_concept_groups ADD COLUMN embedding vector(1024);
CREATE INDEX idx_concept_groups_embedding ON bill_concept_groups USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- 9. amendment_analyses.embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_amendment_analyses_embedding;
ALTER TABLE amendment_analyses DROP COLUMN IF EXISTS embedding;
ALTER TABLE amendment_analyses ADD COLUMN embedding vector(1024);
CREATE INDEX idx_amendment_analyses_embedding ON amendment_analyses USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- 10. amendment_concept_summaries.embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_amendment_concept_summaries_embedding;
ALTER TABLE amendment_concept_summaries DROP COLUMN IF EXISTS embedding;
ALTER TABLE amendment_concept_summaries ADD COLUMN embedding vector(1024);
CREATE INDEX idx_amendment_concept_summaries_embedding ON amendment_concept_summaries USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- 11. amendment_text_versions.embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_amendment_text_versions_embedding;
ALTER TABLE amendment_text_versions DROP COLUMN IF EXISTS embedding;
ALTER TABLE amendment_text_versions ADD COLUMN embedding vector(1024);
CREATE INDEX idx_amendment_text_versions_embedding ON amendment_text_versions USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- 12. scores.reasoning_embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_scores_reasoning_embedding;
ALTER TABLE scores DROP COLUMN IF EXISTS reasoning_embedding;
ALTER TABLE scores ADD COLUMN reasoning_embedding vector(1024);
CREATE INDEX idx_scores_reasoning_embedding ON scores USING hnsw (reasoning_embedding vector_cosine_ops);

-- ============================================================================
-- 13. score_history.reasoning_embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_score_history_reasoning_embedding;
ALTER TABLE score_history DROP COLUMN IF EXISTS reasoning_embedding;
ALTER TABLE score_history ADD COLUMN reasoning_embedding vector(1024);
CREATE INDEX idx_score_history_reasoning_embedding ON score_history USING hnsw (reasoning_embedding vector_cosine_ops);

-- ============================================================================
-- 14. member_bill_stance_topics.reasoning_embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_stance_topics_reasoning_embedding;
ALTER TABLE member_bill_stance_topics DROP COLUMN IF EXISTS reasoning_embedding;
ALTER TABLE member_bill_stance_topics ADD COLUMN reasoning_embedding vector(1024);
CREATE INDEX idx_stance_topics_reasoning_embedding ON member_bill_stance_topics USING hnsw (reasoning_embedding vector_cosine_ops);

-- ============================================================================
-- 15. user_bill_alignments.reasoning_embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_user_bill_align_reasoning_embedding;
ALTER TABLE user_bill_alignments DROP COLUMN IF EXISTS reasoning_embedding;
ALTER TABLE user_bill_alignments ADD COLUMN reasoning_embedding vector(1024);
CREATE INDEX idx_user_bill_align_reasoning_embedding ON user_bill_alignments USING hnsw (reasoning_embedding vector_cosine_ops);

-- ============================================================================
-- 16. user_amendment_alignments.reasoning_embedding
-- ============================================================================
DROP INDEX IF EXISTS idx_user_amend_align_reasoning_embedding;
ALTER TABLE user_amendment_alignments DROP COLUMN IF EXISTS reasoning_embedding;
ALTER TABLE user_amendment_alignments ADD COLUMN reasoning_embedding vector(1024);
CREATE INDEX idx_user_amend_align_reasoning_embedding ON user_amendment_alignments USING hnsw (reasoning_embedding vector_cosine_ops);

-- ============================================================================
-- 17. bill_subject_history.embedding (no index — mirrors bill_subjects but added in 010
--     without one)
-- ============================================================================
ALTER TABLE bill_subject_history DROP COLUMN IF EXISTS embedding;
ALTER TABLE bill_subject_history ADD COLUMN embedding vector(1024);
