-- Migration 037: Dedicated amendment text version code enum (per plan §L3)
--
-- Plan §L3 requires a DEDICATED enum for amendment text version codes, NOT a
-- co-mingled extension of the bill-side text_version_code_type. Bill text
-- versions and amendment text versions have different value spaces:
--   * Bills: IH, IS, RH, RS, ENR, etc. (procedural state codes)
--   * Amendments: Submitted, Modified (per Congress.gov /amendment/.../text)
--
-- Mixing them in one enum forced every reader to know which subset applies to
-- their entity type. The dedicated enum keeps the boundaries clean.
--
-- format_type_enum: NO 'HTML' addition. The Congress.gov amendment-text API
-- returns formats[].type values "PDF" or "HTML"; "HTML" is mapped to the
-- existing 'Formatted Text' value at the DTO/pipeline layer (the existing enum
-- value already serves the same semantic purpose for bills). Avoiding the
-- enum extension prevents two near-synonymous values from coexisting.

CREATE TYPE amendment_text_version_code_type AS ENUM ('Submitted', 'Modified');
