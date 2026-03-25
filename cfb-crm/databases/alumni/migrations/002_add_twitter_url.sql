-- ALUMNI DB -- Migration 002
-- Run this file on: CfbAlumni database
-- Adds twitter_url column to alumni table
-- ============================================================

USE CfbAlumni;
GO

IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('dbo.alumni') AND name = 'twitter_url'
)
BEGIN
  ALTER TABLE dbo.alumni ADD twitter_url NVARCHAR(100) NULL;
  PRINT 'Added twitter_url column to dbo.alumni';
END
ELSE
BEGIN
  PRINT 'twitter_url column already exists — skipped';
END
GO
