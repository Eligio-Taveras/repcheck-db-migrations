-- Migration 022: Expand vote_method_type enum
-- Adds 3 new vote-method values encountered in Congress.gov House vote API responses:
--   yea-and-nay (standard yea/nay roll call)
--   2/3 yea-and-nay (veto override / suspension-of-rules; requires 2/3 majority)
--   quorum call (procedural presence-check; not a substantive vote)
--
-- New values are lowercased to match the existing convention of vote_method_type
-- (which uses 'recorded vote', 'voice vote', etc. — lowercase). VoteMethod.fromString
-- is case-insensitive so the API's title-case strings still decode correctly.

ALTER TYPE vote_method_type ADD VALUE IF NOT EXISTS 'yea-and-nay';
ALTER TYPE vote_method_type ADD VALUE IF NOT EXISTS '2/3 yea-and-nay';
ALTER TYPE vote_method_type ADD VALUE IF NOT EXISTS 'quorum call';
