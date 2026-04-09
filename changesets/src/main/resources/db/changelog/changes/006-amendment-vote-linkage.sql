-- =============================================================================
-- RepCheck Database Schema — V6 Amendment Vote Linkage & Concept Summaries
-- =============================================================================
-- Links amendment votes to their amendments so the scoring engine (Component 11
-- §11.2) can look up amendment-specific stance findings instead of using the
-- parent bill's stance direction. Also adds amendment_concept_summaries for
-- amendment-level explanations in the score explainer (§11.4).
--
-- Problem: When vote_type = 'Amendment', the vote is on an amendment that may
-- have a different (even opposite) stance direction than the parent bill. Without
-- an explicit link, the scoring engine uses bill_findings for all votes —
-- incorrectly attributing the bill's stance to amendment votes. Additionally,
-- without amendment concept summaries, the LLM can only explain amendment votes
-- in terms of the parent bill — losing the specific context of what the amendment
-- does.
--
-- Changes:
--   1. votes: add amendment_id (nullable FK → amendments)
--   2. vote_history: add amendment_id (nullable, no FK — history is a snapshot)
--   3. member_bill_stances: add amendment_id (nullable FK → amendments)
--   4. amendment_analyses: new table mirroring bill_analyses for amendment analysis runs
--   5. amendment_concept_summaries: new table mirroring bill_concept_summaries
--   6. amendment_analysis_topics: new table mirroring bill_analysis_topics
--   7. amendment_findings: add analysis_id FK + pass_number to link to analysis runs
-- =============================================================================

-- ===========================================================================
-- 1. VOTES — Add amendment_id
--    Nullable: only set when vote_type = 'Amendment'.
--    FK to amendments table for referential integrity.
-- ===========================================================================

ALTER TABLE votes
    ADD COLUMN amendment_id TEXT REFERENCES amendments(amendment_id);

COMMENT ON COLUMN votes.amendment_id IS
    'FK to amendments; set when vote_type = ''Amendment''. Enables scoring engine to look up amendment-specific stance findings.';

CREATE INDEX idx_votes_amendment_id ON votes (amendment_id) WHERE amendment_id IS NOT NULL;

-- ===========================================================================
-- 2. VOTE_HISTORY — Add amendment_id
--    No FK constraint — vote_history is an archive snapshot. The referenced
--    amendment may have been modified since archival.
-- ===========================================================================

ALTER TABLE vote_history
    ADD COLUMN amendment_id TEXT;

COMMENT ON COLUMN vote_history.amendment_id IS
    'Amendment ID at time of archival; no FK constraint (snapshot data).';

-- ===========================================================================
-- 3. MEMBER_BILL_STANCES — Add amendment_id
--    Nullable: only set when the vote is on an amendment.
--    FK to amendments for referential integrity.
--    Used by LegislatorProfileBuilder (§11.2) and AlignmentEvidenceFetcher
--    (§11.4) to branch stance lookup: amendment_findings when set,
--    bill_findings when NULL.
-- ===========================================================================

ALTER TABLE member_bill_stances
    ADD COLUMN amendment_id TEXT REFERENCES amendments(amendment_id);

COMMENT ON COLUMN member_bill_stances.amendment_id IS
    'FK to amendments; set when vote_type = ''Amendment''. Scoring engine uses amendment_findings instead of bill_findings for stance direction.';

CREATE INDEX idx_member_bill_stances_amendment
    ON member_bill_stances (amendment_id) WHERE amendment_id IS NOT NULL;

-- ===========================================================================
-- 4. AMENDMENT_ANALYSES — Analysis runs for amendments
--    Mirrors bill_analyses. Amendments go through the same analysis pipeline
--    as bills: decomposition → multi-pass LLM analysis → findings.
--    Even though amendments are typically shorter than bills, they follow the
--    same lifecycle for consistency and to produce the same quality of output.
-- ===========================================================================

CREATE TABLE amendment_analyses (
    analysis_id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    amendment_id         TEXT        NOT NULL REFERENCES amendments(amendment_id),
    bill_id              BIGINT      NOT NULL REFERENCES bills(id),  -- parent bill for context
    status               TEXT        NOT NULL DEFAULT 'in_progress',  -- 'in_progress', 'completed', 'failed'
    summary              TEXT,                     -- amendment-wide summary (what this amendment does)
    topics               TEXT[]      NOT NULL DEFAULT '{}',  -- topic tags
    reading_level        TEXT,
    key_points           TEXT[]      NOT NULL DEFAULT '{}',
    key_changes          TEXT[]      NOT NULL DEFAULT '{}',  -- bullet-point changes to the parent bill
    passes_executed      INT[]       NOT NULL DEFAULT '{}',
    highest_model_used   TEXT,
    pass1_model          TEXT,
    pass2_model          TEXT,
    pass3_model          TEXT,
    embedding            vector(1536),
    stance_direction     TEXT,       -- 'Progressive', 'Conservative', 'Bipartisan', 'Neutral' (from stance finding)
    stance_confidence    FLOAT,
    routing_reasoning    TEXT,
    overall_confidence   FLOAT,
    failure_reason       TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at         TIMESTAMPTZ,
    analyzed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_amendment_analysis_status CHECK (status IN ('in_progress', 'completed', 'failed'))
);

CREATE INDEX idx_amendment_analyses_amendment ON amendment_analyses (amendment_id);
CREATE INDEX idx_amendment_analyses_bill ON amendment_analyses (bill_id);
CREATE INDEX idx_amendment_analyses_status ON amendment_analyses (status);

-- HNSW index for amendment analysis similarity search
CREATE INDEX idx_amendment_analyses_embedding ON amendment_analyses
    USING hnsw (embedding vector_cosine_ops);

-- ===========================================================================
-- 5. AMENDMENT_CONCEPT_SUMMARIES — Per-concept analysis results for amendments
--    Mirrors bill_concept_summaries. Even though amendments are typically
--    single-concept, we use the same structure for consistency. Short
--    amendments will have one concept summary covering the whole amendment.
--    Populated by the amendment analysis pipeline (Component 10 extension).
--    Used by AlignmentEvidenceFetcher (§11.4) to give the LLM specific
--    context about what an amendment does vs what the parent bill does.
-- ===========================================================================

CREATE TABLE amendment_concept_summaries (
    concept_summary_id   UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id          UUID        NOT NULL REFERENCES amendment_analyses(analysis_id) ON DELETE CASCADE,
    amendment_id         TEXT        NOT NULL REFERENCES amendments(amendment_id),
    bill_id              BIGINT      NOT NULL REFERENCES bills(id),  -- parent bill
    pass_number          INT         NOT NULL DEFAULT 1,
    summary              TEXT,                     -- plain-language description of what the amendment does
    topics               TEXT[]      NOT NULL DEFAULT '{}',  -- topics this amendment touches
    reading_level        TEXT,
    key_points           TEXT[]      NOT NULL DEFAULT '{}',
    key_changes          TEXT[]      NOT NULL DEFAULT '{}',  -- bullet-point changes the amendment makes to the parent bill
    embedding            vector(1536),             -- for semantic search
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_amendment_concept_per_analysis UNIQUE (analysis_id, amendment_id)
);

CREATE INDEX idx_amendment_concept_summaries_analysis ON amendment_concept_summaries (analysis_id);
CREATE INDEX idx_amendment_concept_summaries_bill ON amendment_concept_summaries (bill_id);
CREATE INDEX idx_amendment_concept_summaries_amendment ON amendment_concept_summaries (amendment_id);

-- HNSW index for amendment concept similarity search
CREATE INDEX idx_amendment_concept_summaries_embedding ON amendment_concept_summaries
    USING hnsw (embedding vector_cosine_ops);

-- ===========================================================================
-- 6. AMENDMENT_ANALYSIS_TOPICS — Normalized topic scores for amendments
--    Mirrors bill_analysis_topics.
-- ===========================================================================

CREATE TABLE amendment_analysis_topics (
    topic_id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id          UUID        NOT NULL REFERENCES amendment_analyses(analysis_id) ON DELETE CASCADE,
    amendment_id         TEXT        NOT NULL REFERENCES amendments(amendment_id),
    pass_number          INT         NOT NULL DEFAULT 1,
    topic                TEXT        NOT NULL,
    confidence           FLOAT       NOT NULL
);

CREATE INDEX idx_amendment_analysis_topics_analysis ON amendment_analysis_topics (analysis_id);
CREATE INDEX idx_amendment_analysis_topics_amendment ON amendment_analysis_topics (amendment_id);

-- ===========================================================================
-- 7. Add analysis_id FK to amendment_findings
--    amendment_findings predates amendment_analyses. Adding the FK links
--    findings to their analysis run, matching bill_findings → bill_analyses.
-- ===========================================================================

ALTER TABLE amendment_findings
    ADD COLUMN analysis_id UUID REFERENCES amendment_analyses(analysis_id);

ALTER TABLE amendment_findings
    ADD COLUMN pass_number INT NOT NULL DEFAULT 1;

COMMENT ON COLUMN amendment_findings.analysis_id IS
    'FK to amendment_analyses; links findings to their analysis run. Nullable for pre-migration findings.';

CREATE INDEX idx_amendment_findings_analysis ON amendment_findings (analysis_id) WHERE analysis_id IS NOT NULL;
