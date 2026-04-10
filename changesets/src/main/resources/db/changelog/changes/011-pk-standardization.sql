-- =============================================================================
-- RepCheck Database Schema -- V11 Primary Key Standardization
-- =============================================================================
-- Standardizes ALL primary keys to `id BIGSERIAL PRIMARY KEY` with the
-- following exceptions:
--   - users: keeps user_id UUID PRIMARY KEY
--   - us_states: keeps state_code TEXT PRIMARY KEY (pure reference table)
--
-- TEXT PK tables get id BIGSERIAL + natural_key TEXT UNIQUE NOT NULL.
-- UUID PK tables get id BIGSERIAL, old UUID column dropped entirely.
-- Composite PK tables get id BIGSERIAL, old composite PK becomes UNIQUE.
-- All FK columns updated to reference new BIGINT id columns.
--
-- History tables have NO FK constraints by design, but their TEXT/UUID
-- columns still get converted to BIGINT for consistency.
-- =============================================================================

-- ===========================================================================
-- SECTION 1: Create new LIS tables (split lis_member_mapping)
-- ===========================================================================

-- 1a. lis_members -- standalone table for LIS member identifiers
CREATE TABLE lis_members (
    id                   BIGSERIAL   PRIMARY KEY,
    natural_key          TEXT        UNIQUE NOT NULL,  -- e.g., "S428"
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed from existing lis_member_mapping
INSERT INTO lis_members (natural_key)
SELECT lis_member_id FROM lis_member_mapping;

-- ===========================================================================
-- SECTION 2: Add id BIGSERIAL + natural_key to TEXT PK tables
-- ===========================================================================

-- 2a. members: member_id TEXT -> id BIGSERIAL + natural_key
ALTER TABLE members ADD COLUMN id BIGSERIAL;
ALTER TABLE members RENAME COLUMN member_id TO natural_key;

-- 2b. votes: vote_id TEXT -> id BIGSERIAL + natural_key
ALTER TABLE votes ADD COLUMN id BIGSERIAL;
ALTER TABLE votes RENAME COLUMN vote_id TO natural_key;

-- 2c. amendments: amendment_id TEXT -> id BIGSERIAL + natural_key
ALTER TABLE amendments ADD COLUMN id BIGSERIAL;
ALTER TABLE amendments RENAME COLUMN amendment_id TO natural_key;

-- 2d. committees: committee_id TEXT -> id BIGSERIAL + natural_key
ALTER TABLE committees ADD COLUMN id BIGSERIAL;
ALTER TABLE committees RENAME COLUMN committee_id TO natural_key;

-- 2e. qa_questions: question_id TEXT -> id BIGSERIAL + natural_key
ALTER TABLE qa_questions ADD COLUMN id BIGSERIAL;
ALTER TABLE qa_questions RENAME COLUMN question_id TO natural_key;

-- 2f. finding_types: finding_type_id SERIAL -> id BIGSERIAL (rename code stays)
ALTER TABLE finding_types ADD COLUMN id BIGSERIAL;

-- ===========================================================================
-- SECTION 3: Drop ALL FK constraints
-- ===========================================================================
-- Must drop FKs before modifying any referenced columns.
-- Organized by parent table dependency order.

-- FKs referencing members(natural_key) [was member_id]
ALTER TABLE member_terms DROP CONSTRAINT IF EXISTS member_terms_member_id_fkey;
ALTER TABLE member_party_history DROP CONSTRAINT IF EXISTS member_party_history_member_id_fkey;
ALTER TABLE bills DROP CONSTRAINT IF EXISTS bills_sponsor_bioguide_id_fkey;
ALTER TABLE bill_cosponsors DROP CONSTRAINT IF EXISTS bill_cosponsors_member_id_fkey;
ALTER TABLE vote_positions DROP CONSTRAINT IF EXISTS vote_positions_member_id_fkey;
ALTER TABLE scores DROP CONSTRAINT IF EXISTS scores_member_id_fkey;
ALTER TABLE score_history DROP CONSTRAINT IF EXISTS score_history_member_id_fkey;
ALTER TABLE member_bill_stances DROP CONSTRAINT IF EXISTS member_bill_stances_member_id_fkey;
ALTER TABLE amendments DROP CONSTRAINT IF EXISTS amendments_sponsor_bioguide_id_fkey;
ALTER TABLE committee_members DROP CONSTRAINT IF EXISTS committee_members_member_id_fkey;
ALTER TABLE user_legislator_pairings DROP CONSTRAINT IF EXISTS user_legislator_pairings_member_id_fkey;
ALTER TABLE lis_member_mapping DROP CONSTRAINT IF EXISTS lis_member_mapping_member_id_fkey;

-- FKs referencing votes(natural_key) [was vote_id]
ALTER TABLE vote_positions DROP CONSTRAINT IF EXISTS vote_positions_vote_id_fkey;
ALTER TABLE member_bill_stances DROP CONSTRAINT IF EXISTS member_bill_stances_vote_id_fkey;

-- FKs referencing amendments(natural_key) [was amendment_id]
ALTER TABLE amendment_findings DROP CONSTRAINT IF EXISTS amendment_findings_amendment_id_fkey;
ALTER TABLE amendment_analyses DROP CONSTRAINT IF EXISTS amendment_analyses_amendment_id_fkey;
ALTER TABLE amendment_concept_summaries DROP CONSTRAINT IF EXISTS amendment_concept_summaries_amendment_id_fkey;
ALTER TABLE amendment_analysis_topics DROP CONSTRAINT IF EXISTS amendment_analysis_topics_amendment_id_fkey;
ALTER TABLE amendment_text_versions DROP CONSTRAINT IF EXISTS amendment_text_versions_amendment_id_fkey;
ALTER TABLE votes DROP CONSTRAINT IF EXISTS votes_amendment_id_fkey;
ALTER TABLE member_bill_stances DROP CONSTRAINT IF EXISTS member_bill_stances_amendment_id_fkey;
ALTER TABLE user_amendment_alignments DROP CONSTRAINT IF EXISTS user_amendment_alignments_amendment_id_fkey;
-- Also the self-referencing FK on amendments.latest_text_version_id
ALTER TABLE amendments DROP CONSTRAINT IF EXISTS fk_amendments_latest_text_version;

-- FKs referencing committees(natural_key) [was committee_id]
ALTER TABLE committees DROP CONSTRAINT IF EXISTS committees_parent_committee_id_fkey;
ALTER TABLE committee_members DROP CONSTRAINT IF EXISTS committee_members_committee_id_fkey;
ALTER TABLE bill_committee_referrals DROP CONSTRAINT IF EXISTS bill_committee_referrals_committee_id_fkey;

-- FKs referencing qa_questions(natural_key) [was question_id]
ALTER TABLE qa_question_topics DROP CONSTRAINT IF EXISTS qa_question_topics_question_id_fkey;
ALTER TABLE qa_answer_options DROP CONSTRAINT IF EXISTS qa_answer_options_question_id_fkey;
ALTER TABLE qa_user_responses DROP CONSTRAINT IF EXISTS qa_user_responses_question_id_fkey;

-- FKs referencing finding_types(finding_type_id)
ALTER TABLE bill_findings DROP CONSTRAINT IF EXISTS bill_findings_finding_type_id_fkey;
ALTER TABLE amendment_findings DROP CONSTRAINT IF EXISTS amendment_findings_finding_type_id_fkey;

-- FKs referencing bills(id) -- these stay BIGINT but need re-creation after composite PK changes
ALTER TABLE bill_cosponsors DROP CONSTRAINT IF EXISTS bill_cosponsors_bill_id_fkey;
ALTER TABLE bill_subjects DROP CONSTRAINT IF EXISTS bill_subjects_bill_id_fkey;
ALTER TABLE bill_text_versions DROP CONSTRAINT IF EXISTS bill_text_versions_bill_id_fkey;
ALTER TABLE bill_text_sections DROP CONSTRAINT IF EXISTS bill_text_sections_bill_id_fkey;
ALTER TABLE bill_concept_groups DROP CONSTRAINT IF EXISTS bill_concept_groups_bill_id_fkey;
ALTER TABLE bill_analyses DROP CONSTRAINT IF EXISTS bill_analyses_bill_id_fkey;
ALTER TABLE bill_findings DROP CONSTRAINT IF EXISTS bill_findings_bill_id_fkey;
ALTER TABLE bill_concept_summaries DROP CONSTRAINT IF EXISTS bill_concept_summaries_bill_id_fkey;
ALTER TABLE bill_analysis_topics DROP CONSTRAINT IF EXISTS bill_analysis_topics_bill_id_fkey;
ALTER TABLE bill_fiscal_estimates DROP CONSTRAINT IF EXISTS bill_fiscal_estimates_bill_id_fkey;
ALTER TABLE votes DROP CONSTRAINT IF EXISTS votes_bill_id_fkey;
ALTER TABLE amendments DROP CONSTRAINT IF EXISTS amendments_bill_id_fkey;
ALTER TABLE member_bill_stances DROP CONSTRAINT IF EXISTS member_bill_stances_bill_id_fkey;
ALTER TABLE score_history_highlights DROP CONSTRAINT IF EXISTS score_history_highlights_bill_id_fkey;
ALTER TABLE user_bill_alignments DROP CONSTRAINT IF EXISTS user_bill_alignments_bill_id_fkey;
ALTER TABLE user_amendment_alignments DROP CONSTRAINT IF EXISTS user_amendment_alignments_bill_id_fkey;
ALTER TABLE amendment_analyses DROP CONSTRAINT IF EXISTS amendment_analyses_bill_id_fkey;
ALTER TABLE amendment_concept_summaries DROP CONSTRAINT IF EXISTS amendment_concept_summaries_bill_id_fkey;
ALTER TABLE stance_materialization_status DROP CONSTRAINT IF EXISTS stance_materialization_status_bill_id_fkey;
ALTER TABLE bill_committee_referrals DROP CONSTRAINT IF EXISTS bill_committee_referrals_bill_id_fkey;
ALTER TABLE bills DROP CONSTRAINT IF EXISTS bills_latest_text_version_id_fkey;

-- FKs referencing UUID PK tables (will be converted to BIGINT)
-- bill_text_versions
ALTER TABLE bill_text_sections DROP CONSTRAINT IF EXISTS bill_text_sections_version_id_fkey;
ALTER TABLE bill_concept_groups DROP CONSTRAINT IF EXISTS bill_concept_groups_version_id_fkey;
ALTER TABLE bill_analyses DROP CONSTRAINT IF EXISTS bill_analyses_version_id_fkey;

-- bill_text_sections
ALTER TABLE bill_concept_group_sections DROP CONSTRAINT IF EXISTS bill_concept_group_sections_section_id_fkey;

-- bill_concept_groups
ALTER TABLE bill_concept_group_sections DROP CONSTRAINT IF EXISTS bill_concept_group_sections_concept_group_id_fkey;
ALTER TABLE bill_concept_summaries DROP CONSTRAINT IF EXISTS bill_concept_summaries_concept_group_id_fkey;
ALTER TABLE bill_fiscal_estimates DROP CONSTRAINT IF EXISTS bill_fiscal_estimates_concept_group_id_fkey;

-- bill_analyses
ALTER TABLE bill_concept_summaries DROP CONSTRAINT IF EXISTS bill_concept_summaries_analysis_id_fkey;
ALTER TABLE bill_analysis_topics DROP CONSTRAINT IF EXISTS bill_analysis_topics_analysis_id_fkey;
ALTER TABLE bill_fiscal_estimates DROP CONSTRAINT IF EXISTS bill_fiscal_estimates_analysis_id_fkey;
ALTER TABLE bill_findings DROP CONSTRAINT IF EXISTS bill_findings_analysis_id_fkey;

-- bill_findings
ALTER TABLE member_bill_stance_topics DROP CONSTRAINT IF EXISTS member_bill_stance_topics_finding_id_fkey;
ALTER TABLE user_bill_alignments DROP CONSTRAINT IF EXISTS user_bill_alignments_finding_id_fkey;

-- amendment_findings
ALTER TABLE user_amendment_alignments DROP CONSTRAINT IF EXISTS user_amendment_alignments_finding_id_fkey;

-- amendment_analyses
ALTER TABLE amendment_concept_summaries DROP CONSTRAINT IF EXISTS amendment_concept_summaries_analysis_id_fkey;
ALTER TABLE amendment_analysis_topics DROP CONSTRAINT IF EXISTS amendment_analysis_topics_analysis_id_fkey;
ALTER TABLE amendment_findings DROP CONSTRAINT IF EXISTS amendment_findings_analysis_id_fkey;

-- vote_history
ALTER TABLE vote_history_positions DROP CONSTRAINT IF EXISTS vote_history_positions_history_id_fkey;

-- member_history
ALTER TABLE member_term_history DROP CONSTRAINT IF EXISTS member_term_history_history_id_fkey;

-- bill_history
ALTER TABLE bill_cosponsor_history DROP CONSTRAINT IF EXISTS bill_cosponsor_history_history_id_fkey;
ALTER TABLE bill_subject_history DROP CONSTRAINT IF EXISTS bill_subject_history_history_id_fkey;

-- score_history
ALTER TABLE score_history_congress DROP CONSTRAINT IF EXISTS score_history_congress_score_id_fkey;
ALTER TABLE score_history_highlights DROP CONSTRAINT IF EXISTS score_history_highlights_score_id_fkey;

-- score_history_congress
ALTER TABLE score_history_congress_topics DROP CONSTRAINT IF EXISTS score_history_congress_topics_score_id_congress_fkey;

-- scores composite FK
ALTER TABLE score_topics DROP CONSTRAINT IF EXISTS score_topics_user_id_member_id_fkey;
ALTER TABLE score_congress DROP CONSTRAINT IF EXISTS score_congress_user_id_member_id_fkey;

-- score_congress composite FK
ALTER TABLE score_congress_topics DROP CONSTRAINT IF EXISTS score_congress_topics_user_id_member_id_congress_fkey;

-- users
ALTER TABLE user_preferences DROP CONSTRAINT IF EXISTS user_preferences_user_id_fkey;
ALTER TABLE scores DROP CONSTRAINT IF EXISTS scores_user_id_fkey;
ALTER TABLE score_history DROP CONSTRAINT IF EXISTS score_history_user_id_fkey;
ALTER TABLE qa_user_responses DROP CONSTRAINT IF EXISTS qa_user_responses_user_id_fkey;
ALTER TABLE user_legislator_pairings DROP CONSTRAINT IF EXISTS user_legislator_pairings_user_id_fkey;
ALTER TABLE user_bill_alignments DROP CONSTRAINT IF EXISTS user_bill_alignments_user_id_fkey;
ALTER TABLE user_amendment_alignments DROP CONSTRAINT IF EXISTS user_amendment_alignments_user_id_fkey;

-- pipeline_runs
ALTER TABLE processing_results DROP CONSTRAINT IF EXISTS processing_results_run_id_fkey;
ALTER TABLE workflow_run_steps DROP CONSTRAINT IF EXISTS workflow_run_steps_pipeline_run_id_fkey;

-- workflow_runs
ALTER TABLE workflow_run_steps DROP CONSTRAINT IF EXISTS workflow_run_steps_workflow_run_id_fkey;

-- member_bill_stances composite FK from member_bill_stance_topics
ALTER TABLE member_bill_stance_topics DROP CONSTRAINT IF EXISTS member_bill_stance_topics_member_id_bill_id_vote_id_fkey;

-- amendment_text_versions (for amendments.latest_text_version_id)
-- already dropped above

-- ===========================================================================
-- SECTION 4: Convert FK columns TEXT/UUID -> BIGINT
-- ===========================================================================
-- For each FK column that references a TEXT or UUID PK, add a new BIGINT
-- column, populate via subquery, drop old column, rename new.

-- -----------------------------------------------------------------------
-- 4a. Convert member_id TEXT FKs -> BIGINT (referencing members.id)
-- -----------------------------------------------------------------------

-- member_terms.member_id TEXT -> BIGINT
ALTER TABLE member_terms ADD COLUMN member_id_new BIGINT;
UPDATE member_terms mt SET member_id_new = m.id FROM members m WHERE mt.member_id = m.natural_key;
ALTER TABLE member_terms DROP COLUMN member_id;
ALTER TABLE member_terms RENAME COLUMN member_id_new TO member_id;
ALTER TABLE member_terms ALTER COLUMN member_id SET NOT NULL;

-- member_party_history.member_id TEXT -> BIGINT
ALTER TABLE member_party_history ADD COLUMN member_id_new BIGINT;
UPDATE member_party_history mph SET member_id_new = m.id FROM members m WHERE mph.member_id = m.natural_key;
ALTER TABLE member_party_history DROP COLUMN member_id;
ALTER TABLE member_party_history RENAME COLUMN member_id_new TO member_id;
ALTER TABLE member_party_history ALTER COLUMN member_id SET NOT NULL;

-- bills.sponsor_bioguide_id TEXT -> sponsor_member_id BIGINT (Rule 7)
ALTER TABLE bills ADD COLUMN sponsor_member_id BIGINT;
UPDATE bills b SET sponsor_member_id = m.id FROM members m WHERE b.sponsor_bioguide_id = m.natural_key;
ALTER TABLE bills DROP COLUMN sponsor_bioguide_id;

-- bill_cosponsors.member_id TEXT -> BIGINT
ALTER TABLE bill_cosponsors ADD COLUMN member_id_new BIGINT;
UPDATE bill_cosponsors bc SET member_id_new = m.id FROM members m WHERE bc.member_id = m.natural_key;
ALTER TABLE bill_cosponsors DROP COLUMN member_id;
ALTER TABLE bill_cosponsors RENAME COLUMN member_id_new TO member_id;
ALTER TABLE bill_cosponsors ALTER COLUMN member_id SET NOT NULL;

-- vote_positions.member_id TEXT -> BIGINT
ALTER TABLE vote_positions ADD COLUMN member_id_new BIGINT;
UPDATE vote_positions vp SET member_id_new = m.id FROM members m WHERE vp.member_id = m.natural_key;
ALTER TABLE vote_positions DROP COLUMN member_id;
ALTER TABLE vote_positions RENAME COLUMN member_id_new TO member_id;
ALTER TABLE vote_positions ALTER COLUMN member_id SET NOT NULL;

-- scores.member_id TEXT -> BIGINT
ALTER TABLE scores ADD COLUMN member_id_new BIGINT;
UPDATE scores s SET member_id_new = m.id FROM members m WHERE s.member_id = m.natural_key;
ALTER TABLE scores DROP COLUMN member_id;
ALTER TABLE scores RENAME COLUMN member_id_new TO member_id;
ALTER TABLE scores ALTER COLUMN member_id SET NOT NULL;

-- score_topics.member_id TEXT -> BIGINT
ALTER TABLE score_topics ADD COLUMN member_id_new BIGINT;
UPDATE score_topics st SET member_id_new = m.id FROM members m WHERE st.member_id = m.natural_key;
ALTER TABLE score_topics DROP COLUMN member_id;
ALTER TABLE score_topics RENAME COLUMN member_id_new TO member_id;
ALTER TABLE score_topics ALTER COLUMN member_id SET NOT NULL;

-- score_congress.member_id TEXT -> BIGINT
ALTER TABLE score_congress ADD COLUMN member_id_new BIGINT;
UPDATE score_congress sc SET member_id_new = m.id FROM members m WHERE sc.member_id = m.natural_key;
ALTER TABLE score_congress DROP COLUMN member_id;
ALTER TABLE score_congress RENAME COLUMN member_id_new TO member_id;
ALTER TABLE score_congress ALTER COLUMN member_id SET NOT NULL;

-- score_congress_topics.member_id TEXT -> BIGINT
ALTER TABLE score_congress_topics ADD COLUMN member_id_new BIGINT;
UPDATE score_congress_topics sct SET member_id_new = m.id FROM members m WHERE sct.member_id = m.natural_key;
ALTER TABLE score_congress_topics DROP COLUMN member_id;
ALTER TABLE score_congress_topics RENAME COLUMN member_id_new TO member_id;
ALTER TABLE score_congress_topics ALTER COLUMN member_id SET NOT NULL;

-- score_history.member_id TEXT -> BIGINT
ALTER TABLE score_history ADD COLUMN member_id_new BIGINT;
UPDATE score_history sh SET member_id_new = m.id FROM members m WHERE sh.member_id = m.natural_key;
ALTER TABLE score_history DROP COLUMN member_id;
ALTER TABLE score_history RENAME COLUMN member_id_new TO member_id;
ALTER TABLE score_history ALTER COLUMN member_id SET NOT NULL;

-- member_bill_stances.member_id TEXT -> BIGINT
ALTER TABLE member_bill_stances ADD COLUMN member_id_new BIGINT;
UPDATE member_bill_stances mbs SET member_id_new = m.id FROM members m WHERE mbs.member_id = m.natural_key;
ALTER TABLE member_bill_stances DROP COLUMN member_id;
ALTER TABLE member_bill_stances RENAME COLUMN member_id_new TO member_id;
ALTER TABLE member_bill_stances ALTER COLUMN member_id SET NOT NULL;

-- member_bill_stance_topics.member_id TEXT -> BIGINT
ALTER TABLE member_bill_stance_topics ADD COLUMN member_id_new BIGINT;
UPDATE member_bill_stance_topics mbst SET member_id_new = m.id FROM members m WHERE mbst.member_id = m.natural_key;
ALTER TABLE member_bill_stance_topics DROP COLUMN member_id;
ALTER TABLE member_bill_stance_topics RENAME COLUMN member_id_new TO member_id;
ALTER TABLE member_bill_stance_topics ALTER COLUMN member_id SET NOT NULL;

-- amendments.sponsor_bioguide_id TEXT -> sponsor_member_id BIGINT (Rule 7)
ALTER TABLE amendments ADD COLUMN sponsor_member_id BIGINT;
UPDATE amendments a SET sponsor_member_id = m.id FROM members m WHERE a.sponsor_bioguide_id = m.natural_key;
ALTER TABLE amendments DROP COLUMN sponsor_bioguide_id;

-- committee_members.member_id TEXT -> BIGINT
ALTER TABLE committee_members ADD COLUMN member_id_new BIGINT;
UPDATE committee_members cm SET member_id_new = m.id FROM members m WHERE cm.member_id = m.natural_key;
ALTER TABLE committee_members DROP COLUMN member_id;
ALTER TABLE committee_members RENAME COLUMN member_id_new TO member_id;
ALTER TABLE committee_members ALTER COLUMN member_id SET NOT NULL;

-- user_legislator_pairings.member_id TEXT -> BIGINT
ALTER TABLE user_legislator_pairings ADD COLUMN member_id_new BIGINT;
UPDATE user_legislator_pairings ulp SET member_id_new = m.id FROM members m WHERE ulp.member_id = m.natural_key;
ALTER TABLE user_legislator_pairings DROP COLUMN member_id;
ALTER TABLE user_legislator_pairings RENAME COLUMN member_id_new TO member_id;
ALTER TABLE user_legislator_pairings ALTER COLUMN member_id SET NOT NULL;

-- -----------------------------------------------------------------------
-- 4b. Convert vote_id TEXT FKs -> BIGINT (referencing votes.id)
-- -----------------------------------------------------------------------

-- vote_positions.vote_id TEXT -> BIGINT
ALTER TABLE vote_positions ADD COLUMN vote_id_new BIGINT;
UPDATE vote_positions vp SET vote_id_new = v.id FROM votes v WHERE vp.vote_id = v.natural_key;
ALTER TABLE vote_positions DROP COLUMN vote_id;
ALTER TABLE vote_positions RENAME COLUMN vote_id_new TO vote_id;
ALTER TABLE vote_positions ALTER COLUMN vote_id SET NOT NULL;

-- member_bill_stances.vote_id TEXT -> BIGINT
ALTER TABLE member_bill_stances ADD COLUMN vote_id_new BIGINT;
UPDATE member_bill_stances mbs SET vote_id_new = v.id FROM votes v WHERE mbs.vote_id = v.natural_key;
ALTER TABLE member_bill_stances DROP COLUMN vote_id;
ALTER TABLE member_bill_stances RENAME COLUMN vote_id_new TO vote_id;
ALTER TABLE member_bill_stances ALTER COLUMN vote_id SET NOT NULL;

-- member_bill_stance_topics.vote_id TEXT -> BIGINT
ALTER TABLE member_bill_stance_topics ADD COLUMN vote_id_new BIGINT;
UPDATE member_bill_stance_topics mbst SET vote_id_new = v.id FROM votes v WHERE mbst.vote_id = v.natural_key;
ALTER TABLE member_bill_stance_topics DROP COLUMN vote_id;
ALTER TABLE member_bill_stance_topics RENAME COLUMN vote_id_new TO vote_id;
ALTER TABLE member_bill_stance_topics ALTER COLUMN vote_id SET NOT NULL;

-- -----------------------------------------------------------------------
-- 4c. Convert amendment_id TEXT FKs -> BIGINT (referencing amendments.id)
-- -----------------------------------------------------------------------

-- amendment_findings.amendment_id TEXT -> BIGINT
ALTER TABLE amendment_findings ADD COLUMN amendment_id_new BIGINT;
UPDATE amendment_findings af SET amendment_id_new = a.id FROM amendments a WHERE af.amendment_id = a.natural_key;
ALTER TABLE amendment_findings DROP COLUMN amendment_id;
ALTER TABLE amendment_findings RENAME COLUMN amendment_id_new TO amendment_id;
ALTER TABLE amendment_findings ALTER COLUMN amendment_id SET NOT NULL;

-- amendment_analyses.amendment_id TEXT -> BIGINT
ALTER TABLE amendment_analyses ADD COLUMN amendment_id_new BIGINT;
UPDATE amendment_analyses aa SET amendment_id_new = a.id FROM amendments a WHERE aa.amendment_id = a.natural_key;
ALTER TABLE amendment_analyses DROP COLUMN amendment_id;
ALTER TABLE amendment_analyses RENAME COLUMN amendment_id_new TO amendment_id;
ALTER TABLE amendment_analyses ALTER COLUMN amendment_id SET NOT NULL;

-- amendment_concept_summaries.amendment_id TEXT -> BIGINT
ALTER TABLE amendment_concept_summaries ADD COLUMN amendment_id_new BIGINT;
UPDATE amendment_concept_summaries acs SET amendment_id_new = a.id FROM amendments a WHERE acs.amendment_id = a.natural_key;
ALTER TABLE amendment_concept_summaries DROP COLUMN amendment_id;
ALTER TABLE amendment_concept_summaries RENAME COLUMN amendment_id_new TO amendment_id;
ALTER TABLE amendment_concept_summaries ALTER COLUMN amendment_id SET NOT NULL;

-- amendment_analysis_topics.amendment_id TEXT -> BIGINT
ALTER TABLE amendment_analysis_topics ADD COLUMN amendment_id_new BIGINT;
UPDATE amendment_analysis_topics aat SET amendment_id_new = a.id FROM amendments a WHERE aat.amendment_id = a.natural_key;
ALTER TABLE amendment_analysis_topics DROP COLUMN amendment_id;
ALTER TABLE amendment_analysis_topics RENAME COLUMN amendment_id_new TO amendment_id;
ALTER TABLE amendment_analysis_topics ALTER COLUMN amendment_id SET NOT NULL;

-- amendment_text_versions.amendment_id TEXT -> BIGINT
ALTER TABLE amendment_text_versions ADD COLUMN amendment_id_new BIGINT;
UPDATE amendment_text_versions atv SET amendment_id_new = a.id FROM amendments a WHERE atv.amendment_id = a.natural_key;
ALTER TABLE amendment_text_versions DROP COLUMN amendment_id;
ALTER TABLE amendment_text_versions RENAME COLUMN amendment_id_new TO amendment_id;
ALTER TABLE amendment_text_versions ALTER COLUMN amendment_id SET NOT NULL;

-- votes.amendment_id TEXT -> BIGINT (nullable)
ALTER TABLE votes ADD COLUMN amendment_id_new BIGINT;
UPDATE votes v SET amendment_id_new = a.id FROM amendments a WHERE v.amendment_id = a.natural_key;
ALTER TABLE votes DROP COLUMN amendment_id;
ALTER TABLE votes RENAME COLUMN amendment_id_new TO amendment_id;

-- member_bill_stances.amendment_id TEXT -> BIGINT (nullable)
ALTER TABLE member_bill_stances ADD COLUMN amendment_id_new BIGINT;
UPDATE member_bill_stances mbs SET amendment_id_new = a.id FROM amendments a WHERE mbs.amendment_id = a.natural_key;
ALTER TABLE member_bill_stances DROP COLUMN amendment_id;
ALTER TABLE member_bill_stances RENAME COLUMN amendment_id_new TO amendment_id;

-- user_amendment_alignments.amendment_id TEXT -> BIGINT
ALTER TABLE user_amendment_alignments ADD COLUMN amendment_id_new BIGINT;
UPDATE user_amendment_alignments uaa SET amendment_id_new = a.id FROM amendments a WHERE uaa.amendment_id = a.natural_key;
ALTER TABLE user_amendment_alignments DROP COLUMN amendment_id;
ALTER TABLE user_amendment_alignments RENAME COLUMN amendment_id_new TO amendment_id;
ALTER TABLE user_amendment_alignments ALTER COLUMN amendment_id SET NOT NULL;

-- -----------------------------------------------------------------------
-- 4d. Convert committee_id TEXT FKs -> BIGINT (referencing committees.id)
-- -----------------------------------------------------------------------

-- committees.parent_committee_id TEXT -> BIGINT (nullable, self-referencing)
ALTER TABLE committees ADD COLUMN parent_committee_id_new BIGINT;
UPDATE committees c SET parent_committee_id_new = p.id FROM committees p WHERE c.parent_committee_id = p.natural_key;
ALTER TABLE committees DROP COLUMN parent_committee_id;
ALTER TABLE committees RENAME COLUMN parent_committee_id_new TO parent_committee_id;

-- committee_members.committee_id TEXT -> BIGINT
ALTER TABLE committee_members ADD COLUMN committee_id_new BIGINT;
UPDATE committee_members cm SET committee_id_new = c.id FROM committees c WHERE cm.committee_id = c.natural_key;
ALTER TABLE committee_members DROP COLUMN committee_id;
ALTER TABLE committee_members RENAME COLUMN committee_id_new TO committee_id;
ALTER TABLE committee_members ALTER COLUMN committee_id SET NOT NULL;

-- bill_committee_referrals.committee_id TEXT -> BIGINT
ALTER TABLE bill_committee_referrals ADD COLUMN committee_id_new BIGINT;
UPDATE bill_committee_referrals bcr SET committee_id_new = c.id FROM committees c WHERE bcr.committee_id = c.natural_key;
ALTER TABLE bill_committee_referrals DROP COLUMN committee_id;
ALTER TABLE bill_committee_referrals RENAME COLUMN committee_id_new TO committee_id;
ALTER TABLE bill_committee_referrals ALTER COLUMN committee_id SET NOT NULL;

-- -----------------------------------------------------------------------
-- 4e. Convert question_id TEXT FKs -> BIGINT (referencing qa_questions.id)
-- -----------------------------------------------------------------------

-- qa_question_topics.question_id TEXT -> BIGINT
ALTER TABLE qa_question_topics ADD COLUMN question_id_new BIGINT;
UPDATE qa_question_topics qqt SET question_id_new = q.id FROM qa_questions q WHERE qqt.question_id = q.natural_key;
ALTER TABLE qa_question_topics DROP COLUMN question_id;
ALTER TABLE qa_question_topics RENAME COLUMN question_id_new TO question_id;
ALTER TABLE qa_question_topics ALTER COLUMN question_id SET NOT NULL;

-- qa_answer_options.question_id TEXT -> BIGINT
ALTER TABLE qa_answer_options ADD COLUMN question_id_new BIGINT;
UPDATE qa_answer_options qao SET question_id_new = q.id FROM qa_questions q WHERE qao.question_id = q.natural_key;
ALTER TABLE qa_answer_options DROP COLUMN question_id;
ALTER TABLE qa_answer_options RENAME COLUMN question_id_new TO question_id;
ALTER TABLE qa_answer_options ALTER COLUMN question_id SET NOT NULL;

-- qa_user_responses.question_id TEXT -> BIGINT
ALTER TABLE qa_user_responses ADD COLUMN question_id_new BIGINT;
UPDATE qa_user_responses qur SET question_id_new = q.id FROM qa_questions q WHERE qur.question_id = q.natural_key;
ALTER TABLE qa_user_responses DROP COLUMN question_id;
ALTER TABLE qa_user_responses RENAME COLUMN question_id_new TO question_id;
ALTER TABLE qa_user_responses ALTER COLUMN question_id SET NOT NULL;

-- -----------------------------------------------------------------------
-- 4f. Convert finding_type_id INT FKs -> BIGINT (referencing finding_types.id)
-- -----------------------------------------------------------------------

-- bill_findings.finding_type_id INT -> BIGINT (lookup by old finding_type_id)
ALTER TABLE bill_findings ADD COLUMN finding_type_id_new BIGINT;
UPDATE bill_findings bf SET finding_type_id_new = ft.id FROM finding_types ft WHERE bf.finding_type_id = ft.finding_type_id;
ALTER TABLE bill_findings DROP COLUMN finding_type_id;
ALTER TABLE bill_findings RENAME COLUMN finding_type_id_new TO finding_type_id;
ALTER TABLE bill_findings ALTER COLUMN finding_type_id SET NOT NULL;

-- amendment_findings.finding_type_id INT -> BIGINT (lookup by old finding_type_id)
ALTER TABLE amendment_findings ADD COLUMN finding_type_id_new BIGINT;
UPDATE amendment_findings af SET finding_type_id_new = ft.id FROM finding_types ft WHERE af.finding_type_id = ft.finding_type_id;
ALTER TABLE amendment_findings DROP COLUMN finding_type_id;
ALTER TABLE amendment_findings RENAME COLUMN finding_type_id_new TO finding_type_id;
ALTER TABLE amendment_findings ALTER COLUMN finding_type_id SET NOT NULL;

-- -----------------------------------------------------------------------
-- 4g. Convert UUID FK columns -> BIGINT for UUID PK tables
-- -----------------------------------------------------------------------

-- bill_text_versions: version_id UUID PK -> id BIGSERIAL
-- First add id to bill_text_versions (done in Section 6)
-- Here we convert FK columns that reference bill_text_versions.version_id

-- bills.latest_text_version_id UUID -> BIGINT
-- (Will be populated after bill_text_versions gets its id in Section 6)

-- bill_text_sections.version_id UUID -> BIGINT
-- (Will be populated after bill_text_versions gets its id in Section 6)

-- bill_concept_groups.version_id UUID -> BIGINT
-- (Will be populated after bill_text_versions gets its id in Section 6)

-- bill_analyses.version_id UUID -> BIGINT
-- (Will be populated after bill_text_versions gets its id in Section 6)

-- amendments.latest_text_version_id UUID -> BIGINT
-- (Will be populated after amendment_text_versions gets its id in Section 6)

-- -----------------------------------------------------------------------
-- 4h. Convert history table TEXT/UUID columns -> BIGINT (no FKs)
-- -----------------------------------------------------------------------

-- vote_history.vote_id TEXT -> BIGINT (LEFT JOIN for orphans)
ALTER TABLE vote_history ADD COLUMN vote_id_new BIGINT;
UPDATE vote_history vh SET vote_id_new = v.id FROM votes v WHERE vh.vote_id = v.natural_key;
ALTER TABLE vote_history DROP COLUMN vote_id;
ALTER TABLE vote_history RENAME COLUMN vote_id_new TO vote_id;

-- vote_history_positions.member_id TEXT -> BIGINT (LEFT JOIN for orphans)
ALTER TABLE vote_history_positions ADD COLUMN member_id_new BIGINT;
UPDATE vote_history_positions vhp SET member_id_new = m.id FROM members m WHERE vhp.member_id = m.natural_key;
ALTER TABLE vote_history_positions DROP COLUMN member_id;
ALTER TABLE vote_history_positions RENAME COLUMN member_id_new TO member_id;

-- member_history.member_id TEXT -> BIGINT (LEFT JOIN for orphans)
ALTER TABLE member_history ADD COLUMN member_id_new BIGINT;
UPDATE member_history mh SET member_id_new = m.id FROM members m WHERE mh.member_id = m.natural_key;
ALTER TABLE member_history DROP COLUMN member_id;
ALTER TABLE member_history RENAME COLUMN member_id_new TO member_id;

-- member_term_history.member_id TEXT -> BIGINT (LEFT JOIN for orphans)
ALTER TABLE member_term_history ADD COLUMN member_id_new BIGINT;
UPDATE member_term_history mth SET member_id_new = m.id FROM members m WHERE mth.member_id = m.natural_key;
ALTER TABLE member_term_history DROP COLUMN member_id;
ALTER TABLE member_term_history RENAME COLUMN member_id_new TO member_id;

-- bill_history.sponsor_bioguide_id TEXT -> sponsor_member_id BIGINT
ALTER TABLE bill_history ADD COLUMN sponsor_member_id BIGINT;
UPDATE bill_history bh SET sponsor_member_id = m.id FROM members m WHERE bh.sponsor_bioguide_id = m.natural_key;
ALTER TABLE bill_history DROP COLUMN sponsor_bioguide_id;

-- bill_cosponsor_history.member_id TEXT -> BIGINT (LEFT JOIN for orphans)
ALTER TABLE bill_cosponsor_history ADD COLUMN member_id_new BIGINT;
UPDATE bill_cosponsor_history bch SET member_id_new = m.id FROM members m WHERE bch.member_id = m.natural_key;
ALTER TABLE bill_cosponsor_history DROP COLUMN member_id;
ALTER TABLE bill_cosponsor_history RENAME COLUMN member_id_new TO member_id;

-- vote_history.amendment_id TEXT -> BIGINT (LEFT JOIN for orphans, nullable)
ALTER TABLE vote_history ADD COLUMN amendment_id_new BIGINT;
UPDATE vote_history vh SET amendment_id_new = a.id FROM amendments a WHERE vh.amendment_id = a.natural_key;
ALTER TABLE vote_history DROP COLUMN amendment_id;
ALTER TABLE vote_history RENAME COLUMN amendment_id_new TO amendment_id;

-- ===========================================================================
-- SECTION 5: Drop old PKs, promote new id as PK on TEXT PK tables
-- ===========================================================================

-- 5a. members
ALTER TABLE members DROP CONSTRAINT members_pkey;
ALTER TABLE members ADD CONSTRAINT members_pkey PRIMARY KEY (id);
ALTER TABLE members ADD CONSTRAINT uq_members_natural_key UNIQUE (natural_key);
ALTER TABLE members ALTER COLUMN natural_key SET NOT NULL;

-- 5b. votes
ALTER TABLE votes DROP CONSTRAINT votes_pkey;
ALTER TABLE votes ADD CONSTRAINT votes_pkey PRIMARY KEY (id);
ALTER TABLE votes ADD CONSTRAINT uq_votes_natural_key_pk UNIQUE (natural_key);
ALTER TABLE votes ALTER COLUMN natural_key SET NOT NULL;

-- 5c. amendments
ALTER TABLE amendments DROP CONSTRAINT amendments_pkey;
ALTER TABLE amendments ADD CONSTRAINT amendments_pkey PRIMARY KEY (id);
ALTER TABLE amendments ADD CONSTRAINT uq_amendments_natural_key_pk UNIQUE (natural_key);
ALTER TABLE amendments ALTER COLUMN natural_key SET NOT NULL;

-- 5d. committees
ALTER TABLE committees DROP CONSTRAINT committees_pkey;
ALTER TABLE committees ADD CONSTRAINT committees_pkey PRIMARY KEY (id);
ALTER TABLE committees ADD CONSTRAINT uq_committees_natural_key UNIQUE (natural_key);
ALTER TABLE committees ALTER COLUMN natural_key SET NOT NULL;

-- 5e. qa_questions
ALTER TABLE qa_questions DROP CONSTRAINT qa_questions_pkey;
ALTER TABLE qa_questions ADD CONSTRAINT qa_questions_pkey PRIMARY KEY (id);
ALTER TABLE qa_questions ADD CONSTRAINT uq_qa_questions_natural_key UNIQUE (natural_key);
ALTER TABLE qa_questions ALTER COLUMN natural_key SET NOT NULL;

-- 5f. finding_types: drop old SERIAL PK, promote id BIGSERIAL
ALTER TABLE finding_types DROP CONSTRAINT finding_types_pkey;
ALTER TABLE finding_types DROP COLUMN finding_type_id;
ALTER TABLE finding_types ADD CONSTRAINT finding_types_pkey PRIMARY KEY (id);

-- ===========================================================================
-- SECTION 6: Handle UUID PK tables -> id BIGSERIAL
-- ===========================================================================
-- For each UUID PK table: add id BIGSERIAL, convert all FK references,
-- drop old UUID PK, promote id as PK.

-- -----------------------------------------------------------------------
-- 6a. bill_text_versions
-- -----------------------------------------------------------------------
ALTER TABLE bill_text_versions ADD COLUMN id BIGSERIAL;

-- Convert bills.latest_text_version_id UUID -> BIGINT
ALTER TABLE bills ADD COLUMN latest_text_version_id_new BIGINT;
UPDATE bills b SET latest_text_version_id_new = btv.id FROM bill_text_versions btv WHERE b.latest_text_version_id = btv.version_id;
ALTER TABLE bills DROP COLUMN latest_text_version_id;
ALTER TABLE bills RENAME COLUMN latest_text_version_id_new TO latest_text_version_id;

-- Convert bill_text_sections.version_id UUID -> BIGINT
ALTER TABLE bill_text_sections ADD COLUMN version_id_new BIGINT;
UPDATE bill_text_sections bts SET version_id_new = btv.id FROM bill_text_versions btv WHERE bts.version_id = btv.version_id;
ALTER TABLE bill_text_sections DROP COLUMN version_id;
ALTER TABLE bill_text_sections RENAME COLUMN version_id_new TO version_id;
ALTER TABLE bill_text_sections ALTER COLUMN version_id SET NOT NULL;

-- Convert bill_concept_groups.version_id UUID -> BIGINT
ALTER TABLE bill_concept_groups ADD COLUMN version_id_new BIGINT;
UPDATE bill_concept_groups bcg SET version_id_new = btv.id FROM bill_text_versions btv WHERE bcg.version_id = btv.version_id;
ALTER TABLE bill_concept_groups DROP COLUMN version_id;
ALTER TABLE bill_concept_groups RENAME COLUMN version_id_new TO version_id;
ALTER TABLE bill_concept_groups ALTER COLUMN version_id SET NOT NULL;

-- Convert bill_analyses.version_id UUID -> BIGINT (nullable)
ALTER TABLE bill_analyses ADD COLUMN version_id_new BIGINT;
UPDATE bill_analyses ba SET version_id_new = btv.id FROM bill_text_versions btv WHERE ba.version_id = btv.version_id;
ALTER TABLE bill_analyses DROP COLUMN version_id;
ALTER TABLE bill_analyses RENAME COLUMN version_id_new TO version_id;

-- Drop old UUID PK, promote id
ALTER TABLE bill_text_versions DROP CONSTRAINT bill_text_versions_pkey;
ALTER TABLE bill_text_versions DROP COLUMN version_id;
ALTER TABLE bill_text_versions ADD CONSTRAINT bill_text_versions_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6b. bill_text_sections
-- -----------------------------------------------------------------------
ALTER TABLE bill_text_sections ADD COLUMN id BIGSERIAL;

-- Convert bill_concept_group_sections.section_id UUID -> BIGINT
ALTER TABLE bill_concept_group_sections ADD COLUMN section_id_new BIGINT;
UPDATE bill_concept_group_sections bcgs SET section_id_new = bts.id FROM bill_text_sections bts WHERE bcgs.section_id = bts.section_id;
ALTER TABLE bill_concept_group_sections DROP COLUMN section_id;
ALTER TABLE bill_concept_group_sections RENAME COLUMN section_id_new TO section_id;
ALTER TABLE bill_concept_group_sections ALTER COLUMN section_id SET NOT NULL;

-- Drop old UUID PK, promote id
ALTER TABLE bill_text_sections DROP CONSTRAINT bill_text_sections_pkey;
ALTER TABLE bill_text_sections DROP COLUMN section_id;
ALTER TABLE bill_text_sections ADD CONSTRAINT bill_text_sections_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6c. bill_concept_groups
-- -----------------------------------------------------------------------
ALTER TABLE bill_concept_groups ADD COLUMN id BIGSERIAL;

-- Convert bill_concept_group_sections.concept_group_id UUID -> BIGINT
ALTER TABLE bill_concept_group_sections ADD COLUMN concept_group_id_new BIGINT;
UPDATE bill_concept_group_sections bcgs SET concept_group_id_new = bcg.id FROM bill_concept_groups bcg WHERE bcgs.concept_group_id = bcg.concept_group_id;
ALTER TABLE bill_concept_group_sections DROP COLUMN concept_group_id;
ALTER TABLE bill_concept_group_sections RENAME COLUMN concept_group_id_new TO concept_group_id;
ALTER TABLE bill_concept_group_sections ALTER COLUMN concept_group_id SET NOT NULL;

-- Convert bill_concept_summaries.concept_group_id UUID -> BIGINT (nullable)
ALTER TABLE bill_concept_summaries ADD COLUMN concept_group_id_new BIGINT;
UPDATE bill_concept_summaries bcs SET concept_group_id_new = bcg.id FROM bill_concept_groups bcg WHERE bcs.concept_group_id = bcg.concept_group_id;
ALTER TABLE bill_concept_summaries DROP COLUMN concept_group_id;
ALTER TABLE bill_concept_summaries RENAME COLUMN concept_group_id_new TO concept_group_id;

-- Convert bill_fiscal_estimates.concept_group_id UUID -> BIGINT (nullable)
ALTER TABLE bill_fiscal_estimates ADD COLUMN concept_group_id_new BIGINT;
UPDATE bill_fiscal_estimates bfe SET concept_group_id_new = bcg.id FROM bill_concept_groups bcg WHERE bfe.concept_group_id = bcg.concept_group_id;
ALTER TABLE bill_fiscal_estimates DROP COLUMN concept_group_id;
ALTER TABLE bill_fiscal_estimates RENAME COLUMN concept_group_id_new TO concept_group_id;

-- Drop old UUID PK, promote id
ALTER TABLE bill_concept_groups DROP CONSTRAINT bill_concept_groups_pkey;
ALTER TABLE bill_concept_groups DROP COLUMN concept_group_id;
ALTER TABLE bill_concept_groups ADD CONSTRAINT bill_concept_groups_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6d. bill_analyses
-- -----------------------------------------------------------------------
ALTER TABLE bill_analyses ADD COLUMN id BIGSERIAL;

-- Convert bill_concept_summaries.analysis_id UUID -> BIGINT
ALTER TABLE bill_concept_summaries ADD COLUMN analysis_id_new BIGINT;
UPDATE bill_concept_summaries bcs SET analysis_id_new = ba.id FROM bill_analyses ba WHERE bcs.analysis_id = ba.analysis_id;
ALTER TABLE bill_concept_summaries DROP COLUMN analysis_id;
ALTER TABLE bill_concept_summaries RENAME COLUMN analysis_id_new TO analysis_id;
ALTER TABLE bill_concept_summaries ALTER COLUMN analysis_id SET NOT NULL;

-- Convert bill_analysis_topics.analysis_id UUID -> BIGINT
ALTER TABLE bill_analysis_topics ADD COLUMN analysis_id_new BIGINT;
UPDATE bill_analysis_topics bat SET analysis_id_new = ba.id FROM bill_analyses ba WHERE bat.analysis_id = ba.analysis_id;
ALTER TABLE bill_analysis_topics DROP COLUMN analysis_id;
ALTER TABLE bill_analysis_topics RENAME COLUMN analysis_id_new TO analysis_id;
ALTER TABLE bill_analysis_topics ALTER COLUMN analysis_id SET NOT NULL;

-- Convert bill_fiscal_estimates.analysis_id UUID -> BIGINT
ALTER TABLE bill_fiscal_estimates ADD COLUMN analysis_id_new BIGINT;
UPDATE bill_fiscal_estimates bfe SET analysis_id_new = ba.id FROM bill_analyses ba WHERE bfe.analysis_id = ba.analysis_id;
ALTER TABLE bill_fiscal_estimates DROP COLUMN analysis_id;
ALTER TABLE bill_fiscal_estimates RENAME COLUMN analysis_id_new TO analysis_id;
ALTER TABLE bill_fiscal_estimates ALTER COLUMN analysis_id SET NOT NULL;

-- Convert bill_findings.analysis_id UUID -> BIGINT (nullable)
ALTER TABLE bill_findings ADD COLUMN analysis_id_new BIGINT;
UPDATE bill_findings bf SET analysis_id_new = ba.id FROM bill_analyses ba WHERE bf.analysis_id = ba.analysis_id;
ALTER TABLE bill_findings DROP COLUMN analysis_id;
ALTER TABLE bill_findings RENAME COLUMN analysis_id_new TO analysis_id;

-- Drop old UUID PK, promote id
ALTER TABLE bill_analyses DROP CONSTRAINT bill_analyses_pkey;
ALTER TABLE bill_analyses DROP COLUMN analysis_id;
ALTER TABLE bill_analyses ADD CONSTRAINT bill_analyses_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6e. bill_findings
-- -----------------------------------------------------------------------
ALTER TABLE bill_findings ADD COLUMN id BIGSERIAL;

-- Convert member_bill_stance_topics.finding_id UUID -> BIGINT (nullable)
ALTER TABLE member_bill_stance_topics ADD COLUMN finding_id_new BIGINT;
UPDATE member_bill_stance_topics mbst SET finding_id_new = bf.id FROM bill_findings bf WHERE mbst.finding_id = bf.finding_id;
ALTER TABLE member_bill_stance_topics DROP COLUMN finding_id;
ALTER TABLE member_bill_stance_topics RENAME COLUMN finding_id_new TO finding_id;

-- Convert user_bill_alignments.finding_id UUID -> BIGINT (nullable)
ALTER TABLE user_bill_alignments ADD COLUMN finding_id_new BIGINT;
UPDATE user_bill_alignments uba SET finding_id_new = bf.id FROM bill_findings bf WHERE uba.finding_id = bf.finding_id;
ALTER TABLE user_bill_alignments DROP COLUMN finding_id;
ALTER TABLE user_bill_alignments RENAME COLUMN finding_id_new TO finding_id;

-- Drop old UUID PK, promote id
ALTER TABLE bill_findings DROP CONSTRAINT bill_findings_pkey;
ALTER TABLE bill_findings DROP COLUMN finding_id;
ALTER TABLE bill_findings ADD CONSTRAINT bill_findings_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6f. bill_concept_summaries
-- -----------------------------------------------------------------------
ALTER TABLE bill_concept_summaries ADD COLUMN id BIGSERIAL;
ALTER TABLE bill_concept_summaries DROP CONSTRAINT bill_concept_summaries_pkey;
ALTER TABLE bill_concept_summaries DROP COLUMN concept_summary_id;
ALTER TABLE bill_concept_summaries ADD CONSTRAINT bill_concept_summaries_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6g. bill_analysis_topics
-- -----------------------------------------------------------------------
ALTER TABLE bill_analysis_topics ADD COLUMN id BIGSERIAL;
ALTER TABLE bill_analysis_topics DROP CONSTRAINT bill_analysis_topics_pkey;
ALTER TABLE bill_analysis_topics DROP COLUMN topic_id;
ALTER TABLE bill_analysis_topics ADD CONSTRAINT bill_analysis_topics_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6h. bill_fiscal_estimates
-- -----------------------------------------------------------------------
ALTER TABLE bill_fiscal_estimates ADD COLUMN id BIGSERIAL;
ALTER TABLE bill_fiscal_estimates DROP CONSTRAINT bill_fiscal_estimates_pkey;
ALTER TABLE bill_fiscal_estimates DROP COLUMN fiscal_estimate_id;
ALTER TABLE bill_fiscal_estimates ADD CONSTRAINT bill_fiscal_estimates_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6i. amendment_findings
-- -----------------------------------------------------------------------
ALTER TABLE amendment_findings ADD COLUMN id BIGSERIAL;

-- Convert user_amendment_alignments.finding_id UUID -> BIGINT (nullable)
ALTER TABLE user_amendment_alignments ADD COLUMN finding_id_new BIGINT;
UPDATE user_amendment_alignments uaa SET finding_id_new = af.id FROM amendment_findings af WHERE uaa.finding_id = af.finding_id;
ALTER TABLE user_amendment_alignments DROP COLUMN finding_id;
ALTER TABLE user_amendment_alignments RENAME COLUMN finding_id_new TO finding_id;

-- Drop old UUID PK, promote id
ALTER TABLE amendment_findings DROP CONSTRAINT amendment_findings_pkey;
ALTER TABLE amendment_findings DROP COLUMN finding_id;
ALTER TABLE amendment_findings ADD CONSTRAINT amendment_findings_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6j. amendment_analyses
-- -----------------------------------------------------------------------
ALTER TABLE amendment_analyses ADD COLUMN id BIGSERIAL;

-- Convert amendment_concept_summaries.analysis_id UUID -> BIGINT
ALTER TABLE amendment_concept_summaries ADD COLUMN analysis_id_new BIGINT;
UPDATE amendment_concept_summaries acs SET analysis_id_new = aa.id FROM amendment_analyses aa WHERE acs.analysis_id = aa.analysis_id;
ALTER TABLE amendment_concept_summaries DROP COLUMN analysis_id;
ALTER TABLE amendment_concept_summaries RENAME COLUMN analysis_id_new TO analysis_id;
ALTER TABLE amendment_concept_summaries ALTER COLUMN analysis_id SET NOT NULL;

-- Convert amendment_analysis_topics.analysis_id UUID -> BIGINT
ALTER TABLE amendment_analysis_topics ADD COLUMN analysis_id_new BIGINT;
UPDATE amendment_analysis_topics aat SET analysis_id_new = aa.id FROM amendment_analyses aa WHERE aat.analysis_id = aa.analysis_id;
ALTER TABLE amendment_analysis_topics DROP COLUMN analysis_id;
ALTER TABLE amendment_analysis_topics RENAME COLUMN analysis_id_new TO analysis_id;
ALTER TABLE amendment_analysis_topics ALTER COLUMN analysis_id SET NOT NULL;

-- Convert amendment_findings.analysis_id UUID -> BIGINT (nullable)
ALTER TABLE amendment_findings ADD COLUMN analysis_id_new BIGINT;
UPDATE amendment_findings af SET analysis_id_new = aa.id FROM amendment_analyses aa WHERE af.analysis_id = aa.analysis_id;
ALTER TABLE amendment_findings DROP COLUMN analysis_id;
ALTER TABLE amendment_findings RENAME COLUMN analysis_id_new TO analysis_id;

-- Drop old UUID PK, promote id
ALTER TABLE amendment_analyses DROP CONSTRAINT amendment_analyses_pkey;
ALTER TABLE amendment_analyses DROP COLUMN analysis_id;
ALTER TABLE amendment_analyses ADD CONSTRAINT amendment_analyses_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6k. amendment_concept_summaries
-- -----------------------------------------------------------------------
ALTER TABLE amendment_concept_summaries ADD COLUMN id BIGSERIAL;
ALTER TABLE amendment_concept_summaries DROP CONSTRAINT amendment_concept_summaries_pkey;
ALTER TABLE amendment_concept_summaries DROP COLUMN concept_summary_id;
ALTER TABLE amendment_concept_summaries ADD CONSTRAINT amendment_concept_summaries_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6l. amendment_analysis_topics
-- -----------------------------------------------------------------------
ALTER TABLE amendment_analysis_topics ADD COLUMN id BIGSERIAL;
ALTER TABLE amendment_analysis_topics DROP CONSTRAINT amendment_analysis_topics_pkey;
ALTER TABLE amendment_analysis_topics DROP COLUMN topic_id;
ALTER TABLE amendment_analysis_topics ADD CONSTRAINT amendment_analysis_topics_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6m. amendment_text_versions
-- -----------------------------------------------------------------------
ALTER TABLE amendment_text_versions ADD COLUMN id BIGSERIAL;

-- Convert amendments.latest_text_version_id UUID -> BIGINT
ALTER TABLE amendments ADD COLUMN latest_text_version_id_new BIGINT;
UPDATE amendments a SET latest_text_version_id_new = atv.id FROM amendment_text_versions atv WHERE a.latest_text_version_id = atv.version_id;
ALTER TABLE amendments DROP COLUMN latest_text_version_id;
ALTER TABLE amendments RENAME COLUMN latest_text_version_id_new TO latest_text_version_id;

-- Drop old UUID PK, promote id
ALTER TABLE amendment_text_versions DROP CONSTRAINT amendment_text_versions_pkey;
ALTER TABLE amendment_text_versions DROP COLUMN version_id;
ALTER TABLE amendment_text_versions ADD CONSTRAINT amendment_text_versions_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6n. vote_history
-- -----------------------------------------------------------------------
ALTER TABLE vote_history ADD COLUMN id BIGSERIAL;

-- Convert vote_history_positions.history_id UUID -> BIGINT
ALTER TABLE vote_history_positions ADD COLUMN history_id_new BIGINT;
UPDATE vote_history_positions vhp SET history_id_new = vh.id FROM vote_history vh WHERE vhp.history_id = vh.history_id;
ALTER TABLE vote_history_positions DROP COLUMN history_id;
ALTER TABLE vote_history_positions RENAME COLUMN history_id_new TO history_id;

-- Drop old UUID PK, promote id
ALTER TABLE vote_history DROP CONSTRAINT vote_history_pkey;
ALTER TABLE vote_history DROP COLUMN history_id;
ALTER TABLE vote_history ADD CONSTRAINT vote_history_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6o. member_history
-- -----------------------------------------------------------------------
ALTER TABLE member_history ADD COLUMN id BIGSERIAL;

-- Convert member_term_history.history_id UUID -> BIGINT
ALTER TABLE member_term_history ADD COLUMN history_id_new BIGINT;
UPDATE member_term_history mth SET history_id_new = mh.id FROM member_history mh WHERE mth.history_id = mh.history_id;
ALTER TABLE member_term_history DROP COLUMN history_id;
ALTER TABLE member_term_history RENAME COLUMN history_id_new TO history_id;

-- Drop old UUID PK, promote id
ALTER TABLE member_history DROP CONSTRAINT member_history_pkey;
ALTER TABLE member_history DROP COLUMN history_id;
ALTER TABLE member_history ADD CONSTRAINT member_history_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6p. bill_history
-- -----------------------------------------------------------------------
ALTER TABLE bill_history ADD COLUMN id BIGSERIAL;

-- Convert bill_cosponsor_history.history_id UUID -> BIGINT
ALTER TABLE bill_cosponsor_history ADD COLUMN history_id_new BIGINT;
UPDATE bill_cosponsor_history bch SET history_id_new = bh.id FROM bill_history bh WHERE bch.history_id = bh.history_id;
ALTER TABLE bill_cosponsor_history DROP COLUMN history_id;
ALTER TABLE bill_cosponsor_history RENAME COLUMN history_id_new TO history_id;

-- Convert bill_subject_history.history_id UUID -> BIGINT
ALTER TABLE bill_subject_history ADD COLUMN history_id_new BIGINT;
UPDATE bill_subject_history bsh SET history_id_new = bh.id FROM bill_history bh WHERE bsh.history_id = bh.history_id;
ALTER TABLE bill_subject_history DROP COLUMN history_id;
ALTER TABLE bill_subject_history RENAME COLUMN history_id_new TO history_id;

-- Drop old UUID PK, promote id
ALTER TABLE bill_history DROP CONSTRAINT bill_history_pkey;
ALTER TABLE bill_history DROP COLUMN history_id;
ALTER TABLE bill_history ADD CONSTRAINT bill_history_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6q. member_terms
-- -----------------------------------------------------------------------
ALTER TABLE member_terms ADD COLUMN id BIGSERIAL;
ALTER TABLE member_terms DROP CONSTRAINT member_terms_pkey;
ALTER TABLE member_terms DROP COLUMN term_id;
ALTER TABLE member_terms ADD CONSTRAINT member_terms_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6r. member_party_history
-- -----------------------------------------------------------------------
ALTER TABLE member_party_history ADD COLUMN id BIGSERIAL;
ALTER TABLE member_party_history DROP CONSTRAINT member_party_history_pkey;
ALTER TABLE member_party_history DROP COLUMN party_history_id;
ALTER TABLE member_party_history ADD CONSTRAINT member_party_history_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6s. workflow_runs
-- -----------------------------------------------------------------------
ALTER TABLE workflow_runs ADD COLUMN id BIGSERIAL;

-- Convert workflow_run_steps.workflow_run_id UUID -> BIGINT
ALTER TABLE workflow_run_steps ADD COLUMN workflow_run_id_new BIGINT;
UPDATE workflow_run_steps wrs SET workflow_run_id_new = wr.id FROM workflow_runs wr WHERE wrs.workflow_run_id = wr.workflow_run_id;
ALTER TABLE workflow_run_steps DROP COLUMN workflow_run_id;
ALTER TABLE workflow_run_steps RENAME COLUMN workflow_run_id_new TO workflow_run_id;
ALTER TABLE workflow_run_steps ALTER COLUMN workflow_run_id SET NOT NULL;

-- Drop old UUID PK, promote id
ALTER TABLE workflow_runs DROP CONSTRAINT workflow_runs_pkey;
ALTER TABLE workflow_runs DROP COLUMN workflow_run_id;
ALTER TABLE workflow_runs ADD CONSTRAINT workflow_runs_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6t. pipeline_runs + workflow_run_steps + processing_results
--     These three are interleaved because:
--     - workflow_run_steps.pipeline_run_id needs both pr.id (new) and pr.run_id (old)
--     - processing_results.run_id needs both plr.id (new) and plr.run_id (old)
--     So we add pipeline_runs.id first, convert all FK references while run_id still
--     exists, then drop run_id last.
-- -----------------------------------------------------------------------

-- Step 1: Add the new BIGSERIAL id to pipeline_runs (old run_id UUID still present)
ALTER TABLE pipeline_runs ADD COLUMN id BIGSERIAL;

-- Step 2: Convert workflow_run_steps.pipeline_run_id UUID -> BIGINT
--         (needs pr.id AND pr.run_id — both exist at this point)
ALTER TABLE workflow_run_steps ADD COLUMN id BIGSERIAL;
ALTER TABLE workflow_run_steps ADD COLUMN pipeline_run_id_new BIGINT;
UPDATE workflow_run_steps wrs SET pipeline_run_id_new = pr.id FROM pipeline_runs pr WHERE wrs.pipeline_run_id = pr.run_id;
ALTER TABLE workflow_run_steps DROP COLUMN pipeline_run_id;
ALTER TABLE workflow_run_steps RENAME COLUMN pipeline_run_id_new TO pipeline_run_id;

-- Drop old composite PK, promote id
ALTER TABLE workflow_run_steps DROP CONSTRAINT workflow_run_steps_pkey;
ALTER TABLE workflow_run_steps DROP COLUMN step_id;
ALTER TABLE workflow_run_steps ADD CONSTRAINT workflow_run_steps_pkey PRIMARY KEY (id);

-- Step 3: Convert processing_results.run_id UUID -> BIGINT
--         (needs plr.id AND plr.run_id — both still exist)
ALTER TABLE processing_results ADD COLUMN run_id_new BIGINT;
UPDATE processing_results pr SET run_id_new = plr.id FROM pipeline_runs plr WHERE pr.run_id = plr.run_id;
ALTER TABLE processing_results DROP COLUMN run_id;
ALTER TABLE processing_results RENAME COLUMN run_id_new TO run_id;
ALTER TABLE processing_results ALTER COLUMN run_id SET NOT NULL;

-- Step 4: Now safe to drop pipeline_runs.run_id — all references converted
ALTER TABLE pipeline_runs DROP CONSTRAINT pipeline_runs_pkey;
ALTER TABLE pipeline_runs DROP COLUMN run_id;
ALTER TABLE pipeline_runs ADD CONSTRAINT pipeline_runs_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6v. processing_results
-- -----------------------------------------------------------------------
ALTER TABLE processing_results ADD COLUMN id BIGSERIAL;
ALTER TABLE processing_results DROP CONSTRAINT processing_results_pkey;
ALTER TABLE processing_results DROP COLUMN result_id;
ALTER TABLE processing_results ADD CONSTRAINT processing_results_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6w. user_preferences
-- -----------------------------------------------------------------------
ALTER TABLE user_preferences ADD COLUMN id BIGSERIAL;
ALTER TABLE user_preferences DROP CONSTRAINT user_preferences_pkey;
ALTER TABLE user_preferences DROP COLUMN preference_id;
ALTER TABLE user_preferences ADD CONSTRAINT user_preferences_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6x. score_history
-- -----------------------------------------------------------------------
ALTER TABLE score_history ADD COLUMN id BIGSERIAL;

-- Convert score_history_congress.score_id UUID -> BIGINT
ALTER TABLE score_history_congress ADD COLUMN score_id_new BIGINT;
UPDATE score_history_congress shc SET score_id_new = sh.id FROM score_history sh WHERE shc.score_id = sh.score_id;
ALTER TABLE score_history_congress DROP COLUMN score_id;
ALTER TABLE score_history_congress RENAME COLUMN score_id_new TO score_id;

-- Convert score_history_congress_topics.score_id UUID -> BIGINT
ALTER TABLE score_history_congress_topics ADD COLUMN score_id_new BIGINT;
UPDATE score_history_congress_topics shct SET score_id_new = sh.id FROM score_history sh WHERE shct.score_id = sh.score_id;
ALTER TABLE score_history_congress_topics DROP COLUMN score_id;
ALTER TABLE score_history_congress_topics RENAME COLUMN score_id_new TO score_id;

-- Convert score_history_highlights.score_id UUID -> BIGINT
ALTER TABLE score_history_highlights ADD COLUMN score_id_new BIGINT;
UPDATE score_history_highlights shh SET score_id_new = sh.id FROM score_history sh WHERE shh.score_id = sh.score_id;
ALTER TABLE score_history_highlights DROP COLUMN score_id;
ALTER TABLE score_history_highlights RENAME COLUMN score_id_new TO score_id;

-- Drop old UUID PK, promote id
ALTER TABLE score_history DROP CONSTRAINT score_history_pkey;
ALTER TABLE score_history DROP COLUMN score_id;
ALTER TABLE score_history ADD CONSTRAINT score_history_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6y. qa_user_responses
-- -----------------------------------------------------------------------
ALTER TABLE qa_user_responses ADD COLUMN id BIGSERIAL;
ALTER TABLE qa_user_responses DROP CONSTRAINT qa_user_responses_pkey;
ALTER TABLE qa_user_responses DROP COLUMN response_id;
ALTER TABLE qa_user_responses ADD CONSTRAINT qa_user_responses_pkey PRIMARY KEY (id);

-- -----------------------------------------------------------------------
-- 6z. member_bill_stance_topics (already has UUID id, convert to BIGSERIAL)
-- -----------------------------------------------------------------------
ALTER TABLE member_bill_stance_topics ADD COLUMN id_new BIGSERIAL;
ALTER TABLE member_bill_stance_topics DROP CONSTRAINT member_bill_stance_topics_pkey;
ALTER TABLE member_bill_stance_topics DROP COLUMN id;
ALTER TABLE member_bill_stance_topics RENAME COLUMN id_new TO id;
ALTER TABLE member_bill_stance_topics ADD CONSTRAINT member_bill_stance_topics_pkey PRIMARY KEY (id);

-- ===========================================================================
-- SECTION 7: Add id BIGSERIAL to composite PK tables
-- ===========================================================================

-- NOTE: Many composite PK tables had a column dropped/re-added during the FK conversion
-- in section 4. Dropping a column that is part of a composite PK implicitly destroys
-- the PK constraint, so we use DROP CONSTRAINT IF EXISTS throughout.

-- 7a. bill_cosponsors (bill_id BIGINT, member_id BIGINT)
ALTER TABLE bill_cosponsors ADD COLUMN id BIGSERIAL;
ALTER TABLE bill_cosponsors DROP CONSTRAINT IF EXISTS bill_cosponsors_pkey;
ALTER TABLE bill_cosponsors ADD CONSTRAINT bill_cosponsors_pkey PRIMARY KEY (id);
ALTER TABLE bill_cosponsors ADD CONSTRAINT uq_bill_cosponsors UNIQUE (bill_id, member_id);

-- 7b. bill_subjects (bill_id BIGINT, subject_name TEXT)
ALTER TABLE bill_subjects ADD COLUMN id BIGSERIAL;
ALTER TABLE bill_subjects DROP CONSTRAINT IF EXISTS bill_subjects_pkey;
ALTER TABLE bill_subjects ADD CONSTRAINT bill_subjects_pkey PRIMARY KEY (id);
ALTER TABLE bill_subjects ADD CONSTRAINT uq_bill_subjects UNIQUE (bill_id, subject_name);

-- 7c. vote_positions (vote_id BIGINT, member_id BIGINT)
ALTER TABLE vote_positions ADD COLUMN id BIGSERIAL;
ALTER TABLE vote_positions DROP CONSTRAINT IF EXISTS vote_positions_pkey;
ALTER TABLE vote_positions ADD CONSTRAINT vote_positions_pkey PRIMARY KEY (id);
ALTER TABLE vote_positions ADD CONSTRAINT uq_vote_positions UNIQUE (vote_id, member_id);

-- 7d. vote_history_positions (history_id BIGINT, member_id BIGINT) -- no FKs
ALTER TABLE vote_history_positions ADD COLUMN id BIGSERIAL;
ALTER TABLE vote_history_positions DROP CONSTRAINT IF EXISTS vote_history_positions_pkey;
ALTER TABLE vote_history_positions ADD CONSTRAINT vote_history_positions_pkey PRIMARY KEY (id);
ALTER TABLE vote_history_positions ADD CONSTRAINT uq_vote_history_positions UNIQUE (history_id, member_id);

-- 7e. member_term_history (history_id BIGINT, member_id BIGINT, chamber TEXT, start_year INT)
ALTER TABLE member_term_history ADD COLUMN id BIGSERIAL;
ALTER TABLE member_term_history DROP CONSTRAINT IF EXISTS member_term_history_pkey;
ALTER TABLE member_term_history ADD CONSTRAINT member_term_history_pkey PRIMARY KEY (id);
ALTER TABLE member_term_history ADD CONSTRAINT uq_member_term_history UNIQUE (history_id, member_id, chamber, start_year);

-- 7f. bill_cosponsor_history (history_id BIGINT, bill_id BIGINT, member_id BIGINT)
ALTER TABLE bill_cosponsor_history ADD COLUMN id BIGSERIAL;
ALTER TABLE bill_cosponsor_history DROP CONSTRAINT IF EXISTS bill_cosponsor_history_pkey;
ALTER TABLE bill_cosponsor_history ADD CONSTRAINT bill_cosponsor_history_pkey PRIMARY KEY (id);
ALTER TABLE bill_cosponsor_history ADD CONSTRAINT uq_bill_cosponsor_history UNIQUE (history_id, bill_id, member_id);

-- 7g. bill_subject_history (history_id BIGINT, bill_id BIGINT, subject_name TEXT)
ALTER TABLE bill_subject_history ADD COLUMN id BIGSERIAL;
ALTER TABLE bill_subject_history DROP CONSTRAINT IF EXISTS bill_subject_history_pkey;
ALTER TABLE bill_subject_history ADD CONSTRAINT bill_subject_history_pkey PRIMARY KEY (id);
ALTER TABLE bill_subject_history ADD CONSTRAINT uq_bill_subject_history UNIQUE (history_id, bill_id, subject_name);

-- 7h. bill_concept_group_sections (concept_group_id BIGINT, section_id BIGINT)
ALTER TABLE bill_concept_group_sections ADD COLUMN id BIGSERIAL;
ALTER TABLE bill_concept_group_sections DROP CONSTRAINT IF EXISTS bill_concept_group_sections_pkey;
ALTER TABLE bill_concept_group_sections ADD CONSTRAINT bill_concept_group_sections_pkey PRIMARY KEY (id);
ALTER TABLE bill_concept_group_sections ADD CONSTRAINT uq_bill_concept_group_sections UNIQUE (concept_group_id, section_id);

-- 7i. committee_members (committee_id BIGINT, member_id BIGINT)
ALTER TABLE committee_members ADD COLUMN id BIGSERIAL;
ALTER TABLE committee_members DROP CONSTRAINT IF EXISTS committee_members_pkey;
ALTER TABLE committee_members ADD CONSTRAINT committee_members_pkey PRIMARY KEY (id);
ALTER TABLE committee_members ADD CONSTRAINT uq_committee_members UNIQUE (committee_id, member_id);

-- 7j. bill_committee_referrals (bill_id BIGINT, committee_id BIGINT)
ALTER TABLE bill_committee_referrals ADD COLUMN id BIGSERIAL;
ALTER TABLE bill_committee_referrals DROP CONSTRAINT IF EXISTS bill_committee_referrals_pkey;
ALTER TABLE bill_committee_referrals ADD CONSTRAINT bill_committee_referrals_pkey PRIMARY KEY (id);
ALTER TABLE bill_committee_referrals ADD CONSTRAINT uq_bill_committee_referrals UNIQUE (bill_id, committee_id);

-- 7k. qa_question_topics (question_id BIGINT, topic TEXT)
ALTER TABLE qa_question_topics ADD COLUMN id BIGSERIAL;
ALTER TABLE qa_question_topics DROP CONSTRAINT IF EXISTS qa_question_topics_pkey;
ALTER TABLE qa_question_topics ADD CONSTRAINT qa_question_topics_pkey PRIMARY KEY (id);
ALTER TABLE qa_question_topics ADD CONSTRAINT uq_qa_question_topics UNIQUE (question_id, topic);

-- 7l. qa_answer_options (question_id BIGINT, option_value TEXT)
ALTER TABLE qa_answer_options ADD COLUMN id BIGSERIAL;
ALTER TABLE qa_answer_options DROP CONSTRAINT IF EXISTS qa_answer_options_pkey;
ALTER TABLE qa_answer_options ADD CONSTRAINT qa_answer_options_pkey PRIMARY KEY (id);
ALTER TABLE qa_answer_options ADD CONSTRAINT uq_qa_answer_options UNIQUE (question_id, option_value);

-- 7m. scores (user_id UUID, member_id BIGINT)
ALTER TABLE scores ADD COLUMN id BIGSERIAL;
ALTER TABLE scores DROP CONSTRAINT IF EXISTS scores_pkey;
ALTER TABLE scores ADD CONSTRAINT scores_pkey PRIMARY KEY (id);
ALTER TABLE scores ADD CONSTRAINT uq_scores UNIQUE (user_id, member_id);

-- 7n. score_topics (user_id UUID, member_id BIGINT, topic TEXT)
ALTER TABLE score_topics ADD COLUMN id BIGSERIAL;
ALTER TABLE score_topics DROP CONSTRAINT IF EXISTS score_topics_pkey;
ALTER TABLE score_topics ADD CONSTRAINT score_topics_pkey PRIMARY KEY (id);
ALTER TABLE score_topics ADD CONSTRAINT uq_score_topics UNIQUE (user_id, member_id, topic);

-- 7o. score_congress (user_id UUID, member_id BIGINT, congress INT)
ALTER TABLE score_congress ADD COLUMN id BIGSERIAL;
ALTER TABLE score_congress DROP CONSTRAINT IF EXISTS score_congress_pkey;
ALTER TABLE score_congress ADD CONSTRAINT score_congress_pkey PRIMARY KEY (id);
ALTER TABLE score_congress ADD CONSTRAINT uq_score_congress UNIQUE (user_id, member_id, congress);

-- 7p. score_congress_topics (user_id UUID, member_id BIGINT, congress INT, topic TEXT)
ALTER TABLE score_congress_topics ADD COLUMN id BIGSERIAL;
ALTER TABLE score_congress_topics DROP CONSTRAINT IF EXISTS score_congress_topics_pkey;
ALTER TABLE score_congress_topics ADD CONSTRAINT score_congress_topics_pkey PRIMARY KEY (id);
ALTER TABLE score_congress_topics ADD CONSTRAINT uq_score_congress_topics UNIQUE (user_id, member_id, congress, topic);

-- 7q. score_history_congress (score_id BIGINT, congress INT)
ALTER TABLE score_history_congress ADD COLUMN id BIGSERIAL;
ALTER TABLE score_history_congress DROP CONSTRAINT IF EXISTS score_history_congress_pkey;
ALTER TABLE score_history_congress ADD CONSTRAINT score_history_congress_pkey PRIMARY KEY (id);
ALTER TABLE score_history_congress ADD CONSTRAINT uq_score_history_congress UNIQUE (score_id, congress);

-- 7r. score_history_congress_topics (score_id BIGINT, congress INT, topic TEXT)
ALTER TABLE score_history_congress_topics ADD COLUMN id BIGSERIAL;
ALTER TABLE score_history_congress_topics DROP CONSTRAINT IF EXISTS score_history_congress_topics_pkey;
ALTER TABLE score_history_congress_topics ADD CONSTRAINT score_history_congress_topics_pkey PRIMARY KEY (id);
ALTER TABLE score_history_congress_topics ADD CONSTRAINT uq_score_history_congress_topics UNIQUE (score_id, congress, topic);

-- 7s. score_history_highlights (score_id BIGINT, bill_id BIGINT, topic TEXT)
ALTER TABLE score_history_highlights ADD COLUMN id BIGSERIAL;
ALTER TABLE score_history_highlights DROP CONSTRAINT IF EXISTS score_history_highlights_pkey;
ALTER TABLE score_history_highlights ADD CONSTRAINT score_history_highlights_pkey PRIMARY KEY (id);
ALTER TABLE score_history_highlights ADD CONSTRAINT uq_score_history_highlights UNIQUE (score_id, bill_id, topic);

-- 7t. member_bill_stances (member_id BIGINT, bill_id BIGINT, vote_id BIGINT)
ALTER TABLE member_bill_stances ADD COLUMN id BIGSERIAL;
ALTER TABLE member_bill_stances DROP CONSTRAINT IF EXISTS member_bill_stances_pkey;
ALTER TABLE member_bill_stances ADD CONSTRAINT member_bill_stances_pkey PRIMARY KEY (id);
ALTER TABLE member_bill_stances ADD CONSTRAINT uq_member_bill_stances UNIQUE (member_id, bill_id, vote_id);

-- 7u. user_legislator_pairings (user_id UUID, member_id BIGINT)
ALTER TABLE user_legislator_pairings ADD COLUMN id BIGSERIAL;
ALTER TABLE user_legislator_pairings DROP CONSTRAINT IF EXISTS user_legislator_pairings_pkey;
ALTER TABLE user_legislator_pairings ADD CONSTRAINT user_legislator_pairings_pkey PRIMARY KEY (id);
ALTER TABLE user_legislator_pairings ADD CONSTRAINT uq_user_legislator_pairings UNIQUE (user_id, member_id);

-- 7v. user_bill_alignments (user_id UUID, bill_id BIGINT, topic TEXT)
ALTER TABLE user_bill_alignments ADD COLUMN id BIGSERIAL;
ALTER TABLE user_bill_alignments DROP CONSTRAINT IF EXISTS user_bill_alignments_pkey;
ALTER TABLE user_bill_alignments ADD CONSTRAINT user_bill_alignments_pkey PRIMARY KEY (id);
ALTER TABLE user_bill_alignments ADD CONSTRAINT uq_user_bill_alignments UNIQUE (user_id, bill_id, topic);

-- 7w. user_amendment_alignments (user_id UUID, amendment_id BIGINT, topic TEXT)
ALTER TABLE user_amendment_alignments ADD COLUMN id BIGSERIAL;
ALTER TABLE user_amendment_alignments DROP CONSTRAINT IF EXISTS user_amendment_alignments_pkey;
ALTER TABLE user_amendment_alignments ADD CONSTRAINT user_amendment_alignments_pkey PRIMARY KEY (id);
ALTER TABLE user_amendment_alignments ADD CONSTRAINT uq_user_amendment_alignments UNIQUE (user_id, amendment_id, topic);

-- 7x. stance_materialization_status (bill_id BIGINT) -- already BIGINT, just add id
ALTER TABLE stance_materialization_status ADD COLUMN id BIGSERIAL;
ALTER TABLE stance_materialization_status DROP CONSTRAINT IF EXISTS stance_materialization_status_pkey;
ALTER TABLE stance_materialization_status ADD CONSTRAINT stance_materialization_status_pkey PRIMARY KEY (id);
ALTER TABLE stance_materialization_status ADD CONSTRAINT uq_stance_materialization_status UNIQUE (bill_id);

-- 7y. member_lis_mapping -- new table replacing lis_member_mapping
CREATE TABLE member_lis_mapping (
    id                   BIGSERIAL   PRIMARY KEY,
    member_id            BIGINT      NOT NULL,
    lis_member_id        BIGINT      NOT NULL,
    last_verified        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_member_lis_mapping UNIQUE (member_id, lis_member_id)
);

-- Populate from old lis_member_mapping
INSERT INTO member_lis_mapping (member_id, lis_member_id, last_verified)
SELECT m.id, lm.id, olm.last_verified
FROM lis_member_mapping olm
JOIN members m ON olm.member_id = m.natural_key
JOIN lis_members lm ON olm.lis_member_id = lm.natural_key;

-- ===========================================================================
-- SECTION 8: Recreate ALL FK constraints and indexes
-- ===========================================================================

-- -----------------------------------------------------------------------
-- 8a. FKs from member child tables -> members(id)
-- -----------------------------------------------------------------------
ALTER TABLE member_terms ADD CONSTRAINT member_terms_member_id_fkey
    FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE;
ALTER TABLE member_party_history ADD CONSTRAINT member_party_history_member_id_fkey
    FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE;

-- -----------------------------------------------------------------------
-- 8b. FKs referencing members(id) from other tables
-- -----------------------------------------------------------------------
ALTER TABLE bills ADD CONSTRAINT bills_sponsor_member_id_fkey
    FOREIGN KEY (sponsor_member_id) REFERENCES members(id);
ALTER TABLE bill_cosponsors ADD CONSTRAINT bill_cosponsors_member_id_fkey
    FOREIGN KEY (member_id) REFERENCES members(id);
ALTER TABLE vote_positions ADD CONSTRAINT vote_positions_member_id_fkey
    FOREIGN KEY (member_id) REFERENCES members(id);
ALTER TABLE scores ADD CONSTRAINT scores_member_id_fkey
    FOREIGN KEY (member_id) REFERENCES members(id);
ALTER TABLE score_history ADD CONSTRAINT score_history_member_id_fkey
    FOREIGN KEY (member_id) REFERENCES members(id);
ALTER TABLE member_bill_stances ADD CONSTRAINT member_bill_stances_member_id_fkey
    FOREIGN KEY (member_id) REFERENCES members(id);
ALTER TABLE amendments ADD CONSTRAINT amendments_sponsor_member_id_fkey
    FOREIGN KEY (sponsor_member_id) REFERENCES members(id);
ALTER TABLE committee_members ADD CONSTRAINT committee_members_member_id_fkey
    FOREIGN KEY (member_id) REFERENCES members(id);
ALTER TABLE user_legislator_pairings ADD CONSTRAINT user_legislator_pairings_member_id_fkey
    FOREIGN KEY (member_id) REFERENCES members(id);
ALTER TABLE member_lis_mapping ADD CONSTRAINT member_lis_mapping_member_id_fkey
    FOREIGN KEY (member_id) REFERENCES members(id);
ALTER TABLE member_lis_mapping ADD CONSTRAINT member_lis_mapping_lis_member_id_fkey
    FOREIGN KEY (lis_member_id) REFERENCES lis_members(id);

-- -----------------------------------------------------------------------
-- 8c. FKs referencing votes(id)
-- -----------------------------------------------------------------------
ALTER TABLE vote_positions ADD CONSTRAINT vote_positions_vote_id_fkey
    FOREIGN KEY (vote_id) REFERENCES votes(id) ON DELETE CASCADE;
ALTER TABLE member_bill_stances ADD CONSTRAINT member_bill_stances_vote_id_fkey
    FOREIGN KEY (vote_id) REFERENCES votes(id);

-- -----------------------------------------------------------------------
-- 8d. FKs referencing amendments(id)
-- -----------------------------------------------------------------------
ALTER TABLE amendment_findings ADD CONSTRAINT amendment_findings_amendment_id_fkey
    FOREIGN KEY (amendment_id) REFERENCES amendments(id);
ALTER TABLE amendment_analyses ADD CONSTRAINT amendment_analyses_amendment_id_fkey
    FOREIGN KEY (amendment_id) REFERENCES amendments(id);
ALTER TABLE amendment_concept_summaries ADD CONSTRAINT amendment_concept_summaries_amendment_id_fkey
    FOREIGN KEY (amendment_id) REFERENCES amendments(id);
ALTER TABLE amendment_analysis_topics ADD CONSTRAINT amendment_analysis_topics_amendment_id_fkey
    FOREIGN KEY (amendment_id) REFERENCES amendments(id);
ALTER TABLE amendment_text_versions ADD CONSTRAINT amendment_text_versions_amendment_id_fkey
    FOREIGN KEY (amendment_id) REFERENCES amendments(id);
ALTER TABLE votes ADD CONSTRAINT votes_amendment_id_fkey
    FOREIGN KEY (amendment_id) REFERENCES amendments(id);
ALTER TABLE member_bill_stances ADD CONSTRAINT member_bill_stances_amendment_id_fkey
    FOREIGN KEY (amendment_id) REFERENCES amendments(id);
ALTER TABLE user_amendment_alignments ADD CONSTRAINT user_amendment_alignments_amendment_id_fkey
    FOREIGN KEY (amendment_id) REFERENCES amendments(id);

-- -----------------------------------------------------------------------
-- 8e. FKs referencing committees(id)
-- -----------------------------------------------------------------------
ALTER TABLE committees ADD CONSTRAINT committees_parent_committee_id_fkey
    FOREIGN KEY (parent_committee_id) REFERENCES committees(id);
ALTER TABLE committee_members ADD CONSTRAINT committee_members_committee_id_fkey
    FOREIGN KEY (committee_id) REFERENCES committees(id) ON DELETE CASCADE;
ALTER TABLE bill_committee_referrals ADD CONSTRAINT bill_committee_referrals_committee_id_fkey
    FOREIGN KEY (committee_id) REFERENCES committees(id);

-- -----------------------------------------------------------------------
-- 8f. FKs referencing qa_questions(id)
-- -----------------------------------------------------------------------
ALTER TABLE qa_question_topics ADD CONSTRAINT qa_question_topics_question_id_fkey
    FOREIGN KEY (question_id) REFERENCES qa_questions(id) ON DELETE CASCADE;
ALTER TABLE qa_answer_options ADD CONSTRAINT qa_answer_options_question_id_fkey
    FOREIGN KEY (question_id) REFERENCES qa_questions(id) ON DELETE CASCADE;
ALTER TABLE qa_user_responses ADD CONSTRAINT qa_user_responses_question_id_fkey
    FOREIGN KEY (question_id) REFERENCES qa_questions(id);

-- -----------------------------------------------------------------------
-- 8g. FKs referencing finding_types(id)
-- -----------------------------------------------------------------------
ALTER TABLE bill_findings ADD CONSTRAINT bill_findings_finding_type_id_fkey
    FOREIGN KEY (finding_type_id) REFERENCES finding_types(id);
ALTER TABLE amendment_findings ADD CONSTRAINT amendment_findings_finding_type_id_fkey
    FOREIGN KEY (finding_type_id) REFERENCES finding_types(id);

-- -----------------------------------------------------------------------
-- 8h. FKs referencing bills(id)
-- -----------------------------------------------------------------------
ALTER TABLE bill_cosponsors ADD CONSTRAINT bill_cosponsors_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id) ON DELETE CASCADE;
ALTER TABLE bill_subjects ADD CONSTRAINT bill_subjects_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id) ON DELETE CASCADE;
ALTER TABLE bill_text_versions ADD CONSTRAINT bill_text_versions_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id) ON DELETE CASCADE;
ALTER TABLE bill_text_sections ADD CONSTRAINT bill_text_sections_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE bill_concept_groups ADD CONSTRAINT bill_concept_groups_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE bill_analyses ADD CONSTRAINT bill_analyses_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE bill_findings ADD CONSTRAINT bill_findings_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE bill_concept_summaries ADD CONSTRAINT bill_concept_summaries_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE bill_analysis_topics ADD CONSTRAINT bill_analysis_topics_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE bill_fiscal_estimates ADD CONSTRAINT bill_fiscal_estimates_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE votes ADD CONSTRAINT votes_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE amendments ADD CONSTRAINT amendments_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE member_bill_stances ADD CONSTRAINT member_bill_stances_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE score_history_highlights ADD CONSTRAINT score_history_highlights_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE user_bill_alignments ADD CONSTRAINT user_bill_alignments_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE user_amendment_alignments ADD CONSTRAINT user_amendment_alignments_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE amendment_analyses ADD CONSTRAINT amendment_analyses_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE amendment_concept_summaries ADD CONSTRAINT amendment_concept_summaries_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE stance_materialization_status ADD CONSTRAINT stance_materialization_status_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id);
ALTER TABLE bill_committee_referrals ADD CONSTRAINT bill_committee_referrals_bill_id_fkey
    FOREIGN KEY (bill_id) REFERENCES bills(id) ON DELETE CASCADE;
ALTER TABLE bills ADD CONSTRAINT bills_latest_text_version_id_fkey
    FOREIGN KEY (latest_text_version_id) REFERENCES bill_text_versions(id);

-- -----------------------------------------------------------------------
-- 8i. FKs referencing bill_text_versions(id)
-- -----------------------------------------------------------------------
ALTER TABLE bill_text_sections ADD CONSTRAINT bill_text_sections_version_id_fkey
    FOREIGN KEY (version_id) REFERENCES bill_text_versions(id) ON DELETE CASCADE;
ALTER TABLE bill_concept_groups ADD CONSTRAINT bill_concept_groups_version_id_fkey
    FOREIGN KEY (version_id) REFERENCES bill_text_versions(id) ON DELETE CASCADE;
ALTER TABLE bill_analyses ADD CONSTRAINT bill_analyses_version_id_fkey
    FOREIGN KEY (version_id) REFERENCES bill_text_versions(id);

-- -----------------------------------------------------------------------
-- 8j. FKs referencing bill_text_sections(id)
-- -----------------------------------------------------------------------
ALTER TABLE bill_concept_group_sections ADD CONSTRAINT bill_concept_group_sections_section_id_fkey
    FOREIGN KEY (section_id) REFERENCES bill_text_sections(id) ON DELETE CASCADE;

-- -----------------------------------------------------------------------
-- 8k. FKs referencing bill_concept_groups(id)
-- -----------------------------------------------------------------------
ALTER TABLE bill_concept_group_sections ADD CONSTRAINT bill_concept_group_sections_concept_group_id_fkey
    FOREIGN KEY (concept_group_id) REFERENCES bill_concept_groups(id) ON DELETE CASCADE;
ALTER TABLE bill_concept_summaries ADD CONSTRAINT bill_concept_summaries_concept_group_id_fkey
    FOREIGN KEY (concept_group_id) REFERENCES bill_concept_groups(id);
ALTER TABLE bill_fiscal_estimates ADD CONSTRAINT bill_fiscal_estimates_concept_group_id_fkey
    FOREIGN KEY (concept_group_id) REFERENCES bill_concept_groups(id);

-- -----------------------------------------------------------------------
-- 8l. FKs referencing bill_analyses(id)
-- -----------------------------------------------------------------------
ALTER TABLE bill_concept_summaries ADD CONSTRAINT bill_concept_summaries_analysis_id_fkey
    FOREIGN KEY (analysis_id) REFERENCES bill_analyses(id) ON DELETE CASCADE;
ALTER TABLE bill_analysis_topics ADD CONSTRAINT bill_analysis_topics_analysis_id_fkey
    FOREIGN KEY (analysis_id) REFERENCES bill_analyses(id) ON DELETE CASCADE;
ALTER TABLE bill_fiscal_estimates ADD CONSTRAINT bill_fiscal_estimates_analysis_id_fkey
    FOREIGN KEY (analysis_id) REFERENCES bill_analyses(id) ON DELETE CASCADE;
ALTER TABLE bill_findings ADD CONSTRAINT bill_findings_analysis_id_fkey
    FOREIGN KEY (analysis_id) REFERENCES bill_analyses(id);

-- -----------------------------------------------------------------------
-- 8m. FKs referencing bill_findings(id)
-- -----------------------------------------------------------------------
ALTER TABLE member_bill_stance_topics ADD CONSTRAINT member_bill_stance_topics_finding_id_fkey
    FOREIGN KEY (finding_id) REFERENCES bill_findings(id);
ALTER TABLE user_bill_alignments ADD CONSTRAINT user_bill_alignments_finding_id_fkey
    FOREIGN KEY (finding_id) REFERENCES bill_findings(id);

-- -----------------------------------------------------------------------
-- 8n. FKs referencing amendment_findings(id)
-- -----------------------------------------------------------------------
ALTER TABLE user_amendment_alignments ADD CONSTRAINT user_amendment_alignments_finding_id_fkey
    FOREIGN KEY (finding_id) REFERENCES amendment_findings(id);

-- -----------------------------------------------------------------------
-- 8o. FKs referencing amendment_analyses(id)
-- -----------------------------------------------------------------------
ALTER TABLE amendment_concept_summaries ADD CONSTRAINT amendment_concept_summaries_analysis_id_fkey
    FOREIGN KEY (analysis_id) REFERENCES amendment_analyses(id) ON DELETE CASCADE;
ALTER TABLE amendment_analysis_topics ADD CONSTRAINT amendment_analysis_topics_analysis_id_fkey
    FOREIGN KEY (analysis_id) REFERENCES amendment_analyses(id) ON DELETE CASCADE;
ALTER TABLE amendment_findings ADD CONSTRAINT amendment_findings_analysis_id_fkey
    FOREIGN KEY (analysis_id) REFERENCES amendment_analyses(id);

-- -----------------------------------------------------------------------
-- 8p. FKs referencing amendment_text_versions(id)
-- -----------------------------------------------------------------------
ALTER TABLE amendments ADD CONSTRAINT fk_amendments_latest_text_version
    FOREIGN KEY (latest_text_version_id) REFERENCES amendment_text_versions(id);

-- -----------------------------------------------------------------------
-- 8q. FKs referencing vote_history(id) -- history tables
-- -----------------------------------------------------------------------
ALTER TABLE vote_history_positions ADD CONSTRAINT vote_history_positions_history_id_fkey
    FOREIGN KEY (history_id) REFERENCES vote_history(id) ON DELETE CASCADE;

-- -----------------------------------------------------------------------
-- 8r. FKs referencing member_history(id)
-- -----------------------------------------------------------------------
ALTER TABLE member_term_history ADD CONSTRAINT member_term_history_history_id_fkey
    FOREIGN KEY (history_id) REFERENCES member_history(id) ON DELETE CASCADE;

-- -----------------------------------------------------------------------
-- 8s. FKs referencing bill_history(id)
-- -----------------------------------------------------------------------
ALTER TABLE bill_cosponsor_history ADD CONSTRAINT bill_cosponsor_history_history_id_fkey
    FOREIGN KEY (history_id) REFERENCES bill_history(id) ON DELETE CASCADE;
ALTER TABLE bill_subject_history ADD CONSTRAINT bill_subject_history_history_id_fkey
    FOREIGN KEY (history_id) REFERENCES bill_history(id) ON DELETE CASCADE;

-- -----------------------------------------------------------------------
-- 8t. FKs referencing score_history(id)
-- -----------------------------------------------------------------------
ALTER TABLE score_history_congress ADD CONSTRAINT score_history_congress_score_id_fkey
    FOREIGN KEY (score_id) REFERENCES score_history(id) ON DELETE CASCADE;
ALTER TABLE score_history_highlights ADD CONSTRAINT score_history_highlights_score_id_fkey
    FOREIGN KEY (score_id) REFERENCES score_history(id) ON DELETE CASCADE;

-- -----------------------------------------------------------------------
-- 8u. FKs referencing score_history_congress (composite UNIQUE now)
-- -----------------------------------------------------------------------
ALTER TABLE score_history_congress_topics ADD CONSTRAINT score_history_congress_topics_score_id_congress_fkey
    FOREIGN KEY (score_id, congress) REFERENCES score_history_congress(score_id, congress) ON DELETE CASCADE;

-- -----------------------------------------------------------------------
-- 8v. FKs from scores composite children
-- -----------------------------------------------------------------------
ALTER TABLE score_topics ADD CONSTRAINT score_topics_user_id_member_id_fkey
    FOREIGN KEY (user_id, member_id) REFERENCES scores(user_id, member_id) ON DELETE CASCADE;
ALTER TABLE score_congress ADD CONSTRAINT score_congress_user_id_member_id_fkey
    FOREIGN KEY (user_id, member_id) REFERENCES scores(user_id, member_id) ON DELETE CASCADE;

-- -----------------------------------------------------------------------
-- 8w. FKs from score_congress children
-- -----------------------------------------------------------------------
ALTER TABLE score_congress_topics ADD CONSTRAINT score_congress_topics_user_id_member_id_congress_fkey
    FOREIGN KEY (user_id, member_id, congress) REFERENCES score_congress(user_id, member_id, congress) ON DELETE CASCADE;

-- -----------------------------------------------------------------------
-- 8x. FKs referencing users(user_id)
-- -----------------------------------------------------------------------
ALTER TABLE user_preferences ADD CONSTRAINT user_preferences_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE;
ALTER TABLE scores ADD CONSTRAINT scores_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE;
ALTER TABLE score_history ADD CONSTRAINT score_history_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE;
ALTER TABLE qa_user_responses ADD CONSTRAINT qa_user_responses_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE;
ALTER TABLE user_legislator_pairings ADD CONSTRAINT user_legislator_pairings_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE;
ALTER TABLE user_bill_alignments ADD CONSTRAINT user_bill_alignments_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE;
ALTER TABLE user_amendment_alignments ADD CONSTRAINT user_amendment_alignments_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE;

-- -----------------------------------------------------------------------
-- 8y. FKs referencing pipeline_runs(id)
-- -----------------------------------------------------------------------
ALTER TABLE processing_results ADD CONSTRAINT processing_results_run_id_fkey
    FOREIGN KEY (run_id) REFERENCES pipeline_runs(id) ON DELETE CASCADE;
ALTER TABLE workflow_run_steps ADD CONSTRAINT workflow_run_steps_pipeline_run_id_fkey
    FOREIGN KEY (pipeline_run_id) REFERENCES pipeline_runs(id);

-- -----------------------------------------------------------------------
-- 8z. FKs referencing workflow_runs(id)
-- -----------------------------------------------------------------------
ALTER TABLE workflow_run_steps ADD CONSTRAINT workflow_run_steps_workflow_run_id_fkey
    FOREIGN KEY (workflow_run_id) REFERENCES workflow_runs(id) ON DELETE CASCADE;

-- -----------------------------------------------------------------------
-- 8aa. FK from member_bill_stance_topics to member_bill_stances composite UNIQUE
-- -----------------------------------------------------------------------
ALTER TABLE member_bill_stance_topics ADD CONSTRAINT member_bill_stance_topics_member_bill_vote_fkey
    FOREIGN KEY (member_id, bill_id, vote_id)
    REFERENCES member_bill_stances(member_id, bill_id, vote_id) ON DELETE CASCADE;

-- ===========================================================================
-- SECTION 9: Drop old lis_member_mapping table
-- ===========================================================================

DROP TABLE lis_member_mapping;

-- Drop old indexes that referenced TEXT columns (will be recreated by new PKs/UNIQUEs)
DROP INDEX IF EXISTS idx_lis_mapping_member;

-- ===========================================================================
-- SECTION 10: Reset all BIGSERIAL sequences
-- ===========================================================================
-- After bulk data migration, sequences may be behind the max id value.

SELECT setval(pg_get_serial_sequence('lis_members', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM lis_members;
SELECT setval(pg_get_serial_sequence('members', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM members;
SELECT setval(pg_get_serial_sequence('votes', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM votes;
SELECT setval(pg_get_serial_sequence('amendments', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM amendments;
SELECT setval(pg_get_serial_sequence('committees', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM committees;
SELECT setval(pg_get_serial_sequence('qa_questions', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM qa_questions;
SELECT setval(pg_get_serial_sequence('finding_types', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM finding_types;
SELECT setval(pg_get_serial_sequence('bill_text_versions', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_text_versions;
SELECT setval(pg_get_serial_sequence('bill_text_sections', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_text_sections;
SELECT setval(pg_get_serial_sequence('bill_concept_groups', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_concept_groups;
SELECT setval(pg_get_serial_sequence('bill_analyses', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_analyses;
SELECT setval(pg_get_serial_sequence('bill_findings', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_findings;
SELECT setval(pg_get_serial_sequence('bill_concept_summaries', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_concept_summaries;
SELECT setval(pg_get_serial_sequence('bill_analysis_topics', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_analysis_topics;
SELECT setval(pg_get_serial_sequence('bill_fiscal_estimates', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_fiscal_estimates;
SELECT setval(pg_get_serial_sequence('amendment_findings', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM amendment_findings;
SELECT setval(pg_get_serial_sequence('amendment_analyses', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM amendment_analyses;
SELECT setval(pg_get_serial_sequence('amendment_concept_summaries', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM amendment_concept_summaries;
SELECT setval(pg_get_serial_sequence('amendment_analysis_topics', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM amendment_analysis_topics;
SELECT setval(pg_get_serial_sequence('amendment_text_versions', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM amendment_text_versions;
SELECT setval(pg_get_serial_sequence('vote_history', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM vote_history;
SELECT setval(pg_get_serial_sequence('member_history', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM member_history;
SELECT setval(pg_get_serial_sequence('bill_history', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_history;
SELECT setval(pg_get_serial_sequence('member_terms', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM member_terms;
SELECT setval(pg_get_serial_sequence('member_party_history', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM member_party_history;
SELECT setval(pg_get_serial_sequence('workflow_runs', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM workflow_runs;
SELECT setval(pg_get_serial_sequence('workflow_run_steps', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM workflow_run_steps;
SELECT setval(pg_get_serial_sequence('pipeline_runs', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM pipeline_runs;
SELECT setval(pg_get_serial_sequence('processing_results', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM processing_results;
SELECT setval(pg_get_serial_sequence('user_preferences', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM user_preferences;
SELECT setval(pg_get_serial_sequence('score_history', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM score_history;
SELECT setval(pg_get_serial_sequence('qa_user_responses', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM qa_user_responses;
SELECT setval(pg_get_serial_sequence('member_bill_stance_topics', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM member_bill_stance_topics;
SELECT setval(pg_get_serial_sequence('bill_cosponsors', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_cosponsors;
SELECT setval(pg_get_serial_sequence('bill_subjects', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_subjects;
SELECT setval(pg_get_serial_sequence('vote_positions', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM vote_positions;
SELECT setval(pg_get_serial_sequence('vote_history_positions', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM vote_history_positions;
SELECT setval(pg_get_serial_sequence('member_term_history', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM member_term_history;
SELECT setval(pg_get_serial_sequence('bill_cosponsor_history', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_cosponsor_history;
SELECT setval(pg_get_serial_sequence('bill_subject_history', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_subject_history;
SELECT setval(pg_get_serial_sequence('bill_concept_group_sections', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_concept_group_sections;
SELECT setval(pg_get_serial_sequence('committee_members', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM committee_members;
SELECT setval(pg_get_serial_sequence('bill_committee_referrals', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM bill_committee_referrals;
SELECT setval(pg_get_serial_sequence('qa_question_topics', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM qa_question_topics;
SELECT setval(pg_get_serial_sequence('qa_answer_options', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM qa_answer_options;
SELECT setval(pg_get_serial_sequence('scores', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM scores;
SELECT setval(pg_get_serial_sequence('score_topics', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM score_topics;
SELECT setval(pg_get_serial_sequence('score_congress', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM score_congress;
SELECT setval(pg_get_serial_sequence('score_congress_topics', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM score_congress_topics;
SELECT setval(pg_get_serial_sequence('score_history_congress', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM score_history_congress;
SELECT setval(pg_get_serial_sequence('score_history_congress_topics', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM score_history_congress_topics;
SELECT setval(pg_get_serial_sequence('score_history_highlights', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM score_history_highlights;
SELECT setval(pg_get_serial_sequence('member_bill_stances', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM member_bill_stances;
SELECT setval(pg_get_serial_sequence('user_legislator_pairings', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM user_legislator_pairings;
SELECT setval(pg_get_serial_sequence('user_bill_alignments', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM user_bill_alignments;
SELECT setval(pg_get_serial_sequence('user_amendment_alignments', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM user_amendment_alignments;
SELECT setval(pg_get_serial_sequence('stance_materialization_status', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM stance_materialization_status;
SELECT setval(pg_get_serial_sequence('member_lis_mapping', 'id'), GREATEST(COALESCE(MAX(id), 1), 1)) FROM member_lis_mapping;

-- ===========================================================================
-- SECTION 11: Rebuild indexes that were dropped with old columns
-- ===========================================================================
-- Many indexes were auto-dropped when their columns were dropped/renamed.
-- Recreate essential indexes on the new column names/types.

-- members indexes
CREATE INDEX IF NOT EXISTS idx_members_state ON members (state);
CREATE INDEX IF NOT EXISTS idx_members_state_district ON members (state, district);
CREATE INDEX IF NOT EXISTS idx_members_current_party ON members (current_party);

-- bills indexes (sponsor renamed)
DROP INDEX IF EXISTS idx_bills_sponsor;
CREATE INDEX IF NOT EXISTS idx_bills_sponsor ON bills (sponsor_member_id);

-- votes indexes
CREATE INDEX IF NOT EXISTS idx_votes_bill_id ON votes (bill_id);
CREATE INDEX IF NOT EXISTS idx_votes_congress ON votes (congress);
CREATE INDEX IF NOT EXISTS idx_votes_date ON votes (vote_date);
CREATE INDEX IF NOT EXISTS idx_votes_amendment_id ON votes (amendment_id) WHERE amendment_id IS NOT NULL;

-- vote_positions indexes
CREATE INDEX IF NOT EXISTS idx_vote_positions_member ON vote_positions (member_id);

-- vote_history indexes
CREATE INDEX IF NOT EXISTS idx_vote_history_vote_id ON vote_history (vote_id);

-- amendments indexes
DROP INDEX IF EXISTS idx_amendments_sponsor;
CREATE INDEX IF NOT EXISTS idx_amendments_sponsor ON amendments (sponsor_member_id);
CREATE INDEX IF NOT EXISTS idx_amendments_bill_id ON amendments (bill_id);
CREATE INDEX IF NOT EXISTS idx_amendments_congress ON amendments (congress);

-- amendment_findings indexes
CREATE INDEX IF NOT EXISTS idx_amendment_findings_amendment ON amendment_findings (amendment_id);
CREATE INDEX IF NOT EXISTS idx_amendment_findings_type ON amendment_findings (finding_type_id);
CREATE INDEX IF NOT EXISTS idx_amendment_findings_analysis ON amendment_findings (analysis_id) WHERE analysis_id IS NOT NULL;

-- amendment_analyses indexes
CREATE INDEX IF NOT EXISTS idx_amendment_analyses_amendment ON amendment_analyses (amendment_id);
CREATE INDEX IF NOT EXISTS idx_amendment_analyses_bill ON amendment_analyses (bill_id);

-- amendment_concept_summaries indexes
CREATE INDEX IF NOT EXISTS idx_amendment_concept_summaries_analysis ON amendment_concept_summaries (analysis_id);
CREATE INDEX IF NOT EXISTS idx_amendment_concept_summaries_amendment ON amendment_concept_summaries (amendment_id);
CREATE INDEX IF NOT EXISTS idx_amendment_concept_summaries_bill ON amendment_concept_summaries (bill_id);

-- amendment_analysis_topics indexes
CREATE INDEX IF NOT EXISTS idx_amendment_analysis_topics_analysis ON amendment_analysis_topics (analysis_id);
CREATE INDEX IF NOT EXISTS idx_amendment_analysis_topics_amendment ON amendment_analysis_topics (amendment_id);

-- amendment_text_versions indexes
CREATE INDEX IF NOT EXISTS idx_amendment_text_versions_amendment ON amendment_text_versions (amendment_id);

-- bill_text_versions indexes
CREATE INDEX IF NOT EXISTS idx_bill_text_versions_bill ON bill_text_versions (bill_id);

-- bill_text_sections indexes
CREATE INDEX IF NOT EXISTS idx_text_sections_version ON bill_text_sections (version_id);
CREATE INDEX IF NOT EXISTS idx_text_sections_bill ON bill_text_sections (bill_id);

-- bill_concept_groups indexes
CREATE INDEX IF NOT EXISTS idx_concept_groups_version ON bill_concept_groups (version_id);
CREATE INDEX IF NOT EXISTS idx_concept_groups_bill ON bill_concept_groups (bill_id);

-- bill_concept_group_sections indexes
CREATE INDEX IF NOT EXISTS idx_cg_sections_section ON bill_concept_group_sections (section_id);

-- bill_analyses indexes
CREATE INDEX IF NOT EXISTS idx_bill_analyses_bill_id ON bill_analyses (bill_id);

-- bill_findings indexes
CREATE INDEX IF NOT EXISTS idx_bill_findings_bill ON bill_findings (bill_id);
CREATE INDEX IF NOT EXISTS idx_bill_findings_analysis ON bill_findings (analysis_id);
CREATE INDEX IF NOT EXISTS idx_bill_findings_type ON bill_findings (finding_type_id);

-- bill_concept_summaries indexes
CREATE INDEX IF NOT EXISTS idx_concept_summaries_analysis ON bill_concept_summaries (analysis_id);
CREATE INDEX IF NOT EXISTS idx_concept_summaries_bill ON bill_concept_summaries (bill_id);
CREATE INDEX IF NOT EXISTS idx_concept_summaries_group ON bill_concept_summaries (concept_group_id);

-- bill_analysis_topics indexes
CREATE INDEX IF NOT EXISTS idx_analysis_topics_analysis ON bill_analysis_topics (analysis_id);
CREATE INDEX IF NOT EXISTS idx_analysis_topics_bill ON bill_analysis_topics (bill_id);

-- bill_fiscal_estimates indexes
CREATE INDEX IF NOT EXISTS idx_fiscal_estimates_analysis ON bill_fiscal_estimates (analysis_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_estimates_bill ON bill_fiscal_estimates (bill_id);

-- bill_cosponsors indexes
CREATE INDEX IF NOT EXISTS idx_bill_cosponsors_member ON bill_cosponsors (member_id);

-- committee_members indexes
CREATE INDEX IF NOT EXISTS idx_committee_members_member ON committee_members (member_id);

-- committees indexes
CREATE INDEX IF NOT EXISTS idx_committees_chamber ON committees (chamber);
CREATE INDEX IF NOT EXISTS idx_committees_parent ON committees (parent_committee_id);

-- bill_committee_referrals indexes
CREATE INDEX IF NOT EXISTS idx_bill_committee_referrals_committee ON bill_committee_referrals (committee_id);

-- member_terms indexes
CREATE INDEX IF NOT EXISTS idx_member_terms_member ON member_terms (member_id);
CREATE INDEX IF NOT EXISTS idx_member_terms_congress ON member_terms (congress);

-- member_party_history indexes
CREATE INDEX IF NOT EXISTS idx_member_party_history_member ON member_party_history (member_id);

-- member_history indexes
CREATE INDEX IF NOT EXISTS idx_member_history_member ON member_history (member_id);

-- bill_history indexes
CREATE INDEX IF NOT EXISTS idx_bill_history_bill ON bill_history (bill_id);

-- scores indexes
CREATE INDEX IF NOT EXISTS idx_scores_member ON scores (member_id);

-- score_history indexes
CREATE INDEX IF NOT EXISTS idx_score_history_user_member ON score_history (user_id, member_id);

-- member_bill_stances indexes
CREATE INDEX IF NOT EXISTS idx_member_bill_stances_bill ON member_bill_stances (bill_id);
CREATE INDEX IF NOT EXISTS idx_member_bill_stances_member_congress ON member_bill_stances (member_id, congress);
CREATE INDEX IF NOT EXISTS idx_member_bill_stances_amendment ON member_bill_stances (amendment_id) WHERE amendment_id IS NOT NULL;

-- member_bill_stance_topics indexes
CREATE INDEX IF NOT EXISTS idx_stance_topics_member ON member_bill_stance_topics (member_id);
CREATE INDEX IF NOT EXISTS idx_stance_topics_bill ON member_bill_stance_topics (bill_id);
CREATE INDEX IF NOT EXISTS idx_stance_topics_member_topic ON member_bill_stance_topics (member_id, topic);
CREATE INDEX IF NOT EXISTS idx_stance_topics_finding ON member_bill_stance_topics (finding_id);

-- user_bill_alignments indexes
CREATE INDEX IF NOT EXISTS idx_user_bill_align_bill ON user_bill_alignments (bill_id);
CREATE INDEX IF NOT EXISTS idx_user_bill_align_user ON user_bill_alignments (user_id);

-- user_amendment_alignments indexes
CREATE INDEX IF NOT EXISTS idx_user_amend_align_amendment ON user_amendment_alignments (amendment_id);
CREATE INDEX IF NOT EXISTS idx_user_amend_align_user ON user_amendment_alignments (user_id);
CREATE INDEX IF NOT EXISTS idx_user_amend_align_bill ON user_amendment_alignments (bill_id);

-- user_legislator_pairings indexes
CREATE INDEX IF NOT EXISTS idx_pairings_member ON user_legislator_pairings (member_id);
CREATE INDEX IF NOT EXISTS idx_pairings_state_district ON user_legislator_pairings (state, district);

-- processing_results indexes
CREATE INDEX IF NOT EXISTS idx_processing_results_run ON processing_results (run_id);

-- workflow_run_steps indexes
CREATE INDEX IF NOT EXISTS idx_workflow_steps_run ON workflow_run_steps (workflow_run_id);

-- qa indexes
CREATE INDEX IF NOT EXISTS idx_qa_responses_user ON qa_user_responses (user_id);
CREATE INDEX IF NOT EXISTS idx_qa_responses_question ON qa_user_responses (question_id);

-- lis_members index
CREATE INDEX IF NOT EXISTS idx_lis_members_natural_key ON lis_members (natural_key);

-- member_lis_mapping indexes
CREATE INDEX IF NOT EXISTS idx_member_lis_mapping_member ON member_lis_mapping (member_id);
CREATE INDEX IF NOT EXISTS idx_member_lis_mapping_lis_member ON member_lis_mapping (lis_member_id);
