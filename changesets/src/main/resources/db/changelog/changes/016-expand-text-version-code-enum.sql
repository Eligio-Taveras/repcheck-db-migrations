-- Migration 016: Expand text_version_code_type enum
-- Adds 10 new version codes encountered in Congress.gov API responses:
--   PCS (Placed on Calendar Senate), PCH (Placed on Calendar House),
--   PL (Public Law), RDS (Received in Senate), RDH (Received in House),
--   RTS (Reported to Senate), RTH (Reported to House),
--   ATS (Agreed to Senate), ATH (Agreed to House),
--   PP (Printed as Passed)

ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'PCS';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'PCH';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'PL';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'RDS';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'RDH';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'RTS';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'RTH';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'ATS';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'ATH';
ALTER TYPE text_version_code_type ADD VALUE IF NOT EXISTS 'PP';
