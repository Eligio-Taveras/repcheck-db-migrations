-- =============================================================================
-- RepCheck Database Schema — V2 Schema Expansion
-- =============================================================================
-- Adds tables defined in acceptance criteria but missing from V1:
--   - bill_text_versions (§1.4, §4.7)
--   - lis_member_mapping (§1.2, §5.5)
--   - committees, committee_members, bill_committee_referrals (§1.3)
--   - member_history, member_term_history (§1.2)
--   - bill_history, bill_cosponsor_history, bill_subject_history (§4.2)
--   - workflow_runs, workflow_run_steps (§2.6)
--
-- Expands analysis tables for structured per-concept results:
--   - bill_concept_summaries (new — per-concept decomposition + Pass 1 results)
--   - bill_analysis_topics (new — normalized topic scores with confidence)
--   - bill_fiscal_estimates (new — normalized fiscal estimate output)
--   - bill_analyses: add reading_level, key_points, per-pass model columns
--   - bill_findings: add concept_group_id, severity, confidence, affected_section, affected_group
--
-- Adds missing columns:
--   - score_history.reasoning (§1.5)
--   - bills.latest_text_version_id (§1.4)
--
-- Adds missing finding_types:
--   - impact_analysis, fiscal_estimate
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. bill_text_versions — Immutable text versions per bill (§1.4, §4.7)
--    Each legislative stage produces a new version; supports diffing
-- ---------------------------------------------------------------------------

CREATE TABLE bill_text_versions (
    version_id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id              BIGINT      NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    version_code         TEXT        NOT NULL,     -- TextVersionCode enum: 'IH', 'IS', 'RH', etc.
    version_type         TEXT,                     -- full name: 'Introduced in House', etc.
    version_date         TIMESTAMPTZ,
    format_type          TEXT,                     -- 'Formatted Text', 'PDF', 'Formatted XML'
    url                  TEXT,                     -- source URL
    content              TEXT,                     -- full text if fetched (NULL until downloaded)
    embedding            vector(1536),             -- computed after content fetched
    fetched_at           TIMESTAMPTZ,              -- when content was downloaded
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_bill_text_versions UNIQUE (bill_id, version_code, version_date)
);

CREATE INDEX idx_bill_text_versions_bill ON bill_text_versions (bill_id);
CREATE INDEX idx_bill_text_versions_code ON bill_text_versions (version_code);

-- ---------------------------------------------------------------------------
-- 1a. Add latest_text_version_id FK to bills table (§1.4)
-- ---------------------------------------------------------------------------

ALTER TABLE bills ADD COLUMN latest_text_version_id UUID REFERENCES bill_text_versions(version_id);

-- ---------------------------------------------------------------------------
-- 2. lis_member_mapping — Senate LIS ID to bioguideId (§1.2, §5.5)
-- ---------------------------------------------------------------------------

CREATE TABLE lis_member_mapping (
    lis_member_id        TEXT        PRIMARY KEY,  -- e.g., "S428"
    member_id            TEXT        NOT NULL REFERENCES members(member_id),
    last_verified         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_lis_mapping_member ON lis_member_mapping (member_id);

-- ---------------------------------------------------------------------------
-- 3. committees — Congressional committees (§1.3)
-- ---------------------------------------------------------------------------

CREATE TABLE committees (
    committee_id         TEXT        PRIMARY KEY,  -- systemCode from Congress.gov
    name                 TEXT        NOT NULL,
    chamber              TEXT        NOT NULL,     -- 'House', 'Senate', 'Joint'
    committee_type       TEXT,                     -- 'Standing', 'Select', 'Joint', etc.
    parent_committee_id  TEXT        REFERENCES committees(committee_id),  -- for subcommittees
    url                  TEXT,
    update_date          TIMESTAMPTZ NOT NULL,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_committees_chamber ON committees (chamber);
CREATE INDEX idx_committees_parent ON committees (parent_committee_id);

-- ---------------------------------------------------------------------------
-- 3a. committee_members — Committee membership (§1.3)
-- ---------------------------------------------------------------------------

CREATE TABLE committee_members (
    committee_id         TEXT        NOT NULL REFERENCES committees(committee_id) ON DELETE CASCADE,
    member_id            TEXT        NOT NULL REFERENCES members(member_id),
    role                 TEXT,                     -- 'Chair', 'Ranking Member', 'Member'
    start_date           DATE,
    end_date             DATE,

    PRIMARY KEY (committee_id, member_id)
);

CREATE INDEX idx_committee_members_member ON committee_members (member_id);

-- ---------------------------------------------------------------------------
-- 3b. bill_committee_referrals — Bill-to-committee referrals (§1.3)
-- ---------------------------------------------------------------------------

CREATE TABLE bill_committee_referrals (
    bill_id              BIGINT      NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    committee_id         TEXT        NOT NULL REFERENCES committees(committee_id),
    referral_date        DATE,
    activity_date        DATE,
    activity_name        TEXT,                     -- e.g., 'Referred to', 'Markup', 'Hearings Held'

    PRIMARY KEY (bill_id, committee_id)
);

CREATE INDEX idx_bill_committee_referrals_committee ON bill_committee_referrals (committee_id);

-- ---------------------------------------------------------------------------
-- 4. member_history — Archive-before-overwrite for members (§1.2)
-- ---------------------------------------------------------------------------

CREATE TABLE member_history (
    history_id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id            TEXT        NOT NULL,     -- no FK — member may be updated after archive
    first_name           TEXT        NOT NULL,
    last_name            TEXT        NOT NULL,
    direct_order_name    TEXT,
    inverted_order_name  TEXT,
    honorific_name       TEXT,
    birth_year           TEXT,
    current_party        TEXT        NOT NULL,
    state                TEXT        NOT NULL,
    district             INT,
    image_url            TEXT,
    image_attribution    TEXT,
    official_url         TEXT,
    update_date          TIMESTAMPTZ NOT NULL,
    archived_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_member_history_member ON member_history (member_id);
CREATE INDEX idx_member_history_archived ON member_history (archived_at);

-- ---------------------------------------------------------------------------
-- 4a. member_term_history — Archived terms linked to member_history (§1.2)
-- ---------------------------------------------------------------------------

CREATE TABLE member_term_history (
    history_id           UUID        NOT NULL REFERENCES member_history(history_id) ON DELETE CASCADE,
    member_id            TEXT        NOT NULL,
    chamber              TEXT        NOT NULL,
    congress             INT,
    start_year           INT         NOT NULL,
    end_year             INT,
    member_type          TEXT,
    state_code           TEXT,
    state_name           TEXT,
    district             INT,

    PRIMARY KEY (history_id, member_id, chamber, start_year)
);

-- ---------------------------------------------------------------------------
-- 5. bill_history — Archive-before-overwrite for bills (§4.2)
-- ---------------------------------------------------------------------------

CREATE TABLE bill_history (
    history_id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id              BIGINT      NOT NULL,
    congress             INT         NOT NULL,
    bill_type            TEXT        NOT NULL,
    number               INT         NOT NULL,
    title                TEXT        NOT NULL,
    origin_chamber       TEXT,
    origin_chamber_code  TEXT,
    introduced_date      DATE,
    policy_area          TEXT,
    latest_action_date   DATE,
    latest_action_text   TEXT,
    constitutional_authority_text TEXT,
    sponsor_bioguide_id  TEXT,
    text_url             TEXT,
    text_format          TEXT,
    text_version_type    TEXT,
    text_date            TIMESTAMPTZ,
    summary_text         TEXT,
    summary_action_desc  TEXT,
    summary_action_date  DATE,
    update_date          TIMESTAMPTZ NOT NULL,
    update_date_including_text TIMESTAMPTZ,
    legislation_url      TEXT,
    api_url              TEXT,
    archived_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bill_history_bill ON bill_history (bill_id);
CREATE INDEX idx_bill_history_archived ON bill_history (archived_at);

-- ---------------------------------------------------------------------------
-- 5a. bill_cosponsor_history — Archived cosponsors linked to bill_history (§4.2)
-- ---------------------------------------------------------------------------

CREATE TABLE bill_cosponsor_history (
    history_id           UUID        NOT NULL REFERENCES bill_history(history_id) ON DELETE CASCADE,
    bill_id              BIGINT      NOT NULL,
    member_id            TEXT        NOT NULL,
    is_original_cosponsor BOOLEAN,
    sponsorship_date     DATE,

    PRIMARY KEY (history_id, bill_id, member_id)
);

-- ---------------------------------------------------------------------------
-- 5b. bill_subject_history — Archived subjects linked to bill_history (§4.2)
-- ---------------------------------------------------------------------------

CREATE TABLE bill_subject_history (
    history_id           UUID        NOT NULL REFERENCES bill_history(history_id) ON DELETE CASCADE,
    bill_id              BIGINT      NOT NULL,
    subject_name         TEXT        NOT NULL,
    update_date          TIMESTAMPTZ,

    PRIMARY KEY (history_id, bill_id, subject_name)
);

-- ---------------------------------------------------------------------------
-- 6. workflow_runs — Workflow execution tracking (§2.6)
-- ---------------------------------------------------------------------------

CREATE TABLE workflow_runs (
    workflow_run_id      UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    workflow_name        TEXT        NOT NULL,     -- e.g., 'full-ingest', 'bill-analysis'
    status               TEXT        NOT NULL DEFAULT 'pending',  -- 'pending', 'running', 'completed', 'failed'
    trigger              TEXT        NOT NULL DEFAULT 'scheduled',
    started_at           TIMESTAMPTZ,
    completed_at         TIMESTAMPTZ,
    error_message        TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_workflow_runs_name ON workflow_runs (workflow_name);
CREATE INDEX idx_workflow_runs_status ON workflow_runs (status);

-- ---------------------------------------------------------------------------
-- 6a. workflow_run_steps — Individual steps within a workflow run (§2.6)
-- ---------------------------------------------------------------------------

CREATE TABLE workflow_run_steps (
    step_id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    workflow_run_id      UUID        NOT NULL REFERENCES workflow_runs(workflow_run_id) ON DELETE CASCADE,
    step_name            TEXT        NOT NULL,     -- e.g., 'fetch-bills', 'analyze-bills'
    step_order           INT         NOT NULL,
    status               TEXT        NOT NULL DEFAULT 'pending',
    pipeline_run_id      UUID        REFERENCES pipeline_runs(run_id),  -- link to the pipeline run if applicable
    started_at           TIMESTAMPTZ,
    completed_at         TIMESTAMPTZ,
    error_message        TEXT,

    CONSTRAINT uq_workflow_step_order UNIQUE (workflow_run_id, step_order)
);

CREATE INDEX idx_workflow_steps_run ON workflow_run_steps (workflow_run_id);

-- =============================================================================
-- ANALYSIS SCHEMA EXPANSION — Structured per-concept results
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 7. bill_concept_summaries — Per-concept decomposition + Pass 1 results
--    Each row = one concept group from decomposition, with its Pass 1 summary
--    Enables per-concept semantic search and cross-bill concept comparison
-- ---------------------------------------------------------------------------

CREATE TABLE bill_concept_summaries (
    concept_summary_id   UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id          UUID        NOT NULL REFERENCES bill_analyses(analysis_id) ON DELETE CASCADE,
    bill_id              BIGINT      NOT NULL REFERENCES bills(id),
    group_id             TEXT        NOT NULL,     -- e.g., "transportation-funding" — stable within an analysis
    title                TEXT        NOT NULL,     -- human-readable concept name
    topics               TEXT[]      NOT NULL DEFAULT '{}',  -- from section-classification step
    section_references   TEXT[]      NOT NULL DEFAULT '{}',  -- which bill sections are in this group
    simplified_text      TEXT        NOT NULL,     -- LLM-produced summary from decomposition
    summary              TEXT,                     -- Pass 1 BillSummaryOutput.summary for this concept
    reading_level        TEXT,                     -- Pass 1 BillSummaryOutput.readingLevel
    key_points           TEXT[]      NOT NULL DEFAULT '{}',  -- Pass 1 BillSummaryOutput.keyPoints
    embedding            vector(1536),             -- embedding of simplified_text for semantic search
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_concept_per_analysis UNIQUE (analysis_id, group_id)
);

CREATE INDEX idx_concept_summaries_analysis ON bill_concept_summaries (analysis_id);
CREATE INDEX idx_concept_summaries_bill ON bill_concept_summaries (bill_id);

-- HNSW index for per-concept semantic search
CREATE INDEX idx_concept_summaries_embedding ON bill_concept_summaries
    USING hnsw (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- 7a. bill_analysis_topics — Normalized topic scores with confidence
--     Replaces the flat TEXT[] topics on bill_analyses for structured output
--     Can be per-concept (concept_group_id set) or bill-wide (NULL)
-- ---------------------------------------------------------------------------

CREATE TABLE bill_analysis_topics (
    topic_id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id          UUID        NOT NULL REFERENCES bill_analyses(analysis_id) ON DELETE CASCADE,
    bill_id              BIGINT      NOT NULL REFERENCES bills(id),
    concept_group_id     TEXT,                     -- NULL = bill-wide topic; set = per-concept
    topic                TEXT        NOT NULL,
    confidence           FLOAT       NOT NULL,     -- 0.0-1.0

    CONSTRAINT uq_analysis_topic UNIQUE (analysis_id, concept_group_id, topic)
);

CREATE INDEX idx_analysis_topics_analysis ON bill_analysis_topics (analysis_id);
CREATE INDEX idx_analysis_topics_bill ON bill_analysis_topics (bill_id);
CREATE INDEX idx_analysis_topics_topic ON bill_analysis_topics (topic);

-- ---------------------------------------------------------------------------
-- 7b. bill_fiscal_estimates — Normalized fiscal estimate output (Pass 2)
--     One row per analysis run; assumptions stored as TEXT[] (simple string list)
-- ---------------------------------------------------------------------------

CREATE TABLE bill_fiscal_estimates (
    fiscal_estimate_id   UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id          UUID        NOT NULL REFERENCES bill_analyses(analysis_id) ON DELETE CASCADE,
    bill_id              BIGINT      NOT NULL REFERENCES bills(id),
    estimated_cost       TEXT        NOT NULL,     -- e.g., "$1.2 trillion over 10 years"
    timeframe            TEXT        NOT NULL,     -- e.g., "10 years"
    confidence           FLOAT       NOT NULL,     -- 0.0-1.0
    assumptions          TEXT[]      NOT NULL DEFAULT '{}',
    llm_model            TEXT        NOT NULL,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_fiscal_per_analysis UNIQUE (analysis_id)
);

CREATE INDEX idx_fiscal_estimates_analysis ON bill_fiscal_estimates (analysis_id);
CREATE INDEX idx_fiscal_estimates_bill ON bill_fiscal_estimates (bill_id);

-- ---------------------------------------------------------------------------
-- 8. Expand bill_analyses — Per-pass model tracking + overall summary fields
-- ---------------------------------------------------------------------------

ALTER TABLE bill_analyses ADD COLUMN reading_level TEXT;
ALTER TABLE bill_analyses ADD COLUMN key_points TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE bill_analyses ADD COLUMN pass1_model TEXT;
ALTER TABLE bill_analyses ADD COLUMN pass2_model TEXT;
ALTER TABLE bill_analyses ADD COLUMN pass3_model TEXT;

-- ---------------------------------------------------------------------------
-- 9. Expand bill_findings — Normalized structured sub-fields
--    concept_group_id links findings to their concept group (NULL = bill-wide)
--    severity, confidence, affected_section, affected_group avoid JSONB in details
-- ---------------------------------------------------------------------------

ALTER TABLE bill_findings ADD COLUMN concept_group_id TEXT;
ALTER TABLE bill_findings ADD COLUMN severity TEXT;         -- 'High', 'Medium', 'Low' (ImpactSeverity enum)
ALTER TABLE bill_findings ADD COLUMN confidence FLOAT;      -- 0.0-1.0
ALTER TABLE bill_findings ADD COLUMN affected_section TEXT;  -- PorkFinding.affectedSection
ALTER TABLE bill_findings ADD COLUMN affected_group TEXT;    -- ImpactItem.affectedGroup

CREATE INDEX idx_bill_findings_concept ON bill_findings (concept_group_id);

-- ---------------------------------------------------------------------------
-- 10. Expand amendment_findings — Same normalized sub-fields
-- ---------------------------------------------------------------------------

ALTER TABLE amendment_findings ADD COLUMN severity TEXT;
ALTER TABLE amendment_findings ADD COLUMN confidence FLOAT;
ALTER TABLE amendment_findings ADD COLUMN affected_section TEXT;

-- ---------------------------------------------------------------------------
-- 11. Add missing finding_types for Pass 2 output schemas
-- ---------------------------------------------------------------------------

INSERT INTO finding_types (finding_type_id, display_name, description) VALUES
    ('impact_analysis', 'Impact Analysis', 'Analysis of who is affected and how (Pass 2 — Sonnet)'),
    ('fiscal_estimate', 'Fiscal Estimate', 'Estimated cost, timeframe, and fiscal impact (Pass 2 — Sonnet)');

-- ---------------------------------------------------------------------------
-- 12. Add reasoning column to score_history (§1.5)
-- ---------------------------------------------------------------------------

ALTER TABLE score_history ADD COLUMN reasoning TEXT;
