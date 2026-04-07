-- ============================================================
-- MIGRATION 006 — Fix platform_owner role + team_config.team_id
-- Run on: LegacyLinkGlobal database
-- Run after: 005_user_teams.sql
-- ============================================================
-- Fixes from migration 005:
--   1. Drop the auto-generated CHECK constraint on users.global_role
--      that blocked setting role = 'platform_owner'
--   2. Ensure team_config.team_id column exists (may have failed in 005
--      if the filtered index syntax was unsupported on this SQL Server version)
--   3. Re-run the platform_owner seed that failed in step 1
-- ============================================================

USE LegacyLinkGlobal
GO

-- ─── 1. Fix global_role CHECK constraint ─────────────────────────────────────
-- Drop the auto-generated constraint and replace with one that includes
-- platform_owner. The SP already validates roles — the constraint is just
-- a belt-and-suspenders guard.

DECLARE @ConstraintName NVARCHAR(200);

SELECT @ConstraintName = cc.name
FROM sys.check_constraints cc
JOIN sys.columns c ON cc.parent_object_id = c.object_id AND cc.parent_column_id = c.column_id
JOIN sys.tables  t ON t.object_id = c.object_id
WHERE t.name   = 'users'
  AND c.name   = 'global_role';

IF @ConstraintName IS NOT NULL
BEGIN
  EXEC('ALTER TABLE dbo.users DROP CONSTRAINT [' + @ConstraintName + ']');
  PRINT CONCAT('Dropped CHECK constraint: ', @ConstraintName);
END
ELSE
  PRINT 'No CHECK constraint found on users.global_role — skipping drop';
GO

-- Add updated constraint that includes platform_owner
IF NOT EXISTS (
  SELECT 1 FROM sys.check_constraints cc
  JOIN sys.columns c ON cc.parent_object_id = c.object_id AND cc.parent_column_id = c.column_id
  JOIN sys.tables  t ON t.object_id = c.object_id
  WHERE t.name = 'users' AND c.name = 'global_role'
)
BEGIN
  ALTER TABLE dbo.users
    ADD CONSTRAINT CK_users_global_role
    CHECK (global_role IN ('platform_owner','global_admin','app_admin','coach_staff','player','readonly'));
  PRINT 'Added updated CK_users_global_role constraint (includes platform_owner)';
END
ELSE
  PRINT 'CHECK constraint already exists — skipping';
GO

-- ─── 2. Ensure team_config.team_id column exists ─────────────────────────────

IF NOT EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'team_config' AND COLUMN_NAME = 'team_id'
)
BEGIN
  ALTER TABLE dbo.team_config
    ADD team_id UNIQUEIDENTIFIER NULL
        CONSTRAINT FK_team_config_teams REFERENCES dbo.teams(id);
  PRINT 'Added team_id column to dbo.team_config';
END
ELSE
  PRINT 'team_config.team_id already exists — skipping';
GO

-- Add unique index without filter (compatible with all SQL Server versions)
IF NOT EXISTS (
  SELECT 1 FROM sys.indexes
  WHERE name = 'UQ_team_config_team_id'
    AND object_id = OBJECT_ID('dbo.team_config')
)
BEGIN
  CREATE UNIQUE INDEX UQ_team_config_team_id
    ON dbo.team_config (team_id)
    WHERE team_id IS NOT NULL;
  PRINT 'Created unique index UQ_team_config_team_id';
END
ELSE
  PRINT 'Index UQ_team_config_team_id already exists — skipping';
GO

-- ─── 3. Backfill team_config.team_id for USF ─────────────────────────────────

DECLARE @UsfTeamId UNIQUEIDENTIFIER = (SELECT id FROM dbo.teams WHERE abbr = 'USF');

IF @UsfTeamId IS NOT NULL
BEGIN
  UPDATE dbo.team_config
  SET    team_id = @UsfTeamId
  WHERE  team_id IS NULL
    AND  id = (SELECT TOP 1 id FROM dbo.team_config ORDER BY created_at);

  IF @@ROWCOUNT > 0
    PRINT 'Backfilled USF team_config.team_id';
  ELSE
    PRINT 'USF team_config already linked or no config row found';
END
ELSE
  PRINT 'USF team not found — skipping team_config backfill';
GO

-- ─── 4. Re-seed mswalsh68 as platform_owner ──────────────────────────────────

DECLARE @PlatformUserId UNIQUEIDENTIFIER = (
  SELECT id FROM dbo.users WHERE email = 'mswalsh68@gmail.com'
);

IF @PlatformUserId IS NOT NULL
BEGIN
  UPDATE dbo.users
  SET    global_role = 'platform_owner',
         updated_at  = SYSUTCDATETIME()
  WHERE  id = @PlatformUserId;

  PRINT CONCAT('Set mswalsh68@gmail.com global_role = platform_owner (', CAST(@PlatformUserId AS NVARCHAR(100)), ')');
END
ELSE
  PRINT 'mswalsh68@gmail.com not found — skipping';
GO

PRINT '=== Migration 006 complete ===';
GO
