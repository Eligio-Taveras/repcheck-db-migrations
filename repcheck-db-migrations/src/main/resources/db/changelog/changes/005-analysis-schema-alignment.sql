-- =============================================================================
-- RepCheck Database Schema — V5 Analysis Schema Alignment
-- =============================================================================
-- Aligns the database schema with Component 10 (LLM Analysis) acceptance
-- criteria. Addresses mismatches between the existing schema and the
-- authoritative spec defined in §1.9 and §10.6/10.7.
--
-- Changes:
--   1. finding_types: migrate from TEXT PK to SERIAL INT PK + `code` column
--   2. bill_findings & amendment_findings: FK migration TEXT → INT
--   3. bill_analyses: major expansion for multi-pass analysis lifecycle
--   4. bill_concept_summaries: add pass_number
--   5. bill_analysis_topics: add pass_number
--   6. bill_findings: add pass_number
--   7. bill_fiscal_estimates: add pass_number, concept_group_id
-- =============================================================================

-- ===========================================================================
-- 1. FINDING_TYPES — Migrate from TEXT PK to SERIAL INT PK
--    The TEXT PK (e.g., 'pork', 'stance_detection') becomes the `code` column.
--    A new auto-incrementing INT becomes the PK.
--    Also rename display_name → name for consistency with Component 10 spec.
-- ===========================================================================

-- 1a. Drop FK constraints referencing the old TEXT PK
ALTER TABLE bill_findings DROP CONSTRAINT IF EXISTS bill_findings_finding_type_id_fkey;
ALTER TABLE amendment_findings DROP CONSTRAINT IF EXISTS amendment_findings_finding_type_id_fkey;

-- 1b. Rename the TEXT PK column to `code`
ALTER TABLE finding_types RENAME COLUMN finding_type_id TO code;

-- 1c. Drop the old TEXT PK constraint and add UNIQUE on code
ALTER TABLE finding_types DROP CONSTRAINT finding_types_pkey;
ALTER TABLE finding_types ADD CONSTRAINT uq_finding_types_code UNIQUE (code);

-- 1d. Add the new SERIAL INT PK
ALTER TABLE finding_types ADD COLUMN finding_type_id SERIAL;
ALTER TABLE finding_types ADD CONSTRAINT finding_types_pkey PRIMARY KEY (finding_type_id);

-- 1e. Rename display_name → name (matches Component 10 AnalysisFindingType.name)
ALTER TABLE finding_types RENAME COLUMN display_name TO name;

-- ===========================================================================
-- 2. BILL_FINDINGS — Migrate finding_type FK from TEXT to INT
-- ===========================================================================

-- 2a. Rename old TEXT column
ALTER TABLE bill_findings RENAME COLUMN finding_type_id TO finding_type_code;

-- 2b. Add new INT column
ALTER TABLE bill_findings ADD COLUMN finding_type_id INT;

-- 2c. Populate from finding_types lookup
UPDATE bill_findings bf
SET finding_type_id = ft.finding_type_id
FROM finding_types ft
WHERE bf.finding_type_code = ft.code;

-- 2d. Make NOT NULL and add FK
ALTER TABLE bill_findings ALTER COLUMN finding_type_id SET NOT NULL;
ALTER TABLE bill_findings ADD CONSTRAINT bill_findings_finding_type_id_fkey
    FOREIGN KEY (finding_type_id) REFERENCES finding_types(finding_type_id);

-- 2e. Drop old TEXT column and recreate index
ALTER TABLE bill_findings DROP COLUMN finding_type_code;
DROP INDEX IF EXISTS idx_bill_findings_type;
CREATE INDEX idx_bill_findings_type ON bill_findings (finding_type_id);

-- ===========================================================================
-- 3. AMENDMENT_FINDINGS — Migrate finding_type FK from TEXT to INT
-- ===========================================================================

-- 3a. Rename old TEXT column
ALTER TABLE amendment_findings RENAME COLUMN finding_type_id TO finding_type_code;

-- 3b. Add new INT column
ALTER TABLE amendment_findings ADD COLUMN finding_type_id INT;

-- 3c. Populate from finding_types lookup
UPDATE amendment_findings af
SET finding_type_id = ft.finding_type_id
FROM finding_types ft
WHERE af.finding_type_code = ft.code;

-- 3d. Make NOT NULL and add FK
ALTER TABLE amendment_findings ALTER COLUMN finding_type_id SET NOT NULL;
ALTER TABLE amendment_findings ADD CONSTRAINT amendment_findings_finding_type_id_fkey
    FOREIGN KEY (finding_type_id) REFERENCES finding_types(finding_type_id);

-- 3e. Drop old TEXT column and recreate index
ALTER TABLE amendment_findings DROP COLUMN finding_type_code;
DROP INDEX IF EXISTS idx_amendment_findings_type;
CREATE INDEX idx_amendment_findings_type ON amendment_findings (finding_type_id);

-- ===========================================================================
-- 4. BILL_ANALYSES — Major expansion for multi-pass analysis lifecycle
--    Replaces: pass_completed → passes_executed, llm_model → highest_model_used,
--              analyzed_at → created_at
--    Adds: status, version_id, failure_reason, completed_at, routing score columns
-- ===========================================================================

-- 4a. Rename existing columns to match DO spec
ALTER TABLE bill_analyses RENAME COLUMN pass_completed TO _pass_completed_old;
ALTER TABLE bill_analyses RENAME COLUMN llm_model TO _llm_model_old;
ALTER TABLE bill_analyses RENAME COLUMN analyzed_at TO created_at;

-- 4b. Add new columns
ALTER TABLE bill_analyses ADD COLUMN version_id UUID REFERENCES bill_text_versions(version_id);
ALTER TABLE bill_analyses ADD COLUMN status TEXT NOT NULL DEFAULT 'completed';
ALTER TABLE bill_analyses ADD COLUMN passes_executed INT[] NOT NULL DEFAULT '{}';
ALTER TABLE bill_analyses ADD COLUMN highest_model_used TEXT;
ALTER TABLE bill_analyses ADD COLUMN failure_reason TEXT;
ALTER TABLE bill_analyses ADD COLUMN completed_at TIMESTAMPTZ;

-- Routing score columns (Pass 1)
ALTER TABLE bill_analyses ADD COLUMN high_profile_score FLOAT;
ALTER TABLE bill_analyses ADD COLUMN media_coverage_level FLOAT;
ALTER TABLE bill_analyses ADD COLUMN appropriations_estimate NUMERIC;
ALTER TABLE bill_analyses ADD COLUMN stance_confidence FLOAT;
ALTER TABLE bill_analyses ADD COLUMN routing_reasoning TEXT;

-- Routing score columns (Pass 2)
ALTER TABLE bill_analyses ADD COLUMN overall_confidence FLOAT;
ALTER TABLE bill_analyses ADD COLUMN cross_concept_contradiction_score FLOAT;
ALTER TABLE bill_analyses ADD COLUMN expected_vote_contention FLOAT;
ALTER TABLE bill_analyses ADD COLUMN contradiction_details TEXT;
ALTER TABLE bill_analyses ADD COLUMN routing_reasoning_pass2 TEXT;

-- 4c. Migrate existing data
UPDATE bill_analyses
SET passes_executed = ARRAY[_pass_completed_old],
    highest_model_used = _llm_model_old,
    completed_at = created_at;

-- 4d. Drop old columns
ALTER TABLE bill_analyses DROP COLUMN _pass_completed_old;
ALTER TABLE bill_analyses DROP COLUMN _llm_model_old;

-- 4e. Add index on status for filtering in-progress/failed runs
CREATE INDEX idx_bill_analyses_status ON bill_analyses (status);

-- ===========================================================================
-- 5. BILL_CONCEPT_SUMMARIES — Add pass_number
-- ===========================================================================

ALTER TABLE bill_concept_summaries ADD COLUMN pass_number INT NOT NULL DEFAULT 1;

-- ===========================================================================
-- 6. BILL_ANALYSIS_TOPICS — Add pass_number
-- ===========================================================================

ALTER TABLE bill_analysis_topics ADD COLUMN pass_number INT NOT NULL DEFAULT 1;

-- Drop old unique constraint and recreate with pass_number
ALTER TABLE bill_analysis_topics DROP CONSTRAINT IF EXISTS uq_analysis_topic;
ALTER TABLE bill_analysis_topics ADD CONSTRAINT uq_analysis_topic
    UNIQUE (analysis_id, concept_group_id, topic, pass_number);

-- ===========================================================================
-- 7. BILL_FINDINGS — Add pass_number
-- ===========================================================================

ALTER TABLE bill_findings ADD COLUMN pass_number INT NOT NULL DEFAULT 1;

CREATE INDEX idx_bill_findings_pass ON bill_findings (pass_number);

-- ===========================================================================
-- 8. BILL_FISCAL_ESTIMATES — Add pass_number and concept_group_id
-- ===========================================================================

ALTER TABLE bill_fiscal_estimates ADD COLUMN pass_number INT NOT NULL DEFAULT 1;
ALTER TABLE bill_fiscal_estimates ADD COLUMN concept_group_id UUID
    REFERENCES bill_concept_groups(concept_group_id);

-- Drop old unique constraint (one per analysis) and recreate for multi-pass + concept groups
ALTER TABLE bill_fiscal_estimates DROP CONSTRAINT IF EXISTS uq_fiscal_per_analysis;
ALTER TABLE bill_fiscal_estimates ADD CONSTRAINT uq_fiscal_per_analysis_group_pass
    UNIQUE (analysis_id, concept_group_id, pass_number);

CREATE INDEX idx_fiscal_estimates_concept ON bill_fiscal_estimates (concept_group_id);

-- ===========================================================================
-- 9. Add missing finding types for Component 10 analysis categories
--    Existing types: topic_extraction, bill_summary, policy_analysis,
--    stance_detection, pork, rider, lobbying, constitutional,
--    impact_analysis, fiscal_estimate
--    Missing: civil_liberties, environmental (used in 10.7 impact mapping)
-- ===========================================================================

INSERT INTO finding_types (code, name, description) VALUES
    ('civil_liberties', 'Civil Liberties Impact', 'Impact on civil liberties, privacy, or individual rights'),
    ('environmental', 'Environmental Impact', 'Impact on the environment, climate, or natural resources')
ON CONFLICT (code) DO NOTHING;
