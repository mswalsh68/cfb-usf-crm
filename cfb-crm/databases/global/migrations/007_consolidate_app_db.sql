-- ============================================================
-- MIGRATION 007 — Consolidate to Single AppDB per Tenant
-- Run on: LegacyLinkGlobal database
-- Replaces roster_db + alumni_db with a single app_db column.
-- ============================================================

USE LegacyLinkGlobal
GO
-- ─── 1. Add app_db column ─────────────────────────────────────

IF NOT EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'teams' AND COLUMN_NAME = 'app_db'
)
BEGIN
  ALTER TABLE dbo.teams ADD app_db NVARCHAR(150) NULL;
  PRINT 'Added app_db column to dbo.teams';
END
ELSE
  PRINT 'app_db already exists — skipping';
GO

-- ─── 2. Populate app_db from existing tenant names ────────────
-- Convention: {TeamName}App  (e.g. USFBullsApp, PHSPanthersApp)
-- Update these values to match the actual DB names you created.

UPDATE dbo.teams SET app_db = 'USFBullsApp'     WHERE abbr = 'USF'  AND app_db IS NULL;
UPDATE dbo.teams SET app_db = 'PHSPanthersApp'  WHERE abbr = 'HSFC' AND app_db IS NULL;

PRINT CONCAT('Populated app_db for ', @@ROWCOUNT, ' team(s)');
GO

-- ─── 3. Make app_db NOT NULL once populated ───────────────────
-- Only run this after verifying all rows have app_db set.
-- Uncomment when ready:

-- ALTER TABLE dbo.teams ALTER COLUMN app_db NVARCHAR(150) NOT NULL;
-- PRINT 'Made app_db NOT NULL';
-- GO

-- ─── 4. (Optional) Drop old columns after migration verified ──
-- Run only after confirming the new AppDBs are live and working.
-- Uncomment when ready:

-- ALTER TABLE dbo.teams DROP COLUMN roster_db;
-- ALTER TABLE dbo.teams DROP COLUMN alumni_db;
-- PRINT 'Dropped roster_db and alumni_db columns';
-- GO

PRINT '=== Migration 007 complete ===';
GO
