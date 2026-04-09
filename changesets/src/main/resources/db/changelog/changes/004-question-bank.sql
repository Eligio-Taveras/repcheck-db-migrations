-- =============================================================================
-- RepCheck Database Schema — V4 Question Bank for User Stance Collection
-- =============================================================================
-- Adds pre-tagged question bank tables for determining user political stances.
-- Questions are pre-curated with topic mappings and answer metadata so that
-- stance extraction from multiple-choice answers is deterministic (no LLM).
-- Custom fill-in answers still require LLM interpretation.
--
-- New tables:
--   - qa_questions: the question bank (~50-100 pre-curated questions)
--   - qa_question_topics: topic mappings per question (what "agree" means)
--   - qa_answer_options: multiple choice options with stance/importance metadata
--   - qa_user_responses: user answers (selected option or custom text)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. qa_questions — Pre-curated political stance questions
--    Each question probes one or more political topics.
--    Questions are LLM-assisted but human-reviewed before deployment.
-- ---------------------------------------------------------------------------

CREATE TABLE qa_questions (
    question_id          TEXT        PRIMARY KEY,  -- e.g., "q-healthcare-medicare-expansion"
    question_text        TEXT        NOT NULL,     -- "Should the federal government expand Medicare?"
    category             TEXT        NOT NULL,     -- broad category: "healthcare", "environment", etc.
    display_order        INT         NOT NULL,     -- ordering for onboarding flow
    allow_custom         BOOLEAN     NOT NULL DEFAULT true,  -- allow free-text override
    active               BOOLEAN     NOT NULL DEFAULT true,  -- soft delete for retired questions
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_qa_questions_category ON qa_questions (category);
CREATE INDEX idx_qa_questions_active ON qa_questions (active) WHERE active = true;

-- ---------------------------------------------------------------------------
-- 2. qa_question_topics — Topic mappings per question
--    Defines what "agree" means for each topic this question probes.
--    A question can probe multiple topics with different weights.
--    Example: "Expand Medicare?" → healthcare (weight 1.0), federal-spending (weight 0.6)
-- ---------------------------------------------------------------------------

CREATE TABLE qa_question_topics (
    question_id          TEXT        NOT NULL REFERENCES qa_questions(question_id) ON DELETE CASCADE,
    topic                TEXT        NOT NULL,
    agree_stance         TEXT        NOT NULL,     -- 'Progressive' or 'Conservative' — what "agree" means
    weight               FLOAT       NOT NULL CHECK (weight > 0.0 AND weight <= 1.0),

    PRIMARY KEY (question_id, topic)
);

-- ---------------------------------------------------------------------------
-- 3. qa_answer_options — Multiple choice options per question
--    Each option carries metadata for algorithmic stance extraction.
--    stance_multiplier: -1.0 (strongly disagree) to 1.0 (strongly agree)
--    importance_signal: 1-10, how much this answer implies the topic matters
-- ---------------------------------------------------------------------------

CREATE TABLE qa_answer_options (
    question_id          TEXT        NOT NULL REFERENCES qa_questions(question_id) ON DELETE CASCADE,
    option_value         TEXT        NOT NULL,     -- 'strongly_agree', 'agree', 'neutral', etc.
    display_text         TEXT        NOT NULL,     -- "Strongly Agree"
    stance_multiplier    FLOAT       NOT NULL CHECK (stance_multiplier >= -1.0 AND stance_multiplier <= 1.0),
    importance_signal    INT         NOT NULL CHECK (importance_signal BETWEEN 1 AND 10),
    display_order        INT         NOT NULL,

    PRIMARY KEY (question_id, option_value)
);

-- ---------------------------------------------------------------------------
-- 4. qa_user_responses — User answers to questions
--    selected_option is set for multiple-choice answers (algorithmic extraction).
--    custom_text is set for free-text answers (requires LLM interpretation).
--    Exactly one of selected_option or custom_text should be non-NULL.
-- ---------------------------------------------------------------------------

CREATE TABLE qa_user_responses (
    response_id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id              UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    question_id          TEXT        NOT NULL REFERENCES qa_questions(question_id),
    selected_option      TEXT,                     -- FK-like to qa_answer_options.option_value (NULL if custom)
    custom_text          TEXT,                     -- free-text answer (NULL if multiple choice)
    responded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_user_question UNIQUE (user_id, question_id),
    CONSTRAINT chk_answer_type CHECK (
        (selected_option IS NOT NULL AND custom_text IS NULL) OR
        (selected_option IS NULL AND custom_text IS NOT NULL)
    )
);

CREATE INDEX idx_qa_responses_user ON qa_user_responses (user_id);
CREATE INDEX idx_qa_responses_question ON qa_user_responses (question_id);
