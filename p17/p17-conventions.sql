-- =============================================================================
-- P17 SUPABASE CONVENTIONS
-- =============================================================================
-- This file documents and enforces the standard patterns used across all
-- Phaze17 projects. Every new project schema should follow these conventions.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. STANDARD AUDIT COLUMNS
-- -----------------------------------------------------------------------------
-- Every P17 table ships with these. No exceptions.
--
-- created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
-- updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
-- created_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL
--
-- Example:
CREATE TABLE IF NOT EXISTS p17_example (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL
);


-- -----------------------------------------------------------------------------
-- 2. AUTO-UPDATE updated_at TRIGGER
-- -----------------------------------------------------------------------------
-- Attach this to every table. Create the function once, reuse everywhere.

CREATE OR REPLACE FUNCTION p17_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Usage per table:
-- CREATE TRIGGER set_updated_at
-- BEFORE UPDATE ON <your_table>
-- FOR EACH ROW EXECUTE FUNCTION p17_set_updated_at();


-- -----------------------------------------------------------------------------
-- 3. TABLE NAMING CONVENTIONS
-- -----------------------------------------------------------------------------
-- All tables are prefixed by project shortcode:
--
--   dj_*        Doc Jock
--   mc_*        MetaCrate
--   p17_*       Platform / shared ecosystem tables
--   c17_*       C17 agent
--
-- Use snake_case. No camelCase. No ambiguous names.
-- Good:  dj_documents, dj_document_chunks, p17_users
-- Bad:   Documents, docChunks, data


-- -----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS) — STANDARD TEMPLATES
-- -----------------------------------------------------------------------------
-- RLS is ALWAYS enabled on every table. No exceptions.
-- These templates cover the most common access patterns.

-- 4a. User-owned rows (each user sees only their own data)

-- ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;

-- CREATE POLICY "Users can view own rows"
--   ON <table> FOR SELECT
--   USING (auth.uid() = created_by);

-- CREATE POLICY "Users can insert own rows"
--   ON <table> FOR INSERT
--   WITH CHECK (auth.uid() = created_by);

-- CREATE POLICY "Users can update own rows"
--   ON <table> FOR UPDATE
--   USING (auth.uid() = created_by);

-- CREATE POLICY "Users can delete own rows"
--   ON <table> FOR DELETE
--   USING (auth.uid() = created_by);


-- 4b. Service role bypass (for backend/admin operations)
-- The service role key bypasses RLS automatically in Supabase.
-- Never expose the service role key client-side. Ever.


-- 4c. DEV_MODE bypass (local development only)
-- When DEV_MODE=true, the FastAPI backend skips auth checks.
-- This is implemented at the application layer, NOT in the database.
-- The DB always enforces RLS — DEV_MODE is an app-level convenience only.
-- DO NOT replicate DEV_MODE logic into database policies.


-- -----------------------------------------------------------------------------
-- 5. INDEXES — STANDARD PATTERNS
-- -----------------------------------------------------------------------------
-- Always index foreign keys and any column used in WHERE clauses frequently.

-- CREATE INDEX idx_<table>_created_by ON <table>(created_by);
-- CREATE INDEX idx_<table>_created_at ON <table>(created_at DESC);


-- -----------------------------------------------------------------------------
-- 6. SOFT DELETES (optional but preferred for P17 projects)
-- -----------------------------------------------------------------------------
-- Instead of hard deletes, mark rows as deleted.
-- Add to tables where audit trail matters:
--
--   deleted_at  TIMESTAMPTZ DEFAULT NULL
--
-- Filter in queries:
--   WHERE deleted_at IS NULL
--
-- RLS policy for soft deletes:
-- CREATE POLICY "Hide deleted rows"
--   ON <table> FOR SELECT
--   USING (deleted_at IS NULL AND auth.uid() = created_by);


-- =============================================================================
-- END P17 CONVENTIONS
-- =============================================================================
