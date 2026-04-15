-- Add columns to lis_members for storing senator details from the Senate XML feed.
-- These fields are populated by the LIS mapping refresher pipeline.
ALTER TABLE lis_members ADD COLUMN first_name TEXT;
ALTER TABLE lis_members ADD COLUMN last_name TEXT;
ALTER TABLE lis_members ADD COLUMN party TEXT;
ALTER TABLE lis_members ADD COLUMN state TEXT;
ALTER TABLE lis_members ADD COLUMN last_verified TIMESTAMPTZ;
