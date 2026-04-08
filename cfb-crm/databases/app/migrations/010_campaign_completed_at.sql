-- ============================================================
-- MIGRATION 010 — Add completed_at to outreach_campaigns
-- Run on: each tenant AppDB
-- ============================================================

IF NOT EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns'
    AND COLUMN_NAME = 'completed_at'
)
BEGIN
  ALTER TABLE dbo.outreach_campaigns ADD completed_at DATETIME2 NULL;
  PRINT 'Added completed_at to dbo.outreach_campaigns';
END
ELSE
  PRINT 'completed_at already exists — skipping';
GO

PRINT '=== Migration 010 complete ===';
GO
