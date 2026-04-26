-- Migration 032: add bills.expected_text_version_code for stage-aware text-availability checks
--
-- Tracks the text version we expect this bill to have based on its current legislative
-- stage (introduced, reported, passed, enrolled, became-law). Two pipelines write to it,
-- both using a Scala-level read-then-write pattern with a TextVersionCode.progressionOrder
-- regression guard so neither can downgrade the other's writes:
--
--   * bill-metadata-pipeline (baseline writer): on every full upsert, sets the introduced
--     floor (IH or IS) based on origin_chamber. Guarantees coverage for bills CRS never
--     summarizes — most introduced bills die in committee without ever getting a summary.
--
--   * bill-summary-pipeline (advancing writer): on every CRS summary, maps the summary's
--     versionCode (e.g., "00", "01", "36", "49") to a TextVersionCode and writes when the
--     mapped stage exceeds the current stored stage.
--
-- bill-text-availability-checker uses this column as its sweep gate:
--
--   WHERE expected_text_version_code IS NOT NULL
--     AND text_version_type IS DISTINCT FROM expected_text_version_code
--
-- so it only calls Congress.gov /text when the bill's stage has moved past what we have
-- stored. Once bill-text-pipeline downloads and persists the matching version,
-- text_version_type catches up to expected_text_version_code and the bill exits the sweep
-- until the next stage transition.
--
-- No backfill: every value starts NULL. The bill-metadata-pipeline 10-year backfill cycles
-- through every bill on its first run after deploy and floors expected_text_version_code
-- from origin_chamber, so coverage converges naturally over the first ~2h sweep.

ALTER TABLE bills
  ADD COLUMN expected_text_version_code text_version_code_type;

COMMENT ON COLUMN bills.expected_text_version_code IS
  'The text version we expect this bill to have based on its current legislative stage. Written by bill-metadata-pipeline (introduced floor from origin_chamber) and bill-summary-pipeline (advancing from CRS summary versionCode). Read by bill-text-availability-checker to gate /text API calls. NULL means we have no stage signal yet.';
