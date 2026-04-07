-- ============================================================
-- MIGRATION 009 — Drop legacy roster_db and alumni_db columns
-- Run on: LegacyLinkGlobal database
-- These were replaced by the single app_db column in migration 007.
-- Safe to run after verifying app_db is populated for all teams.
-- ============================================================

USE LegacyLinkGlobal
GO

-- Verify all teams have app_db set before dropping
IF EXISTS (SELECT 1 FROM dbo.teams WHERE app_db IS NULL OR app_db = '')
BEGIN
  RAISERROR('One or more teams have no app_db value. Populate app_db before running this migration.', 16, 1);
  RETURN;
END
PRINT 'app_db verified for all teams — proceeding.';
GO

IF EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'teams' AND COLUMN_NAME = 'roster_db'
)
BEGIN
  ALTER TABLE dbo.teams DROP COLUMN roster_db;
  PRINT 'Dropped roster_db column.';
END
ELSE
  PRINT 'roster_db already gone — skipping.';
GO

IF EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'teams' AND COLUMN_NAME = 'alumni_db'
)
BEGIN
  ALTER TABLE dbo.teams DROP COLUMN alumni_db;
  PRINT 'Dropped alumni_db column.';
END
ELSE
  PRINT 'alumni_db already gone — skipping.';
GO

PRINT '=== Migration 009 complete ===';
GO
