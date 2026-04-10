-- ============================================================
-- MIGRATION 012 — Cascade deletes from teams to dependents
-- Dropping a team now automatically removes:
--   - user_teams rows for that team
--   - team_config row for that team
-- Previously these FKs had no cascade action, causing DELETE
-- conflicts when trying to remove a team.
-- ============================================================

-- ── user_teams.team_id ────────────────────────────────────────
IF EXISTS (
  SELECT 1 FROM sys.foreign_keys
  WHERE name = 'FK_user_teams_teams'
    AND parent_object_id = OBJECT_ID('dbo.user_teams')
)
BEGIN
  ALTER TABLE dbo.user_teams DROP CONSTRAINT FK_user_teams_teams;
  ALTER TABLE dbo.user_teams
    ADD CONSTRAINT FK_user_teams_teams
    FOREIGN KEY (team_id) REFERENCES dbo.teams(id) ON DELETE CASCADE;
  PRINT 'Updated FK_user_teams_teams to ON DELETE CASCADE';
END
ELSE
  PRINT 'FK_user_teams_teams not found — skipping';
GO

-- ── team_config.team_id ───────────────────────────────────────
IF EXISTS (
  SELECT 1 FROM sys.foreign_keys
  WHERE name = 'FK_team_config_teams'
    AND parent_object_id = OBJECT_ID('dbo.team_config')
)
BEGIN
  ALTER TABLE dbo.team_config DROP CONSTRAINT FK_team_config_teams;
  ALTER TABLE dbo.team_config
    ADD CONSTRAINT FK_team_config_teams
    FOREIGN KEY (team_id) REFERENCES dbo.teams(id) ON DELETE CASCADE;
  PRINT 'Updated FK_team_config_teams to ON DELETE CASCADE';
END
ELSE
  PRINT 'FK_team_config_teams not found — skipping';
GO

PRINT '=== Migration 012 complete ===';
GO
