-- ============================================================
-- MIGRATION 011 — Drop users.team_id (superseded by user_teams)
-- The user_teams junction table is the source of truth for
-- user-to-team relationships. users.team_id is a legacy column
-- left over from before migration 005 introduced user_teams.
-- Dropping it also removes the FK that blocked team deletions.
-- ============================================================

IF EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users' AND COLUMN_NAME = 'team_id'
)
BEGIN
  -- Drop FK constraint first
  DECLARE @fk NVARCHAR(200);
  SELECT @fk = name FROM sys.foreign_keys
  WHERE parent_object_id = OBJECT_ID('dbo.users') AND name LIKE '%team%';

  IF @fk IS NOT NULL
    EXEC('ALTER TABLE dbo.users DROP CONSTRAINT [' + @fk + ']');

  -- Drop index if present
  IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.users') AND name = 'IX_users_team_id')
    DROP INDEX IX_users_team_id ON dbo.users;

  ALTER TABLE dbo.users DROP COLUMN team_id;
  PRINT 'Dropped users.team_id (use user_teams junction table instead)';
END
ELSE
  PRINT 'users.team_id does not exist — skipping';
GO

PRINT '=== Migration 011 complete ===';
GO
