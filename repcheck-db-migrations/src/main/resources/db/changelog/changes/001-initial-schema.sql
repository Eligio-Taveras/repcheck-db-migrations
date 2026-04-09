-- =============================================================================
-- RepCheck Database Schema — V1 Initial
-- =============================================================================
-- PostgreSQL 16+ compatible (works with both Cloud SQL and AlloyDB)
-- Requires: CREATE EXTENSION vector  (pgvector for semantic embeddings)
--
-- Table name constants must match: repcheck.pipeline.models.db.Tables
--
-- Congress.gov API fields sourced from: docs/reference/congress-gov-api.yaml
-- RepCheck-internal tables (users, scores, pipelines) from: BEHAVIORAL_SPECS.md
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- ---------------------------------------------------------------------------
-- 0. us_states — State code/name mapping (reference data)
--    Enables joins between users (two-letter code) and members (full name)
-- ---------------------------------------------------------------------------

CREATE TABLE us_states (
    state_code           TEXT        PRIMARY KEY,  -- two-letter code: 'AL', 'AK', ...
    state_name           TEXT        NOT NULL UNIQUE, -- full name: 'Alabama', 'Alaska', ...
    is_territory         BOOLEAN     NOT NULL DEFAULT FALSE  -- DC, PR, GU, AS, VI, MP
);

-- Seed all 50 states + DC + 5 territories
INSERT INTO us_states (state_code, state_name, is_territory) VALUES
    ('AL', 'Alabama', FALSE),
    ('AK', 'Alaska', FALSE),
    ('AZ', 'Arizona', FALSE),
    ('AR', 'Arkansas', FALSE),
    ('CA', 'California', FALSE),
    ('CO', 'Colorado', FALSE),
    ('CT', 'Connecticut', FALSE),
    ('DE', 'Delaware', FALSE),
    ('FL', 'Florida', FALSE),
    ('GA', 'Georgia', FALSE),
    ('HI', 'Hawaii', FALSE),
    ('ID', 'Idaho', FALSE),
    ('IL', 'Illinois', FALSE),
    ('IN', 'Indiana', FALSE),
    ('IA', 'Iowa', FALSE),
    ('KS', 'Kansas', FALSE),
    ('KY', 'Kentucky', FALSE),
    ('LA', 'Louisiana', FALSE),
    ('ME', 'Maine', FALSE),
    ('MD', 'Maryland', FALSE),
    ('MA', 'Massachusetts', FALSE),
    ('MI', 'Michigan', FALSE),
    ('MN', 'Minnesota', FALSE),
    ('MS', 'Mississippi', FALSE),
    ('MO', 'Missouri', FALSE),
    ('MT', 'Montana', FALSE),
    ('NE', 'Nebraska', FALSE),
    ('NV', 'Nevada', FALSE),
    ('NH', 'New Hampshire', FALSE),
    ('NJ', 'New Jersey', FALSE),
    ('NM', 'New Mexico', FALSE),
    ('NY', 'New York', FALSE),
    ('NC', 'North Carolina', FALSE),
    ('ND', 'North Dakota', FALSE),
    ('OH', 'Ohio', FALSE),
    ('OK', 'Oklahoma', FALSE),
    ('OR', 'Oregon', FALSE),
    ('PA', 'Pennsylvania', FALSE),
    ('RI', 'Rhode Island', FALSE),
    ('SC', 'South Carolina', FALSE),
    ('SD', 'South Dakota', FALSE),
    ('TN', 'Tennessee', FALSE),
    ('TX', 'Texas', FALSE),
    ('UT', 'Utah', FALSE),
    ('VT', 'Vermont', FALSE),
    ('VA', 'Virginia', FALSE),
    ('WA', 'Washington', FALSE),
    ('WV', 'West Virginia', FALSE),
    ('WI', 'Wisconsin', FALSE),
    ('WY', 'Wyoming', FALSE),
    ('DC', 'District of Columbia', TRUE),
    ('PR', 'Puerto Rico', TRUE),
    ('GU', 'Guam', TRUE),
    ('AS', 'American Samoa', TRUE),
    ('VI', 'Virgin Islands', TRUE),
    ('MP', 'Northern Mariana Islands', TRUE);

-- ---------------------------------------------------------------------------
-- 1. members — Congress members (bioguideId is the natural key)
--    Source: Congress.gov Member / Members schemas
-- ---------------------------------------------------------------------------

CREATE TABLE members (
    member_id            TEXT        PRIMARY KEY,  -- bioguideId from Congress.gov
    first_name           TEXT        NOT NULL,
    last_name            TEXT        NOT NULL,
    direct_order_name    TEXT,                     -- e.g., "Patrick J. Leahy"
    inverted_order_name  TEXT,                     -- e.g., "Leahy, Patrick J."
    honorific_name       TEXT,                     -- e.g., "Mr.", "Mrs."
    birth_year           TEXT,                     -- string in API (e.g., "1940")
    current_party        TEXT        NOT NULL,     -- current party abbreviation: 'D', 'R', 'I'
    state                TEXT        NOT NULL,     -- full state name from API (e.g., "Vermont")
    district             INT,                      -- NULL for senators
    image_url            TEXT,                     -- depiction.imageUrl
    image_attribution    TEXT,                     -- depiction.attribution
    official_url         TEXT,                     -- link to congress.gov member page
    update_date          TIMESTAMPTZ NOT NULL,     -- from Congress.gov API updateDate
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_members_state ON members (state);
CREATE INDEX idx_members_state_district ON members (state, district);
CREATE INDEX idx_members_current_party ON members (current_party);

-- ---------------------------------------------------------------------------
-- 1a. member_terms — Term history per member (many terms per member)
--     Source: Congress.gov Member.terms[] / memberDetailTerms schema
-- ---------------------------------------------------------------------------

CREATE TABLE member_terms (
    term_id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id            TEXT        NOT NULL REFERENCES members(member_id) ON DELETE CASCADE,
    chamber              TEXT        NOT NULL,     -- "Senate" or "House of Representatives"
    congress             INT,                      -- e.g., 116
    start_year           INT         NOT NULL,
    end_year             INT,                      -- NULL if currently serving
    member_type          TEXT,                     -- e.g., "Senator", "Representative"
    state_code           TEXT,                     -- two-letter code (e.g., "VT")
    state_name           TEXT,                     -- full name (e.g., "Vermont")
    district             INT,                      -- NULL for senators

    CONSTRAINT uq_member_terms UNIQUE (member_id, chamber, start_year)
);

CREATE INDEX idx_member_terms_member ON member_terms (member_id);
CREATE INDEX idx_member_terms_congress ON member_terms (congress);

-- ---------------------------------------------------------------------------
-- 1b. member_party_history — Party affiliation changes over time
--     Source: Congress.gov Member.partyHistory[] schema
-- ---------------------------------------------------------------------------

CREATE TABLE member_party_history (
    party_history_id     UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id            TEXT        NOT NULL REFERENCES members(member_id) ON DELETE CASCADE,
    party_name           TEXT        NOT NULL,     -- e.g., "Democrat"
    party_abbreviation   TEXT        NOT NULL,     -- e.g., "D"
    start_year           INT         NOT NULL,

    CONSTRAINT uq_member_party_history UNIQUE (member_id, start_year)
);

CREATE INDEX idx_member_party_history_member ON member_party_history (member_id);

-- ---------------------------------------------------------------------------
-- 2. bills — Legislation tracked from Congress.gov
--    Source: Congress.gov Bill / BillDetail / LawNumber schemas
--    Existing code: LegislativeBillDO fields
-- ---------------------------------------------------------------------------

CREATE TABLE bills (
    id                         BIGSERIAL   PRIMARY KEY,
    congress                   INT         NOT NULL,
    bill_type                  TEXT        NOT NULL,     -- 'HR', 'S', 'HJRES', 'SJRES', etc.
    number                     INT         NOT NULL,     -- bill number from Congress.gov API
    title                      TEXT        NOT NULL,
    origin_chamber             TEXT,                     -- "House" or "Senate"
    origin_chamber_code        TEXT,                     -- "H" or "S"
    introduced_date            DATE,
    policy_area                TEXT,                     -- policyArea.name (e.g., "Health")
    -- legislative subjects stored in bill_subjects join table
    latest_action_date         DATE,
    latest_action_text         TEXT,
    constitutional_authority_text TEXT,                   -- constitutionalAuthorityStatementText
    sponsor_bioguide_id        TEXT        REFERENCES members(member_id),
    text_url                   TEXT,                     -- URL to bill full text (triggers analysis)
    text_format                TEXT,                     -- 'Formatted Text', 'PDF', 'Formatted XML'
    text_version_type          TEXT,                     -- e.g., "Enrolled Bill", "Introduced in House"
    text_date                  TIMESTAMPTZ,              -- date of the text version
    text_content               TEXT,                     -- full bill text stored locally (avoids refetching)
    text_embedding             vector(1536),             -- embedding of bill text for similarity search
    summary_text               TEXT,                     -- latest summary HTML text
    summary_action_desc        TEXT,                     -- e.g., "Passed Senate"
    summary_action_date        DATE,
    update_date                TIMESTAMPTZ NOT NULL,     -- from Congress.gov API updateDate
    update_date_including_text TIMESTAMPTZ,              -- updateDateIncludingText
    legislation_url            TEXT,                     -- congress.gov human-readable URL
    api_url                    TEXT,                     -- api.congress.gov URL
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_bills_natural_key UNIQUE (congress, bill_type, number)
);

CREATE INDEX idx_bills_congress ON bills (congress);
CREATE INDEX idx_bills_sponsor ON bills (sponsor_bioguide_id);
CREATE INDEX idx_bills_update_date ON bills (update_date);
CREATE INDEX idx_bills_policy_area ON bills (policy_area);
CREATE INDEX idx_bills_introduced_date ON bills (introduced_date);

-- HNSW index on bill text embeddings for user preference → bill similarity search
CREATE INDEX idx_bills_text_embedding ON bills
    USING hnsw (text_embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- 2a. bill_cosponsors — Cosponsors per bill (many-to-many: bills <-> members)
--     Source: Congress.gov CoSponsor schema
-- ---------------------------------------------------------------------------

CREATE TABLE bill_cosponsors (
    bill_id              BIGINT      NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    member_id            TEXT        NOT NULL REFERENCES members(member_id),
    is_original_cosponsor BOOLEAN,
    sponsorship_date     DATE,

    PRIMARY KEY (bill_id, member_id)
);

CREATE INDEX idx_bill_cosponsors_member ON bill_cosponsors (member_id);

-- ---------------------------------------------------------------------------
-- 2b. bill_subjects — Legislative subjects per bill (normalized)
--     Source: Congress.gov Subjects.legislativeSubjects[] schema
-- ---------------------------------------------------------------------------

CREATE TABLE bill_subjects (
    bill_id              BIGINT      NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    subject_name         TEXT        NOT NULL,     -- e.g., "Congressional oversight"
    embedding            vector(1536),             -- for semantic subject search
    update_date          TIMESTAMPTZ,              -- per-subject updateDate from API

    PRIMARY KEY (bill_id, subject_name)
);

CREATE INDEX idx_bill_subjects_name ON bill_subjects (subject_name);

-- HNSW index for subject similarity search
CREATE INDEX idx_bill_subjects_embedding ON bill_subjects
    USING hnsw (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- 3. votes — Roll call votes from Congress.gov
--    Source: Congress.gov HouseVote / HouseVoteNumber schemas
--    Behavioral spec: BEHAVIORAL_SPECS.md §2 Vote Significance
-- ---------------------------------------------------------------------------

CREATE TABLE votes (
    vote_id              TEXT        PRIMARY KEY,  -- natural key: {congress}-{chamber}-{rollNumber}
    congress             INT         NOT NULL,
    chamber              TEXT        NOT NULL,     -- 'House' or 'Senate'
    roll_number          INT         NOT NULL,
    session_number       INT,                      -- congressional session (1 or 2)
    bill_id              BIGINT      REFERENCES bills(id),  -- NULL for procedural votes
    question             TEXT        NOT NULL,     -- raw question text (e.g., "On Passage")
    vote_type            TEXT        NOT NULL,     -- classified: Passage, ConferenceReport, Cloture, VetoOverride, Amendment, Committee, Recommit, Other
    vote_method          TEXT,                     -- from API voteType: "Yea-and-Nay", "Recorded Vote", etc.
    result               TEXT        NOT NULL,     -- 'Passed', 'Failed', 'Agreed to', etc.
    vote_date            TIMESTAMPTZ NOT NULL,     -- startDate from API
    legislation_number   TEXT,                     -- e.g., "30" — bill number from vote context
    legislation_type     TEXT,                     -- e.g., "HR" — bill type from vote context
    legislation_url      TEXT,                     -- congress.gov URL to the legislation
    source_data_url      TEXT,                     -- clerk.house.gov or senate.gov XML source
    update_date          TIMESTAMPTZ NOT NULL,     -- from Congress.gov API updateDate
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_votes_natural_key UNIQUE (congress, chamber, roll_number)
);

CREATE INDEX idx_votes_bill_id ON votes (bill_id);
CREATE INDEX idx_votes_congress ON votes (congress);
CREATE INDEX idx_votes_date ON votes (vote_date);

-- ---------------------------------------------------------------------------
-- 4. vote_positions — Individual member positions on each vote
--    Source: Congress.gov houseVoteResults schema
-- ---------------------------------------------------------------------------

CREATE TABLE vote_positions (
    vote_id              TEXT        NOT NULL REFERENCES votes(vote_id) ON DELETE CASCADE,
    member_id            TEXT        NOT NULL REFERENCES members(member_id),
    position             TEXT        NOT NULL,     -- 'Yea', 'Nay', 'Present', 'Not Voting'
    party_at_vote        TEXT,                     -- party at time of vote (from voteParty)
    state_at_vote        TEXT,                     -- state at time of vote (from voteState)
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (vote_id, member_id)
);

CREATE INDEX idx_vote_positions_member ON vote_positions (member_id);

-- ---------------------------------------------------------------------------
-- 5. vote_history — Archived prior versions of votes (audit trail)
--    Per BEHAVIORAL_SPECS.md: prior version saved before overwrite
-- ---------------------------------------------------------------------------

CREATE TABLE vote_history (
    history_id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    vote_id              TEXT        NOT NULL,     -- references the vote natural key
    congress             INT         NOT NULL,
    chamber              TEXT        NOT NULL,
    roll_number          INT         NOT NULL,
    session_number       INT,
    bill_id              BIGINT,
    question             TEXT        NOT NULL,
    vote_type            TEXT        NOT NULL,
    vote_method          TEXT,
    result               TEXT        NOT NULL,
    vote_date            TIMESTAMPTZ NOT NULL,
    legislation_number   TEXT,
    legislation_type     TEXT,
    legislation_url      TEXT,
    source_data_url      TEXT,
    update_date          TIMESTAMPTZ NOT NULL,
    archived_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_vote_history_vote_id ON vote_history (vote_id);
CREATE INDEX idx_vote_history_archived_at ON vote_history (archived_at);

-- ---------------------------------------------------------------------------
-- 5a. vote_history_positions — Archived member positions (structured)
--     Mirrors vote_positions but linked to vote_history
-- ---------------------------------------------------------------------------

CREATE TABLE vote_history_positions (
    history_id           UUID        NOT NULL REFERENCES vote_history(history_id) ON DELETE CASCADE,
    member_id            TEXT        NOT NULL,     -- no FK to members — member may change over time
    position             TEXT        NOT NULL,
    party_at_vote        TEXT,
    state_at_vote        TEXT,

    PRIMARY KEY (history_id, member_id)
);

-- ---------------------------------------------------------------------------
-- 6. amendments — Bill amendments from Congress.gov
--    Source: Congress.gov Amendment / AmendmentNumber schemas
-- ---------------------------------------------------------------------------

CREATE TABLE amendments (
    amendment_id         TEXT        PRIMARY KEY,  -- natural key: {congress}-{amendmentType}-{number}
    congress             INT         NOT NULL,
    amendment_type       TEXT        NOT NULL,     -- 'HAMDT', 'SAMDT', etc.
    number               INT         NOT NULL,
    bill_id              BIGINT      REFERENCES bills(id),  -- amendedBill linkage
    chamber              TEXT,                     -- from AmendmentNumber.chamber
    description          TEXT,                     -- amendment description
    purpose              TEXT,                     -- e.g., "In the nature of a substitute."
    sponsor_bioguide_id  TEXT        REFERENCES members(member_id),
    submitted_date       TIMESTAMPTZ,              -- submittedDate
    latest_action_date   DATE,
    latest_action_text   TEXT,
    update_date          TIMESTAMPTZ NOT NULL,     -- from Congress.gov API updateDate
    api_url              TEXT,                     -- api.congress.gov URL
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_amendments_natural_key UNIQUE (congress, amendment_type, number)
);

CREATE INDEX idx_amendments_bill_id ON amendments (bill_id);
CREATE INDEX idx_amendments_congress ON amendments (congress);
CREATE INDEX idx_amendments_sponsor ON amendments (sponsor_bioguide_id);

-- ---------------------------------------------------------------------------
-- 7. finding_types — Lookup table for finding categories (bills + amendments)
--    Extensible: add new types via INSERT without schema changes
--    Must be created before amendment_findings and bill_findings which reference it
-- ---------------------------------------------------------------------------

CREATE TABLE finding_types (
    finding_type_id      TEXT        PRIMARY KEY,  -- e.g., 'pork', 'topic_extraction', etc.
    display_name         TEXT        NOT NULL,     -- human-readable name
    description          TEXT                      -- what this finding type represents
);

-- Seed finding types: analysis pass outputs + discovery categories
INSERT INTO finding_types (finding_type_id, display_name, description) VALUES
    -- Analysis pass outputs (produced by the multi-pass LLM pipeline)
    ('topic_extraction', 'Topic Extraction', 'Topics and categories identified in the bill (Pass 1 — Haiku)'),
    ('bill_summary', 'Bill Summary', 'Concise summary of the bill content and intent (Pass 1 — Haiku)'),
    ('policy_analysis', 'Policy Analysis', 'Deeper analysis of policy implications and impact (Pass 2 — Sonnet)'),
    ('stance_detection', 'Stance Detection', 'Nuanced detection of political stances and positions (Pass 3 — Opus)'),
    -- Discovery categories (produced by targeted analysis)
    ('pork', 'Pork Barrel Spending', 'Earmarks, directed spending, or provisions that benefit a specific district or interest group'),
    ('rider', 'Policy Rider', 'Unrelated provisions attached to a larger bill to ensure passage'),
    ('lobbying', 'Lobbying Influence', 'Provisions that appear to benefit specific lobbying interests'),
    ('constitutional', 'Constitutional Concern', 'Provisions that raise constitutional questions or challenges');

-- ---------------------------------------------------------------------------
-- 6a. amendment_findings — LLM-discovered findings per amendment (searchable)
--     Same pattern as bill_findings: raw text + vector, FK to finding_types
-- ---------------------------------------------------------------------------

CREATE TABLE amendment_findings (
    finding_id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    amendment_id         TEXT        NOT NULL REFERENCES amendments(amendment_id),
    finding_type_id      TEXT        NOT NULL REFERENCES finding_types(finding_type_id),
    summary              TEXT        NOT NULL,     -- LLM-generated short summary
    details              TEXT,                     -- full raw analysis text
    embedding            vector(1536),             -- for similarity search within this finding type
    llm_model            TEXT        NOT NULL,     -- model that generated this finding
    analyzed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_amendment_findings_amendment ON amendment_findings (amendment_id);
CREATE INDEX idx_amendment_findings_type ON amendment_findings (finding_type_id);

-- HNSW index for amendment finding similarity search
CREATE INDEX idx_amendment_findings_embedding ON amendment_findings
    USING hnsw (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- 7a. bill_analyses — LLM analysis run tracking (append-only, multi-pass)
--     Source: BEHAVIORAL_SPECS.md §1 and §2
--     Pass 1 produces a shortened summary; Pass 2/3 operate on that summary
--     Actual findings from each pass stored in bill_findings
-- ---------------------------------------------------------------------------

CREATE TABLE bill_analyses (
    analysis_id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id              BIGINT      NOT NULL REFERENCES bills(id),
    pass_completed       INT         NOT NULL DEFAULT 1,  -- highest pass completed (1, 2, or 3)
    llm_model            TEXT        NOT NULL,     -- model used for final pass
    summary              TEXT,                     -- shortened summary from Pass 1, input to Pass 2/3
    topics               TEXT[]      NOT NULL DEFAULT '{}', -- extracted topic tags for event payload
    embedding            vector(1536),             -- overall analysis embedding
    analyzed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bill_analyses_bill_id ON bill_analyses (bill_id);
CREATE INDEX idx_bill_analyses_analyzed_at ON bill_analyses (analyzed_at);

-- HNSW index for cosine similarity search
CREATE INDEX idx_bill_analyses_embedding ON bill_analyses
    USING hnsw (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- 7b. bill_findings — LLM-discovered findings per bill (searchable)
--     Each finding has raw text for display and a vector for similarity search
--     Links to both the bill and the analysis run that produced it
-- ---------------------------------------------------------------------------

CREATE TABLE bill_findings (
    finding_id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id              BIGINT      NOT NULL REFERENCES bills(id),
    analysis_id          UUID        REFERENCES bill_analyses(analysis_id),  -- which analysis run produced this
    finding_type_id      TEXT        NOT NULL REFERENCES finding_types(finding_type_id),
    summary              TEXT        NOT NULL,     -- LLM-generated short summary
    details              TEXT,                     -- full raw analysis text
    embedding            vector(1536),             -- for similarity search within this finding type
    llm_model            TEXT        NOT NULL,     -- model that generated this finding
    analyzed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bill_findings_bill ON bill_findings (bill_id);
CREATE INDEX idx_bill_findings_analysis ON bill_findings (analysis_id);
CREATE INDEX idx_bill_findings_type ON bill_findings (finding_type_id);

-- HNSW index for finding similarity search (e.g., "find bills with similar pork")
CREATE INDEX idx_bill_findings_embedding ON bill_findings
    USING hnsw (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- 8. users — RepCheck platform users
-- ---------------------------------------------------------------------------

CREATE TABLE users (
    user_id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    display_name         TEXT        NOT NULL,
    email                TEXT        NOT NULL UNIQUE,
    state                TEXT        NOT NULL,     -- two-letter state code for representative lookup
    district             INT,                      -- congressional district (NULL if not provided)
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_state_district ON users (state, district);

-- ---------------------------------------------------------------------------
-- 9. user_preferences — Political topic preferences (Q&A responses)
--    Source: BEHAVIORAL_SPECS.md §3
-- ---------------------------------------------------------------------------

CREATE TABLE user_preferences (
    preference_id        UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id              UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    topic                TEXT        NOT NULL,     -- e.g., 'healthcare', 'environment', 'defense'
    stance               TEXT        NOT NULL,     -- 'support', 'oppose', 'neutral'
    importance           INT         NOT NULL CHECK (importance BETWEEN 1 AND 10),
    embedding            vector(1536),             -- per-topic preference embedding for bill similarity search
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_user_preferences_user_topic UNIQUE (user_id, topic)
);

CREATE INDEX idx_user_preferences_user_id ON user_preferences (user_id);

-- HNSW index for per-topic preference → bill similarity search
-- e.g., "find bills matching this user's healthcare stance"
CREATE INDEX idx_user_preferences_embedding ON user_preferences
    USING hnsw (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- 9a. member_bill_stances — Denormalized: how each member voted on each bill
--     Materialized from vote_positions → votes → bills join path
--     Rebuilt when votes or analyses change; enables fast alignment queries
-- ---------------------------------------------------------------------------

CREATE TABLE member_bill_stances (
    member_id            TEXT        NOT NULL REFERENCES members(member_id),
    bill_id              BIGINT      NOT NULL REFERENCES bills(id),
    vote_id              TEXT        NOT NULL REFERENCES votes(vote_id),
    position             TEXT        NOT NULL,     -- 'Yea', 'Nay', 'Present', 'Not Voting'
    vote_type            TEXT        NOT NULL,     -- Passage, Cloture, Amendment, etc.
    vote_date            TIMESTAMPTZ NOT NULL,
    congress             INT         NOT NULL,
    topics               TEXT[]      NOT NULL DEFAULT '{}',  -- from bill_analyses.topics

    PRIMARY KEY (member_id, bill_id, vote_id)
);

CREATE INDEX idx_member_bill_stances_bill ON member_bill_stances (bill_id);
CREATE INDEX idx_member_bill_stances_member_congress ON member_bill_stances (member_id, congress);

-- ---------------------------------------------------------------------------
-- 10. scores — Latest alignment score per user/legislator pair (fast reads)
--     Source: BEHAVIORAL_SPECS.md §3
--     scoring_context flattened to columns; topic and congress scores normalized
-- ---------------------------------------------------------------------------

CREATE TABLE scores (
    user_id              UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    member_id            TEXT        NOT NULL REFERENCES members(member_id),
    aggregate_score      FLOAT       NOT NULL,     -- 0.0–1.0 (lifetime, all congresses)
    last_updated         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    llm_model            TEXT        NOT NULL,     -- model used for scoring
    total_bills          INT         NOT NULL,     -- total bills considered
    total_votes          INT         NOT NULL,     -- total votes considered

    PRIMARY KEY (user_id, member_id)
);

CREATE INDEX idx_scores_member ON scores (member_id);

-- ---------------------------------------------------------------------------
-- 10a. score_topics — Per-topic aggregate scores (replaces aggregate_topic_scores JSONB)
-- ---------------------------------------------------------------------------

CREATE TABLE score_topics (
    user_id              UUID        NOT NULL,
    member_id            TEXT        NOT NULL,
    topic                TEXT        NOT NULL,
    score                FLOAT       NOT NULL,     -- 0.0–1.0

    PRIMARY KEY (user_id, member_id, topic),
    FOREIGN KEY (user_id, member_id) REFERENCES scores(user_id, member_id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- 10b. score_congress — Per-congress overall scores (replaces congress_scores JSONB)
-- ---------------------------------------------------------------------------

CREATE TABLE score_congress (
    user_id              UUID        NOT NULL,
    member_id            TEXT        NOT NULL,
    congress             INT         NOT NULL,
    overall_score        FLOAT       NOT NULL,     -- 0.0–1.0
    bills_considered     INT         NOT NULL,
    votes_analyzed       INT         NOT NULL,

    PRIMARY KEY (user_id, member_id, congress),
    FOREIGN KEY (user_id, member_id) REFERENCES scores(user_id, member_id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- 10c. score_congress_topics — Per-congress per-topic scores
-- ---------------------------------------------------------------------------

CREATE TABLE score_congress_topics (
    user_id              UUID        NOT NULL,
    member_id            TEXT        NOT NULL,
    congress             INT         NOT NULL,
    topic                TEXT        NOT NULL,
    score                FLOAT       NOT NULL,     -- 0.0–1.0

    PRIMARY KEY (user_id, member_id, congress, topic),
    FOREIGN KEY (user_id, member_id, congress) REFERENCES score_congress(user_id, member_id, congress) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- 11. score_history — Append-only audit trail for trend charts
--     Source: BEHAVIORAL_SPECS.md §3
-- ---------------------------------------------------------------------------

CREATE TABLE score_history (
    score_id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id              UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    member_id            TEXT        NOT NULL REFERENCES members(member_id),
    computed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    aggregate_score      FLOAT       NOT NULL,
    trigger_event        TEXT        NOT NULL      -- e.g., 'vote.recorded', 'analysis.completed', 'user.profile.updated'
);

CREATE INDEX idx_score_history_user_member ON score_history (user_id, member_id);
CREATE INDEX idx_score_history_computed_at ON score_history (computed_at);

-- ---------------------------------------------------------------------------
-- 11a. score_history_congress — Per-congress scores at point in time
-- ---------------------------------------------------------------------------

CREATE TABLE score_history_congress (
    score_id             UUID        NOT NULL REFERENCES score_history(score_id) ON DELETE CASCADE,
    congress             INT         NOT NULL,
    overall_score        FLOAT       NOT NULL,
    bills_considered     INT         NOT NULL,
    votes_analyzed       INT         NOT NULL,

    PRIMARY KEY (score_id, congress)
);

-- ---------------------------------------------------------------------------
-- 11b. score_history_congress_topics — Per-congress per-topic scores at point in time
-- ---------------------------------------------------------------------------

CREATE TABLE score_history_congress_topics (
    score_id             UUID        NOT NULL,
    congress             INT         NOT NULL,
    topic                TEXT        NOT NULL,
    score                FLOAT       NOT NULL,

    PRIMARY KEY (score_id, congress, topic),
    FOREIGN KEY (score_id, congress) REFERENCES score_history_congress(score_id, congress) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- 11c. score_history_highlights — Notable bill alignments at point in time
-- ---------------------------------------------------------------------------

CREATE TABLE score_history_highlights (
    score_id             UUID        NOT NULL REFERENCES score_history(score_id) ON DELETE CASCADE,
    bill_id              BIGINT      NOT NULL,
    topic                TEXT        NOT NULL,
    stance               TEXT        NOT NULL,     -- user's stance on the topic
    vote                 TEXT        NOT NULL,     -- legislator's vote: 'Yea', 'Nay', etc.
    alignment            FLOAT       NOT NULL,     -- 0.0–1.0

    PRIMARY KEY (score_id, bill_id, topic)
);

-- ---------------------------------------------------------------------------
-- 12. pipeline_runs — Tracks each pipeline execution
--     Source: BEHAVIORAL_SPECS.md §5 Workflow Execution Rules
-- ---------------------------------------------------------------------------

CREATE TABLE pipeline_runs (
    run_id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    pipeline_name        TEXT        NOT NULL,     -- e.g., 'bills-pipeline', 'scoring-pipeline'
    status               TEXT        NOT NULL DEFAULT 'running',  -- 'running', 'completed', 'completed_with_errors', 'failed'
    started_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at         TIMESTAMPTZ,
    items_processed      INT         NOT NULL DEFAULT 0,
    items_succeeded      INT         NOT NULL DEFAULT 0,
    items_failed         INT         NOT NULL DEFAULT 0,
    error_summary        JSONB,                    -- aggregated error info if any
    snapshot_path        TEXT,                      -- GCS path to the snapshot used for this run
    trigger              TEXT        NOT NULL DEFAULT 'scheduled',  -- 'scheduled', 'manual', 'event'
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_pipeline_runs_name ON pipeline_runs (pipeline_name);
CREATE INDEX idx_pipeline_runs_started ON pipeline_runs (started_at);

-- ---------------------------------------------------------------------------
-- 13. processing_results — Per-item outcome within a pipeline run
--     Source: BEHAVIORAL_SPECS.md §5 — ProcessingResult per item
-- ---------------------------------------------------------------------------

CREATE TABLE processing_results (
    result_id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    run_id               UUID        NOT NULL REFERENCES pipeline_runs(run_id) ON DELETE CASCADE,
    correlation_id       UUID        NOT NULL,     -- per-item UUID visible in all logs
    entity_type          TEXT        NOT NULL,     -- 'bill', 'vote', 'member', 'amendment', 'analysis', 'score'
    entity_id            TEXT        NOT NULL,     -- natural key of the entity processed
    status               TEXT        NOT NULL,     -- 'success', 'failed', 'skipped'
    error_message        TEXT,
    error_class          TEXT,                     -- 'Transient' or 'Systemic'
    processed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_processing_results_run ON processing_results (run_id);
CREATE INDEX idx_processing_results_entity ON processing_results (entity_type, entity_id);
CREATE INDEX idx_processing_results_correlation ON processing_results (correlation_id);
