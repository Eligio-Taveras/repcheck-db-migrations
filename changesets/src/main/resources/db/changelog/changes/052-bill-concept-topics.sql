-- Migration 052: bill_concept_topics — stance-tagged topics per concept group (vectors-primary)
--
-- One row per (concept group, topic). Each concept group (051) gets N topics from the per-cluster
-- summarizer (ConceptSummaryWithTopics). `topic` is the neutrally-framed noun phrase whose
-- `topic_embedding` is the cross-bill retrieval vector; `phrase` + effect/impact/scope/entity are
-- stance metadata persisted for alignment scoring (Component 11), NOT used as the primary vector.
--
-- FK -> bill_concept_groups(id) ON DELETE CASCADE (topics die with their group). NO unique on
-- (group, topic): the summarizer legitimately emits duplicate `topic` rows that differ on
-- phrase/effect/impact (e.g. a concept that both EXPANDS and RESTRICTS the same area).
--
-- Column order mirrors repcheck-shared-models BillConceptTopicDO (id, concept_group_id, phrase,
-- topic, effect, entity, impact, scope, topic_embedding, created_at) so Doobie positional mapping
-- lines up. effect/impact/scope are TEXT + CHECK (matching 051's status convention for the
-- decomposition controlled vocabularies; simplest Doobie Meta[String].timap round-trip). Values are
-- the UPPERCASE apiValues the summarizer emits and the Scala enums encode.
--
-- Additive: new empty table. IF NOT EXISTS-guarded per repo convention so Liquibase can replay
-- against hot-patched dev/local databases. pgvector / hnsw already enabled (051 et al.).

CREATE TABLE IF NOT EXISTS bill_concept_topics (
    id                BIGSERIAL PRIMARY KEY,
    concept_group_id  BIGINT NOT NULL REFERENCES bill_concept_groups(id) ON DELETE CASCADE,
    phrase            TEXT NOT NULL,
    topic             TEXT NOT NULL,
    effect            TEXT NOT NULL CHECK (effect IN ('EXPANDS', 'RESTRICTS', 'CREATES', 'ELIMINATES', 'MODIFIES', 'REPORTS')),
    entity            TEXT NOT NULL,
    impact            TEXT NOT NULL CHECK (impact IN ('POSITIVE', 'NEGATIVE', 'MIXED', 'NEUTRAL')),
    scope             TEXT NOT NULL CHECK (scope IN ('MAJOR', 'MODERATE', 'MINOR')),
    topic_embedding   vector(1024),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- FK lookup / cascade support: topics fetched by their concept group.
CREATE INDEX IF NOT EXISTS idx_bill_concept_topics_group
    ON bill_concept_topics (concept_group_id);

-- Cross-bill topic retrieval (the vectors-primary search vector).
CREATE INDEX IF NOT EXISTS idx_bill_concept_topics_embedding
    ON bill_concept_topics USING hnsw (topic_embedding vector_cosine_ops);
