-- Migration 053: SNAP snapshot manifest + decomposition-run provenance (vectors-primary)
--
-- Resolves the snapshot schema for the decomposition pipeline (master plan SNAP/D22 + the
-- 2026-06-28 orchestrator execution note). Decomposition runs OFF a frozen corpus snapshot so its
-- outputs are reproducible; every output is tagged with the snapshot_version it was produced under.
--
--   * pre_llm_metadata_snapshots (NEW): the snapshot manifest — one row per capture-time T.
--     snapshot_version is the monotonic domain identity (Int, per the SNAP design — snapshots are
--     coarse: one per T, shared across all users). SERIAL PK is an intentional exception to the
--     id-BIGSERIAL convention (migration 011) because snapshot_version IS the version key everything
--     references.
--   * pre_llm_metadata_snapshot_members (NEW): the frozen version_id set (+ subject count) for a
--     snapshot. No FK on version_id — bill_text_versions rows are immutable, so the manifest needs no
--     referential copy.
--   * bill_decomposition_runs (NEW): provenance for one orchestrator sweep within a snapshot — the
--     orchestrator/embedder/clusterer/prompt versions + status. Concept groups link to it via run_id.
--   * bill_concept_groups: + decomposition_snapshot_version (the reuse-check / idempotency dimension)
--     + run_id (the producing run). Index (version_id, decomposition_snapshot_version) drives the
--     existsForVersion reuse-check. Both columns nullable + additive; the table is empty today.
--
-- IF NOT EXISTS-guarded per repo convention so Liquibase can replay against hot-patched dev/local DBs.

CREATE TABLE IF NOT EXISTS pre_llm_metadata_snapshots (
    snapshot_version SERIAL PRIMARY KEY,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    status           TEXT NOT NULL CHECK (status IN ('capturing', 'active', 'superseded'))
);

CREATE TABLE IF NOT EXISTS pre_llm_metadata_snapshot_members (
    snapshot_version INT    NOT NULL REFERENCES pre_llm_metadata_snapshots(snapshot_version) ON DELETE CASCADE,
    version_id       BIGINT NOT NULL,
    subject_count    INT    NOT NULL,
    PRIMARY KEY (snapshot_version, version_id)
);

CREATE TABLE IF NOT EXISTS bill_decomposition_runs (
    id                   BIGSERIAL PRIMARY KEY,
    snapshot_version     INT  NOT NULL REFERENCES pre_llm_metadata_snapshots(snapshot_version),
    orchestrator_version TEXT NOT NULL,
    embedder_version     TEXT NOT NULL,
    clusterer_version    TEXT NOT NULL,
    prompt_version       TEXT NOT NULL,
    status               TEXT NOT NULL CHECK (status IN ('running', 'completed', 'completed_with_errors', 'failed')),
    started_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at         TIMESTAMPTZ,
    workflow_run_id      BIGINT
);

-- Tag concept groups with the snapshot they were produced under + the producing run.
ALTER TABLE bill_concept_groups
    ADD COLUMN IF NOT EXISTS decomposition_snapshot_version INT REFERENCES pre_llm_metadata_snapshots(snapshot_version);
ALTER TABLE bill_concept_groups
    ADD COLUMN IF NOT EXISTS run_id BIGINT REFERENCES bill_decomposition_runs(id);

-- Drives existsForVersion(versionId, snapshotVersion) — the reuse-check / idempotency key.
CREATE INDEX IF NOT EXISTS idx_bill_concept_groups_reuse
    ON bill_concept_groups (version_id, decomposition_snapshot_version);
