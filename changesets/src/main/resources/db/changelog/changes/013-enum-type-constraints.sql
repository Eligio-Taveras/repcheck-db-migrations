-- =============================================================================
-- RepCheck Database Schema — V13 Enum Type Constraints
-- =============================================================================
-- Converts all TEXT columns with finite known value sets to PostgreSQL ENUM
-- types, replacing loose TEXT with strict type-checked enumerations.
--
-- Enum values match exactly what the Scala Doobie Put instances write to the
-- database (as defined in repcheck-shared-models DO/enum files).
--
-- Ordering: CREATE TYPE → DROP CHECK → ALTER COLUMN TYPE → Re-apply DEFAULTs
--
-- NOTE: State columns (members.state, member_terms.state_code/state_name,
-- vote_positions.state_at_vote, etc.) are intentionally left as TEXT.
-- The UsState Doobie Put writes .fullName (e.g., "California") while some
-- columns (state_code) expect two-letter codes. This mismatch must be
-- resolved in the Scala layer before adding DB constraints.
--
-- Depends on: 001–012 applied in order.
-- =============================================================================

-- ===========================================================================
-- PHASE 1: CREATE ENUM TYPES
-- ===========================================================================

-- Legislative domain enums (values from Scala enum .apiValue / .toString)

CREATE TYPE chamber_type AS ENUM ('House', 'Senate', 'Joint');

CREATE TYPE party_type AS ENUM ('Democrat', 'Republican', 'Independent');

CREATE TYPE party_abbreviation_type AS ENUM ('D', 'R', 'I');

CREATE TYPE bill_type_enum AS ENUM (
    'hr', 's', 'hjres', 'sjres', 'hconres', 'sconres',
    'hres', 'sres', 'pl', 'stat', 'usc', 'srpt', 'hrpt'
);

CREATE TYPE vote_method_type AS ENUM (
    'recorded vote', 'voice vote', 'unanimous consent', 'roll'
);

CREATE TYPE vote_cast_type AS ENUM (
    'Yea', 'Nay', 'Present', 'Not Voting', 'Absent'
);

CREATE TYPE vote_type_enum AS ENUM (
    'Passage', 'Conference Report', 'Cloture', 'Veto Override',
    'Amendment', 'Committee', 'Recommit', 'Other'
);

CREATE TYPE member_type_enum AS ENUM (
    'Representative', 'Senator', 'Delegate', 'Resident Commissioner'
);

CREATE TYPE text_version_code_type AS ENUM (
    'IH', 'IS', 'RH', 'RS', 'RFS', 'RFH', 'EH', 'ES', 'ENR', 'CPH', 'CPS'
);

CREATE TYPE format_type_enum AS ENUM ('Formatted Text', 'PDF', 'Formatted XML');

CREATE TYPE amendment_type_enum AS ENUM ('hamdt', 'samdt', 'suamdt');

CREATE TYPE committee_type_enum AS ENUM (
    'Standing', 'Special', 'Select', 'Joint', 'Subcommittee'
);

CREATE TYPE committee_position_type AS ENUM (
    'Chairman', 'Ranking Member', 'Vice Chairman', 'Member'
);

CREATE TYPE origin_chamber_code_type AS ENUM ('H', 'S');

-- Analysis / scoring domain enums

CREATE TYPE severity_type AS ENUM ('High', 'Medium', 'Low');

CREATE TYPE stance_direction_type AS ENUM (
    'Progressive', 'Conservative', 'Neutral', 'Bipartisan'
);

CREATE TYPE analysis_status_type AS ENUM ('in_progress', 'completed', 'failed');

CREATE TYPE score_status_type AS ENUM ('scored', 'no_overlap');

CREATE TYPE user_stance_type AS ENUM ('support', 'oppose', 'neutral');

-- Pipeline / operational domain enums

CREATE TYPE pipeline_status_type AS ENUM (
    'running', 'completed', 'completed_with_errors', 'failed'
);

CREATE TYPE processing_status_type AS ENUM ('success', 'failed', 'skipped');

CREATE TYPE processing_entity_type AS ENUM (
    'bill', 'vote', 'member', 'amendment', 'analysis', 'score'
);

CREATE TYPE error_class_type AS ENUM ('Transient', 'Systemic');

CREATE TYPE workflow_status_type AS ENUM (
    'pending', 'running', 'completed', 'failed'
);

CREATE TYPE trigger_type AS ENUM ('scheduled', 'manual', 'event');


-- ===========================================================================
-- PHASE 2: DROP EXISTING CHECK CONSTRAINTS
-- These CHECK constraints are superseded by the ENUM type constraints.
-- ===========================================================================

ALTER TABLE amendment_analyses DROP CONSTRAINT IF EXISTS chk_amendment_analysis_status;
ALTER TABLE scores            DROP CONSTRAINT IF EXISTS chk_scores_status;
ALTER TABLE score_history      DROP CONSTRAINT IF EXISTS chk_score_history_status;


-- ===========================================================================
-- PHASE 3: ALTER COLUMN TYPES
-- Grouped by table. USING clauses handle case normalization and value mapping
-- for existing data that may differ from current Scala enum values.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- members
-- ---------------------------------------------------------------------------
ALTER TABLE members
    ALTER COLUMN current_party TYPE party_type USING current_party::party_type;

-- ---------------------------------------------------------------------------
-- member_terms
-- ---------------------------------------------------------------------------
ALTER TABLE member_terms
    ALTER COLUMN chamber TYPE chamber_type USING chamber::chamber_type;

ALTER TABLE member_terms
    ALTER COLUMN member_type TYPE member_type_enum USING member_type::member_type_enum;

-- ---------------------------------------------------------------------------
-- member_party_history
-- ---------------------------------------------------------------------------
ALTER TABLE member_party_history
    ALTER COLUMN party_name TYPE party_type USING party_name::party_type;

ALTER TABLE member_party_history
    ALTER COLUMN party_abbreviation TYPE party_abbreviation_type
    USING party_abbreviation::party_abbreviation_type;

-- ---------------------------------------------------------------------------
-- member_history
-- ---------------------------------------------------------------------------
ALTER TABLE member_history
    ALTER COLUMN current_party TYPE party_type USING current_party::party_type;

-- ---------------------------------------------------------------------------
-- member_term_history
-- ---------------------------------------------------------------------------
ALTER TABLE member_term_history
    ALTER COLUMN chamber TYPE chamber_type USING chamber::chamber_type;

ALTER TABLE member_term_history
    ALTER COLUMN member_type TYPE member_type_enum USING member_type::member_type_enum;

-- ---------------------------------------------------------------------------
-- bills
-- Existing data may have uppercase bill_type values (e.g., 'HR'); normalize
-- to lowercase to match Scala BillType.apiValue.
-- ---------------------------------------------------------------------------
ALTER TABLE bills
    ALTER COLUMN bill_type TYPE bill_type_enum USING LOWER(bill_type)::bill_type_enum;

ALTER TABLE bills
    ALTER COLUMN origin_chamber TYPE chamber_type USING origin_chamber::chamber_type;

ALTER TABLE bills
    ALTER COLUMN origin_chamber_code TYPE origin_chamber_code_type
    USING origin_chamber_code::origin_chamber_code_type;

ALTER TABLE bills
    ALTER COLUMN text_format TYPE format_type_enum USING text_format::format_type_enum;

ALTER TABLE bills
    ALTER COLUMN text_version_type TYPE text_version_code_type
    USING text_version_type::text_version_code_type;

-- ---------------------------------------------------------------------------
-- bill_text_versions
-- ---------------------------------------------------------------------------
ALTER TABLE bill_text_versions
    ALTER COLUMN version_code TYPE text_version_code_type
    USING version_code::text_version_code_type;

ALTER TABLE bill_text_versions
    ALTER COLUMN format_type TYPE format_type_enum USING format_type::format_type_enum;

-- ---------------------------------------------------------------------------
-- bill_history
-- ---------------------------------------------------------------------------
ALTER TABLE bill_history
    ALTER COLUMN bill_type TYPE bill_type_enum USING LOWER(bill_type)::bill_type_enum;

ALTER TABLE bill_history
    ALTER COLUMN origin_chamber TYPE chamber_type USING origin_chamber::chamber_type;

ALTER TABLE bill_history
    ALTER COLUMN origin_chamber_code TYPE origin_chamber_code_type
    USING origin_chamber_code::origin_chamber_code_type;

ALTER TABLE bill_history
    ALTER COLUMN text_format TYPE format_type_enum USING text_format::format_type_enum;

ALTER TABLE bill_history
    ALTER COLUMN text_version_type TYPE text_version_code_type
    USING text_version_type::text_version_code_type;

-- ---------------------------------------------------------------------------
-- votes
-- ---------------------------------------------------------------------------
ALTER TABLE votes
    ALTER COLUMN chamber TYPE chamber_type USING chamber::chamber_type;

ALTER TABLE votes
    ALTER COLUMN vote_type TYPE vote_type_enum USING vote_type::vote_type_enum;

ALTER TABLE votes
    ALTER COLUMN vote_method TYPE vote_method_type USING vote_method::vote_method_type;

ALTER TABLE votes
    ALTER COLUMN legislation_type TYPE bill_type_enum
    USING LOWER(legislation_type)::bill_type_enum;

-- ---------------------------------------------------------------------------
-- vote_positions
-- ---------------------------------------------------------------------------
ALTER TABLE vote_positions
    ALTER COLUMN position TYPE vote_cast_type USING position::vote_cast_type;

ALTER TABLE vote_positions
    ALTER COLUMN party_at_vote TYPE party_type USING party_at_vote::party_type;

-- ---------------------------------------------------------------------------
-- vote_history
-- ---------------------------------------------------------------------------
ALTER TABLE vote_history
    ALTER COLUMN chamber TYPE chamber_type USING chamber::chamber_type;

ALTER TABLE vote_history
    ALTER COLUMN vote_type TYPE vote_type_enum USING vote_type::vote_type_enum;

ALTER TABLE vote_history
    ALTER COLUMN vote_method TYPE vote_method_type USING vote_method::vote_method_type;

ALTER TABLE vote_history
    ALTER COLUMN legislation_type TYPE bill_type_enum
    USING LOWER(legislation_type)::bill_type_enum;

-- ---------------------------------------------------------------------------
-- vote_history_positions
-- ---------------------------------------------------------------------------
ALTER TABLE vote_history_positions
    ALTER COLUMN position TYPE vote_cast_type USING position::vote_cast_type;

ALTER TABLE vote_history_positions
    ALTER COLUMN party_at_vote TYPE party_type USING party_at_vote::party_type;

-- ---------------------------------------------------------------------------
-- amendments
-- Existing data may have uppercase amendment_type (e.g., 'HAMDT'); normalize
-- to lowercase to match Scala AmendmentType.apiValue.
-- ---------------------------------------------------------------------------
ALTER TABLE amendments
    ALTER COLUMN amendment_type TYPE amendment_type_enum
    USING LOWER(amendment_type)::amendment_type_enum;

ALTER TABLE amendments
    ALTER COLUMN chamber TYPE chamber_type USING chamber::chamber_type;

ALTER TABLE amendments
    ALTER COLUMN text_format TYPE format_type_enum USING text_format::format_type_enum;

ALTER TABLE amendments
    ALTER COLUMN text_version_type TYPE text_version_code_type
    USING text_version_type::text_version_code_type;

-- ---------------------------------------------------------------------------
-- amendment_text_versions
-- ---------------------------------------------------------------------------
ALTER TABLE amendment_text_versions
    ALTER COLUMN format_type TYPE format_type_enum USING format_type::format_type_enum;

-- ---------------------------------------------------------------------------
-- committees
-- ---------------------------------------------------------------------------
ALTER TABLE committees
    ALTER COLUMN chamber TYPE chamber_type USING chamber::chamber_type;

ALTER TABLE committees
    ALTER COLUMN committee_type TYPE committee_type_enum
    USING committee_type::committee_type_enum;

-- ---------------------------------------------------------------------------
-- committee_members
-- Existing data may use 'Chair' instead of 'Chairman', 'Vice Chair' instead
-- of 'Vice Chairman'. Map to canonical Scala CommitteePosition.apiValue.
-- ---------------------------------------------------------------------------
ALTER TABLE committee_members
    ALTER COLUMN role TYPE committee_position_type
    USING (CASE
        WHEN role = 'Chair' THEN 'Chairman'
        WHEN role = 'Vice Chair' THEN 'Vice Chairman'
        ELSE role
    END)::committee_position_type;

-- ---------------------------------------------------------------------------
-- bill_analyses
-- ---------------------------------------------------------------------------
ALTER TABLE bill_analyses ALTER COLUMN status DROP DEFAULT;
ALTER TABLE bill_analyses
    ALTER COLUMN status TYPE analysis_status_type USING status::analysis_status_type;
ALTER TABLE bill_analyses
    ALTER COLUMN status SET DEFAULT 'completed'::analysis_status_type;

-- ---------------------------------------------------------------------------
-- amendment_analyses
-- ---------------------------------------------------------------------------
ALTER TABLE amendment_analyses ALTER COLUMN status DROP DEFAULT;
ALTER TABLE amendment_analyses
    ALTER COLUMN status TYPE analysis_status_type USING status::analysis_status_type;
ALTER TABLE amendment_analyses
    ALTER COLUMN status SET DEFAULT 'in_progress'::analysis_status_type;

ALTER TABLE amendment_analyses
    ALTER COLUMN stance_direction TYPE stance_direction_type
    USING stance_direction::stance_direction_type;

-- ---------------------------------------------------------------------------
-- bill_findings
-- ---------------------------------------------------------------------------
ALTER TABLE bill_findings
    ALTER COLUMN severity TYPE severity_type USING severity::severity_type;

-- ---------------------------------------------------------------------------
-- amendment_findings
-- ---------------------------------------------------------------------------
ALTER TABLE amendment_findings
    ALTER COLUMN severity TYPE severity_type USING severity::severity_type;

-- ---------------------------------------------------------------------------
-- member_bill_stances
-- ---------------------------------------------------------------------------
ALTER TABLE member_bill_stances
    ALTER COLUMN position TYPE vote_cast_type USING position::vote_cast_type;

ALTER TABLE member_bill_stances
    ALTER COLUMN vote_type TYPE vote_type_enum USING vote_type::vote_type_enum;

-- ---------------------------------------------------------------------------
-- member_bill_stance_topics
-- ---------------------------------------------------------------------------
ALTER TABLE member_bill_stance_topics
    ALTER COLUMN stance_direction TYPE stance_direction_type
    USING stance_direction::stance_direction_type;

-- ---------------------------------------------------------------------------
-- user_bill_alignments
-- ---------------------------------------------------------------------------
ALTER TABLE user_bill_alignments
    ALTER COLUMN bill_stance_direction TYPE stance_direction_type
    USING bill_stance_direction::stance_direction_type;

-- ---------------------------------------------------------------------------
-- user_amendment_alignments
-- ---------------------------------------------------------------------------
ALTER TABLE user_amendment_alignments
    ALTER COLUMN amendment_stance_direction TYPE stance_direction_type
    USING amendment_stance_direction::stance_direction_type;

-- ---------------------------------------------------------------------------
-- user_legislator_pairings
-- ---------------------------------------------------------------------------
ALTER TABLE user_legislator_pairings
    ALTER COLUMN chamber TYPE chamber_type USING chamber::chamber_type;

-- ---------------------------------------------------------------------------
-- user_preferences
-- ---------------------------------------------------------------------------
ALTER TABLE user_preferences
    ALTER COLUMN stance TYPE user_stance_type USING stance::user_stance_type;

-- ---------------------------------------------------------------------------
-- qa_question_topics
-- agree_stance stores 'Progressive' or 'Conservative' — subset of
-- stance_direction_type, which also accepts 'Neutral' and 'Bipartisan'.
-- ---------------------------------------------------------------------------
ALTER TABLE qa_question_topics
    ALTER COLUMN agree_stance TYPE stance_direction_type
    USING agree_stance::stance_direction_type;

-- ---------------------------------------------------------------------------
-- scores
-- ---------------------------------------------------------------------------
ALTER TABLE scores ALTER COLUMN status DROP DEFAULT;
ALTER TABLE scores
    ALTER COLUMN status TYPE score_status_type USING status::score_status_type;
ALTER TABLE scores
    ALTER COLUMN status SET DEFAULT 'scored'::score_status_type;

-- ---------------------------------------------------------------------------
-- score_history
-- ---------------------------------------------------------------------------
ALTER TABLE score_history ALTER COLUMN status DROP DEFAULT;
ALTER TABLE score_history
    ALTER COLUMN status TYPE score_status_type USING status::score_status_type;
ALTER TABLE score_history
    ALTER COLUMN status SET DEFAULT 'scored'::score_status_type;

-- ---------------------------------------------------------------------------
-- pipeline_runs
-- ---------------------------------------------------------------------------
ALTER TABLE pipeline_runs ALTER COLUMN status DROP DEFAULT;
ALTER TABLE pipeline_runs
    ALTER COLUMN status TYPE pipeline_status_type USING status::pipeline_status_type;
ALTER TABLE pipeline_runs
    ALTER COLUMN status SET DEFAULT 'running'::pipeline_status_type;

ALTER TABLE pipeline_runs ALTER COLUMN trigger DROP DEFAULT;
ALTER TABLE pipeline_runs
    ALTER COLUMN trigger TYPE trigger_type USING trigger::trigger_type;
ALTER TABLE pipeline_runs
    ALTER COLUMN trigger SET DEFAULT 'scheduled'::trigger_type;

-- ---------------------------------------------------------------------------
-- processing_results
-- ---------------------------------------------------------------------------
ALTER TABLE processing_results
    ALTER COLUMN entity_type TYPE processing_entity_type
    USING entity_type::processing_entity_type;

ALTER TABLE processing_results
    ALTER COLUMN status TYPE processing_status_type USING status::processing_status_type;

ALTER TABLE processing_results
    ALTER COLUMN error_class TYPE error_class_type USING error_class::error_class_type;

-- ---------------------------------------------------------------------------
-- workflow_runs
-- ---------------------------------------------------------------------------
ALTER TABLE workflow_runs ALTER COLUMN status DROP DEFAULT;
ALTER TABLE workflow_runs
    ALTER COLUMN status TYPE workflow_status_type USING status::workflow_status_type;
ALTER TABLE workflow_runs
    ALTER COLUMN status SET DEFAULT 'pending'::workflow_status_type;

ALTER TABLE workflow_runs ALTER COLUMN trigger DROP DEFAULT;
ALTER TABLE workflow_runs
    ALTER COLUMN trigger TYPE trigger_type USING trigger::trigger_type;
ALTER TABLE workflow_runs
    ALTER COLUMN trigger SET DEFAULT 'scheduled'::trigger_type;

-- ---------------------------------------------------------------------------
-- workflow_run_steps
-- ---------------------------------------------------------------------------
ALTER TABLE workflow_run_steps ALTER COLUMN status DROP DEFAULT;
ALTER TABLE workflow_run_steps
    ALTER COLUMN status TYPE workflow_status_type USING status::workflow_status_type;
ALTER TABLE workflow_run_steps
    ALTER COLUMN status SET DEFAULT 'pending'::workflow_status_type;
