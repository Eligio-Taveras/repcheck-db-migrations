-- =============================================================================
-- RepCheck Database Schema — V17a Add completed_with_errors enum value
-- =============================================================================
-- Must run outside a transaction because ALTER TYPE ADD VALUE cannot execute
-- inside a transaction block in PostgreSQL.
-- =============================================================================

ALTER TYPE workflow_status_type ADD VALUE IF NOT EXISTS 'completed_with_errors' AFTER 'completed';
