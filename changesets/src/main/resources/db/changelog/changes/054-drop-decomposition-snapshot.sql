-- Migration 054: Drop the decomposition snapshot schema (decompose keys on version_id ALONE)
--
-- Reverses the snapshot dimension added in migration 053. A bill text version is self-contained, so a
-- decomposition is a pure function of that version's text — independent of any DB metadata snapshot.
-- Gating the existsForVersion reuse-check on a snapshot_version would force re-decomposing every bill on
-- every snapshot (the DB state churns constantly as user data updates); the idempotency key is
-- version_id ALONE. (Decomposition persister PR review, 2026-06-28.)
--
-- Removed:
--   * bill_concept_groups.decomposition_snapshot_version (+ its reuse index) — reuse-check now keys on
--     version_id, so the index is replaced by one on (version_id).
--   * bill_decomposition_runs.snapshot_version — run provenance is KEPT
--     (orchestrator/embedder/clusterer/prompt versions + status + workflow_run_id); only the snapshot FK goes.
--   * pre_llm_metadata_snapshots + pre_llm_metadata_snapshot_members — the snapshot manifest. The concept
--     is decomposition-only and the tables were never populated; no other component references them.
--
-- Kept: bill_decomposition_runs (provenance) + bill_concept_groups.run_id (the producing run).
--
-- All four tables are empty today -> no data loss. IF EXISTS-guarded per repo convention so Liquibase can
-- replay against hot-patched dev/local DBs (including ones where 053 was already applied).

-- Reuse index first (it covers the column being dropped); DROP COLUMN would auto-drop it, this is explicit.
DROP INDEX IF EXISTS idx_bill_concept_groups_reuse;

ALTER TABLE bill_concept_groups DROP COLUMN IF EXISTS decomposition_snapshot_version;

ALTER TABLE bill_decomposition_runs DROP COLUMN IF EXISTS snapshot_version;

-- Members FK pre_llm_metadata_snapshots, so drop it first.
DROP TABLE IF EXISTS pre_llm_metadata_snapshot_members;
DROP TABLE IF EXISTS pre_llm_metadata_snapshots;

-- Reuse-check now keys on version_id alone: existsForVersion(versionId).
CREATE INDEX IF NOT EXISTS idx_bill_concept_groups_version
    ON bill_concept_groups (version_id);
