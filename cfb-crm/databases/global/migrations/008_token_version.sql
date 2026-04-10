-- ============================================================
-- Migration 008: Per-user token version for session revocation
-- Run on: LegacyLinkGlobal database
-- ============================================================

USE LegacyLinkGlobal
GO

IF NOT EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users' AND COLUMN_NAME = 'token_version'
)
BEGIN
  ALTER TABLE dbo.users
    ADD token_version INT NOT NULL DEFAULT 1;
  PRINT 'Added token_version column';
END
ELSE
  PRINT 'token_version already exists — skipping';
GO
