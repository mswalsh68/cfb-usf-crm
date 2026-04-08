-- ============================================================
-- MIGRATION 010 — Enforce app_db NOT NULL on teams
-- Run on: LegacyLinkGlobal / DevLegacyLinkGlobal
-- Prerequisites: All rows in dbo.teams must have app_db set.
-- Migration 007 added app_db as nullable; this completes the
-- intent by enforcing NOT NULL now that all tenants are live.
-- ============================================================

-- Safety check: abort if any team still has a NULL app_db.
IF EXISTS (SELECT 1 FROM dbo.teams WHERE app_db IS NULL)
BEGIN
  DECLARE @msg NVARCHAR(500) = 'Migration 010 aborted: one or more rows in dbo.teams have NULL app_db. Populate app_db for all teams before running this migration.';
  RAISERROR(@msg, 16, 1);
  RETURN;
END
GO

-- Enforce NOT NULL
ALTER TABLE dbo.teams
  ALTER COLUMN app_db NVARCHAR(150) NOT NULL;

PRINT 'Migration 010: app_db column is now NOT NULL on dbo.teams';
GO
