-- Migration 021: Expand text_version_code_type enum
-- Adds 3 new version codes encountered in Congress.gov API responses for older bills:
--   RCH (Reference Change House), EAS (Engrossed Amendment Senate),
--   RIS (Referral Instructions Senate)

ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'RCH';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'EAS';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'RIS';
