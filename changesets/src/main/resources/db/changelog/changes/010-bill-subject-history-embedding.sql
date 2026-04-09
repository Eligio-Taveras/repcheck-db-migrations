-- changeset repcheck:010-bill-subject-history-embedding
-- comment: Add embedding column to bill_subject_history to match bill_subjects table
ALTER TABLE bill_subject_history ADD COLUMN embedding vector(1536);
