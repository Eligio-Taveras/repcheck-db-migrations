-- Migration 012: Placeholder support and workflow step tracking columns
--
-- Two concerns addressed:
--
-- 1. PLACEHOLDER SUPPORT — The PK standardization (migration 011) enables placeholder rows
--    (insert with only the key fields, fill in the rest later). This migration relaxes NOT
--    NULL constraints on non-key columns so placeholder inserts succeed.
--
--    For single TEXT natural_key tables (members, committees, qa_questions): only natural_key
--    is required. For composite natural key tables (bills, votes, amendments): the composite
--    key columns stay NOT NULL; all other columns become nullable.
--
-- 2. WORKFLOW STEP TRACKING — The WorkflowStateUpdater (ingestion-common) requires retry
--    tracking and audit columns on workflow_run_steps that were designed but not yet present
--    in the production schema. This migration adds them and the unique constraint the
--    ON CONFLICT upsert relies on.

-- ===========================================================================
-- SECTION 1: Relax NOT NULL constraints for placeholder support
-- ===========================================================================

-- ── Single natural_key tables ─────────────────────────────────────────────

-- members — placeholder rows contain only natural_key; all other fields are populated
-- by the members ingestion pipeline on its next run.
ALTER TABLE members ALTER COLUMN first_name DROP NOT NULL;
ALTER TABLE members ALTER COLUMN last_name DROP NOT NULL;
ALTER TABLE members ALTER COLUMN current_party DROP NOT NULL;
ALTER TABLE members ALTER COLUMN state DROP NOT NULL;
ALTER TABLE members ALTER COLUMN update_date DROP NOT NULL;

-- committees — placeholder rows contain only natural_key.
ALTER TABLE committees ALTER COLUMN name DROP NOT NULL;
ALTER TABLE committees ALTER COLUMN chamber DROP NOT NULL;
ALTER TABLE committees ALTER COLUMN update_date DROP NOT NULL;

-- qa_questions — placeholder rows contain only natural_key.
ALTER TABLE qa_questions ALTER COLUMN question_text DROP NOT NULL;

-- ── Composite natural key tables ──────────────────────────────────────────
-- Composite key columns stay NOT NULL; all other NOT NULL columns are relaxed.

-- bills — composite key: (congress, bill_type, number). Relax non-key columns.
ALTER TABLE bills ALTER COLUMN title DROP NOT NULL;
ALTER TABLE bills ALTER COLUMN update_date DROP NOT NULL;

-- votes — composite key: (congress, chamber, roll_number). Relax non-key columns.
ALTER TABLE votes ALTER COLUMN question DROP NOT NULL;
ALTER TABLE votes ALTER COLUMN vote_type DROP NOT NULL;
ALTER TABLE votes ALTER COLUMN result DROP NOT NULL;
ALTER TABLE votes ALTER COLUMN vote_date DROP NOT NULL;
ALTER TABLE votes ALTER COLUMN update_date DROP NOT NULL;

-- amendments — composite key: (congress, amendment_type, number). Relax non-key columns.
ALTER TABLE amendments ALTER COLUMN update_date DROP NOT NULL;

-- ===========================================================================
-- SECTION 2: Add workflow step tracking columns
-- ===========================================================================

-- retry_count and max_retries enable the WorkflowStateUpdater to track how many
-- times a step has been retried and the configured ceiling.
ALTER TABLE workflow_run_steps ADD COLUMN IF NOT EXISTS retry_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE workflow_run_steps ADD COLUMN IF NOT EXISTS max_retries INTEGER NOT NULL DEFAULT 3;
ALTER TABLE workflow_run_steps ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE workflow_run_steps ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- The WorkflowStateUpdater upserts via ON CONFLICT (workflow_run_id, step_name).
-- The existing constraint is on (workflow_run_id, step_order) which serves a different
-- purpose (ordering within a run). Add the name-based constraint for upsert support.
-- Drop the step_order NOT NULL since code-driven inserts don't always supply it.
ALTER TABLE workflow_run_steps ALTER COLUMN step_order DROP NOT NULL;

-- This migration runs exactly once, so the constraint cannot already exist.
ALTER TABLE workflow_run_steps
  ADD CONSTRAINT uq_workflow_step_name UNIQUE (workflow_run_id, step_name);
