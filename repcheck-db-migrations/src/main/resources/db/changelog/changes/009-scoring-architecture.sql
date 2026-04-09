-- =============================================================================
-- RepCheck Database Schema — V9 Scoring Architecture
-- =============================================================================
-- Adds tables for the batch scoring architecture (Component 11):
--   1. user_legislator_pairings — persistent user-to-legislator mapping
--   2. member_bill_stance_topics — per-topic stance with LLM reasoning
--   3. user_bill_alignments — pre-computed user-bill topic alignment
--   4. user_amendment_alignments — pre-computed user-amendment topic alignment
--   5. stance_materialization_status — DB-polling readiness tracker
--   6. ALTER users — add last_stance_change_at for skip-unchanged optimization
--   7. ALTER scores — add status, non_overlapping_topics for no-overlap handling
--   8. ALTER score_history — add status for historical no-overlap tracking
--
-- Depends on migrations 006-008 (amendment_id, score status/reasoning columns)
-- being applied first via db.changelog-master.yaml ordering.
--
-- Table name constants: repcheck.pipeline.models.db.Tables
-- DO definitions: docs/architecture/acceptance-criteria/01-shared-models/01.5-user-domain-objects.md
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. user_legislator_pairings — Persistent user-to-legislator mapping
--    Created at signup, validated by scheduled PairingValidator (§11.6).
--    Source: BEHAVIORAL_SPECS.md §3.1
-- ---------------------------------------------------------------------------

CREATE TABLE user_legislator_pairings (
    user_id              UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    member_id            TEXT        NOT NULL REFERENCES members(member_id),
    state                TEXT        NOT NULL,     -- two-letter state code at pairing time
    district             INT,                      -- congressional district (NULL for senators)
    chamber              TEXT        NOT NULL,     -- 'House' or 'Senate'
    paired_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    validated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (user_id, member_id)
);

CREATE INDEX idx_pairings_member ON user_legislator_pairings (member_id);
CREATE INDEX idx_pairings_state_district ON user_legislator_pairings (state, district);

-- ---------------------------------------------------------------------------
-- 2. member_bill_stance_topics — Per-topic stance with LLM reasoning
--    Child table of member_bill_stances. Populated by StanceMaterializer (§11.9).
--    Each row: one member's vote on one bill, for one topic.
--    Source: BEHAVIORAL_SPECS.md §3.2
-- ---------------------------------------------------------------------------

CREATE TABLE member_bill_stance_topics (
    id                   UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id            TEXT        NOT NULL,
    bill_id              BIGINT      NOT NULL,
    vote_id              TEXT        NOT NULL,
    topic                TEXT        NOT NULL,
    stance_direction     TEXT        NOT NULL,     -- 'Progressive', 'Conservative', 'Neutral'
    reasoning            TEXT,                     -- LLM-generated explanation of stance
    reasoning_embedding  vector(1536),             -- DJL/ONNX embedding of reasoning
    finding_id           UUID,                     -- FK to bill_findings for provenance
    confidence           FLOAT,                    -- 0.0-1.0, LLM's confidence in stance assessment
    concept_summary      TEXT,                     -- concept summary from analysis
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY (member_id, bill_id, vote_id)
        REFERENCES member_bill_stances(member_id, bill_id, vote_id) ON DELETE CASCADE,
    FOREIGN KEY (finding_id)
        REFERENCES bill_findings(finding_id)
);

CREATE INDEX idx_stance_topics_member ON member_bill_stance_topics (member_id);
CREATE INDEX idx_stance_topics_bill ON member_bill_stance_topics (bill_id);
CREATE INDEX idx_stance_topics_member_topic ON member_bill_stance_topics (member_id, topic);
CREATE INDEX idx_stance_topics_finding ON member_bill_stance_topics (finding_id);

-- HNSW index for semantic search on stance reasoning embeddings
CREATE INDEX idx_stance_topics_reasoning_embedding ON member_bill_stance_topics
    USING hnsw (reasoning_embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- 3. user_bill_alignments — Pre-computed user-bill topic alignment
--    Populated by UserBillAligner (§11.10). Each row: one user's alignment
--    with one bill on one topic.
--    Source: BEHAVIORAL_SPECS.md §3.3
-- ---------------------------------------------------------------------------

CREATE TABLE user_bill_alignments (
    user_id              UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    bill_id              BIGINT      NOT NULL REFERENCES bills(id),
    topic                TEXT        NOT NULL,
    user_stance_score    DOUBLE PRECISION NOT NULL, -- user's stance strength on this topic
    bill_stance_direction TEXT       NOT NULL,       -- bill's stance: 'Progressive', 'Conservative', 'Neutral'
    alignment_score      DOUBLE PRECISION NOT NULL CHECK (alignment_score BETWEEN 0.0 AND 1.0),
    reasoning            TEXT,                       -- LLM-generated alignment explanation
    reasoning_embedding  vector(1536),               -- DJL/ONNX embedding of reasoning
    finding_id           UUID REFERENCES bill_findings(finding_id), -- provenance
    computed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (user_id, bill_id, topic)
);

CREATE INDEX idx_user_bill_align_bill ON user_bill_alignments (bill_id);
CREATE INDEX idx_user_bill_align_user ON user_bill_alignments (user_id);

-- HNSW index for semantic search on alignment reasoning
CREATE INDEX idx_user_bill_align_reasoning_embedding ON user_bill_alignments
    USING hnsw (reasoning_embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- 4. user_amendment_alignments — Pre-computed user-amendment topic alignment
--    Same structure as user_bill_alignments but for amendment votes.
--    finding_id references amendment_findings instead of bill_findings.
--    Source: BEHAVIORAL_SPECS.md §3.3
-- ---------------------------------------------------------------------------

CREATE TABLE user_amendment_alignments (
    user_id              UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    amendment_id         TEXT        NOT NULL REFERENCES amendments(amendment_id),
    bill_id              BIGINT      REFERENCES bills(id), -- parent bill (nullable for standalone amendments)
    topic                TEXT        NOT NULL,
    user_stance_score    DOUBLE PRECISION NOT NULL,
    amendment_stance_direction TEXT  NOT NULL,
    alignment_score      DOUBLE PRECISION NOT NULL CHECK (alignment_score BETWEEN 0.0 AND 1.0),
    reasoning            TEXT,
    reasoning_embedding  vector(1536),
    finding_id           UUID REFERENCES amendment_findings(finding_id),
    computed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (user_id, amendment_id, topic)
);

CREATE INDEX idx_user_amend_align_amendment ON user_amendment_alignments (amendment_id);
CREATE INDEX idx_user_amend_align_user ON user_amendment_alignments (user_id);
CREATE INDEX idx_user_amend_align_bill ON user_amendment_alignments (bill_id);

-- HNSW index for semantic search on amendment alignment reasoning
CREATE INDEX idx_user_amend_align_reasoning_embedding ON user_amendment_alignments
    USING hnsw (reasoning_embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- 5. stance_materialization_status — DB-polling readiness tracker
--    Tracks whether a bill has both votes and completed analysis, enabling
--    the StanceMaterializationScanner (§11.9) to poll for ready bills
--    instead of coordinating dual Pub/Sub events.
--    Source: BEHAVIORAL_SPECS.md §3.2
-- ---------------------------------------------------------------------------

CREATE TABLE stance_materialization_status (
    bill_id              BIGINT      PRIMARY KEY REFERENCES bills(id),
    has_votes            BOOLEAN     NOT NULL DEFAULT FALSE,
    has_analysis         BOOLEAN     NOT NULL DEFAULT FALSE,
    all_passes_completed BOOLEAN     NOT NULL DEFAULT FALSE,
    votes_updated_at     TIMESTAMPTZ,              -- last time votes arrived for this bill
    analysis_completed_at TIMESTAMPTZ,             -- last time analysis completed
    stances_materialized_at TIMESTAMPTZ,           -- last time stance materializer processed this bill
    last_scoring_run_at  TIMESTAMPTZ               -- last time scoring used this bill's stances
);

CREATE INDEX idx_stance_status_ready ON stance_materialization_status
    (has_votes, all_passes_completed)
    WHERE has_votes = TRUE AND all_passes_completed = TRUE;

-- ---------------------------------------------------------------------------
-- 6. ALTER users — Add last_stance_change_at for skip-unchanged optimization
--    Used by scoring pipeline (§11.8) to skip users whose stances haven't
--    changed since the last scoring run.
--    Source: BEHAVIORAL_SPECS.md §3.6
-- ---------------------------------------------------------------------------

ALTER TABLE users ADD COLUMN last_stance_change_at TIMESTAMPTZ;

-- ---------------------------------------------------------------------------
-- 7. ALTER scores — Add status and non_overlapping_topics
--    status: "scored" (has shared topics) or "no_overlap" (zero shared topics)
--    non_overlapping_topics: user topics with no legislator votes (TEXT[])
--    Source: §1.5 ScoreDO, BEHAVIORAL_SPECS.md §3.4
-- ---------------------------------------------------------------------------

ALTER TABLE scores
    ADD COLUMN status TEXT NOT NULL DEFAULT 'scored',
    ADD COLUMN non_overlapping_topics TEXT[] NOT NULL DEFAULT '{}';

ALTER TABLE scores
    ADD CONSTRAINT chk_scores_status CHECK (status IN ('scored', 'no_overlap'));

COMMENT ON COLUMN scores.status IS
    'scored = alignment computed with shared topics; no_overlap = zero shared topics between user and legislator.';

COMMENT ON COLUMN scores.non_overlapping_topics IS
    'User topics that the legislator has no votes on. Used by frontend to suggest additional survey topics.';

-- ---------------------------------------------------------------------------
-- 8. ALTER score_history — Add status
--    Mirrors scores.status for historical records.
-- ---------------------------------------------------------------------------

ALTER TABLE score_history
    ADD COLUMN status TEXT NOT NULL DEFAULT 'scored';

ALTER TABLE score_history
    ADD CONSTRAINT chk_score_history_status CHECK (status IN ('scored', 'no_overlap'));
