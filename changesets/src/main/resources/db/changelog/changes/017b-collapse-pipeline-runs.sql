-- =============================================================================
-- RepCheck Database Schema — V17b Collapse Pipeline Runs
-- =============================================================================
-- Eliminates the pipeline_runs table. All pipeline execution tracking is now
-- handled by workflow_runs + workflow_run_steps (two-table model).
--
-- Key changes:
--   1. Add item count columns to workflow_run_steps (absorbed from pipeline_runs)
--   2. Rename processing_results.run_id -> step_run_id, FK to workflow_run_steps
--   3. Remove workflow_run_steps.pipeline_run_id
--   4. Drop stale step_order column from workflow_run_steps
--   5. Rename workflow_runs.trigger -> triggered_by, convert to TEXT
--   6. Drop pipeline_runs table and unused enum types
--
-- Depends on: 017a applied (completed_with_errors enum value).
-- =============================================================================

-- ===========================================================================
-- PHASE 1: Add item count columns to workflow_run_steps
-- ===========================================================================
-- Absorbed from the eliminated pipeline_runs table
ALTER TABLE workflow_run_steps ADD COLUMN IF NOT EXISTS items_processed INTEGER NOT NULL DEFAULT 0;
ALTER TABLE workflow_run_steps ADD COLUMN IF NOT EXISTS items_succeeded INTEGER NOT NULL DEFAULT 0;
ALTER TABLE workflow_run_steps ADD COLUMN IF NOT EXISTS items_failed INTEGER NOT NULL DEFAULT 0;

-- ===========================================================================
-- PHASE 2: Migrate processing_results FK from pipeline_runs to workflow_run_steps
-- ===========================================================================

-- 2a. Drop the existing FK: processing_results.run_id -> pipeline_runs(id)
ALTER TABLE processing_results DROP CONSTRAINT IF EXISTS processing_results_run_id_fkey;

-- 2b. Map existing processing_results to workflow_run_steps via pipeline_run_id
-- For each processing_result, find the workflow_run_step that referenced the
-- same pipeline_run_id and update run_id to point to that step's id.
UPDATE processing_results pr
SET run_id = wrs.id
FROM workflow_run_steps wrs
WHERE wrs.pipeline_run_id = pr.run_id;

-- 2c. Delete orphaned rows that could not be mapped
DELETE FROM processing_results
WHERE run_id NOT IN (SELECT id FROM workflow_run_steps);

-- 2d. Rename the column
ALTER TABLE processing_results RENAME COLUMN run_id TO step_run_id;

-- 2e. Add the new FK: processing_results.step_run_id -> workflow_run_steps(id)
ALTER TABLE processing_results
  ADD CONSTRAINT processing_results_step_run_id_fkey
  FOREIGN KEY (step_run_id) REFERENCES workflow_run_steps(id) ON DELETE CASCADE;

-- Update index to match renamed column
DROP INDEX IF EXISTS idx_processing_results_run;
CREATE INDEX idx_processing_results_step_run ON processing_results(step_run_id);

-- ===========================================================================
-- PHASE 3: Remove pipeline_run_id from workflow_run_steps
-- ===========================================================================
ALTER TABLE workflow_run_steps DROP CONSTRAINT IF EXISTS workflow_run_steps_pipeline_run_id_fkey;
ALTER TABLE workflow_run_steps DROP COLUMN IF EXISTS pipeline_run_id;

-- ===========================================================================
-- PHASE 4: Drop stale step_order column and constraint
-- ===========================================================================
ALTER TABLE workflow_run_steps DROP CONSTRAINT IF EXISTS uq_workflow_step_order;
ALTER TABLE workflow_run_steps DROP COLUMN IF EXISTS step_order;

-- ===========================================================================
-- PHASE 5: Rename workflow_runs.trigger -> triggered_by, convert to TEXT
-- ===========================================================================
-- Convert from trigger_type enum to TEXT for open-ended values
-- (e.g., 'daily-initializer', 'standalone', 'scheduled', 'manual')
ALTER TABLE workflow_runs ALTER COLUMN trigger TYPE TEXT USING trigger::TEXT;
ALTER TABLE workflow_runs RENAME COLUMN trigger TO triggered_by;

-- ===========================================================================
-- PHASE 6: Drop pipeline_runs table
-- ===========================================================================
DROP TABLE IF EXISTS pipeline_runs CASCADE;

-- ===========================================================================
-- PHASE 7: Drop unused enum types
-- ===========================================================================
-- pipeline_status_type was only used by pipeline_runs (now dropped)
-- trigger_type was used by pipeline_runs and workflow_runs (both converted)
DROP TYPE IF EXISTS pipeline_status_type;
DROP TYPE IF EXISTS trigger_type;
