-- Migration 049: Create bill_summaries table
--
-- CRS publishes a bill summary at each major stage (Introduced, Reported, Engrossed,
-- Passed, Public Law, ...). The single bills.summary_text column could only hold one
-- of these, and it was being clobbered to NULL on every bill-metadata UPSERT (the bill
-- detail API carries no summary, so EXCLUDED.summary_text was always NULL — fixed on the
-- write side by the ownership-boundary change in bills-common). This dedicated table,
-- owned by bill-summary-pipeline, keeps one row per stage with a FK back to bills —
-- mirroring bill_text_versions (one row per text version, FK to bills).
--
-- Additive and non-breaking: no code reads or writes this table yet (the consumers land
-- in a follow-up shared-models / bills-common change). The bills.summary_* columns are
-- dropped later, in the Phase 2 contract migration, once nothing references them.
--
-- IF NOT EXISTS-guarded per repo convention so Liquibase can replay against hot-patched
-- dev/local databases.

CREATE TABLE IF NOT EXISTS bill_summaries (
    id           BIGSERIAL PRIMARY KEY,
    bill_id      BIGINT NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    version_code text_version_code_type NOT NULL,   -- CRS action/stage (IH, RH, EH, ATS, PL, ...)
    action_date  DATE,
    action_desc  TEXT,
    text         TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_bill_summaries UNIQUE (bill_id, version_code)   -- one summary per stage; upsert target
);

CREATE INDEX IF NOT EXISTS idx_bill_summaries_bill ON bill_summaries (bill_id);
