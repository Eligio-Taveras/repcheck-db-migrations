-- Migration 050: Drop the retired text_*/summary_* columns from bills and bill_history
--
-- Phase 2c contract step. These columns are fully superseded:
--   * text_url, text_format, text_date, text_content  -> bill_text_versions (one row per version)
--   * text_version_type                               -> read from bill_text_versions via
--                                                        bills.latest_text_version_id (the
--                                                        availability checker no longer reads the column)
--   * summary_text, summary_action_desc, summary_action_date -> bill_summaries (one row per CRS stage)
--
-- Safe to drop now: the bill-metadata UPSERT stopped writing them (ownership-boundary fix), the
-- availability checker reads the stored stage from bill_text_versions (Phase 2c expand), summaries
-- write to bill_summaries, and BillDO dropped the 7 mirrored fields (textVersionType kept, btv-sourced).
-- No code reads or writes these columns after the Phase 2c expand deploy.
--
-- bill_history never archived text_content, so it has 7 of the 8 columns.
--
-- DROP COLUMN IF EXISTS per repo convention so Liquibase can replay against hot-patched dev/local DBs.

ALTER TABLE bills DROP COLUMN IF EXISTS text_url;
ALTER TABLE bills DROP COLUMN IF EXISTS text_format;
ALTER TABLE bills DROP COLUMN IF EXISTS text_version_type;
ALTER TABLE bills DROP COLUMN IF EXISTS text_date;
ALTER TABLE bills DROP COLUMN IF EXISTS text_content;
ALTER TABLE bills DROP COLUMN IF EXISTS summary_text;
ALTER TABLE bills DROP COLUMN IF EXISTS summary_action_desc;
ALTER TABLE bills DROP COLUMN IF EXISTS summary_action_date;

ALTER TABLE bill_history DROP COLUMN IF EXISTS text_url;
ALTER TABLE bill_history DROP COLUMN IF EXISTS text_format;
ALTER TABLE bill_history DROP COLUMN IF EXISTS text_version_type;
ALTER TABLE bill_history DROP COLUMN IF EXISTS text_date;
ALTER TABLE bill_history DROP COLUMN IF EXISTS summary_text;
ALTER TABLE bill_history DROP COLUMN IF EXISTS summary_action_desc;
ALTER TABLE bill_history DROP COLUMN IF EXISTS summary_action_date;
