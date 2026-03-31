SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
-- ============================================================
-- APP DB — ADD SPORT + CLASSIFICATION COLUMNS
-- Adds sport_id, user_classification, and Starter-tier fields
-- to roster.players and alumni.alumni.
-- Run on: each tenant AppDB after 003_rbac_infrastructure.sql
--
-- NOTE: Statements that reference newly-added columns use
-- EXEC sp_executesql so they compile at runtime (not parse time).
-- ============================================================

-- ─── roster.players additions ────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('roster.players') AND name = 'sport_id')
BEGIN
  ALTER TABLE roster.players ADD sport_id UNIQUEIDENTIFIER NULL REFERENCES dbo.sports(id);
  EXEC sp_executesql N'CREATE INDEX IX_players_sport ON roster.players (sport_id) WHERE sport_id IS NOT NULL;';
  PRINT 'Added roster.players.sport_id';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('roster.players') AND name = 'user_classification')
BEGIN
  ALTER TABLE roster.players ADD user_classification NVARCHAR(20) NOT NULL DEFAULT 'roster';
  PRINT 'Added roster.players.user_classification';
END

-- ─── alumni.alumni additions ──────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('alumni.alumni') AND name = 'sport_id')
BEGIN
  ALTER TABLE alumni.alumni ADD sport_id UNIQUEIDENTIFIER NULL REFERENCES dbo.sports(id);
  EXEC sp_executesql N'CREATE INDEX IX_alumni_sport ON alumni.alumni (sport_id) WHERE sport_id IS NOT NULL;';
  PRINT 'Added alumni.alumni.sport_id';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('alumni.alumni') AND name = 'user_classification')
BEGIN
  ALTER TABLE alumni.alumni ADD user_classification NVARCHAR(20) NOT NULL DEFAULT 'alumni';
  PRINT 'Added alumni.alumni.user_classification';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('alumni.alumni') AND name = 'communication_consent')
BEGIN
  ALTER TABLE alumni.alumni ADD communication_consent BIT NOT NULL DEFAULT 1;
  PRINT 'Added alumni.alumni.communication_consent';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('alumni.alumni') AND name = 'original_player_id')
BEGIN
  -- original_player_id: canonical name per directive.
  -- source_player_id already exists as legacy column — keep both during transition.
  ALTER TABLE alumni.alumni ADD original_player_id UNIQUEIDENTIFIER NULL;
  -- Backfill via dynamic SQL so the column reference compiles at runtime
  EXEC sp_executesql N'UPDATE alumni.alumni SET original_player_id = source_player_id WHERE original_player_id IS NULL AND source_player_id IS NOT NULL;';
  PRINT 'Added alumni.alumni.original_player_id (backfilled from source_player_id)';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('alumni.alumni') AND name = 'years_on_roster')
BEGIN
  ALTER TABLE alumni.alumni ADD years_on_roster NVARCHAR(50) NULL;
  PRINT 'Added alumni.alumni.years_on_roster';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('alumni.alumni') AND name = 'city')
BEGIN
  ALTER TABLE alumni.alumni ADD city  NVARCHAR(100) NULL;
  ALTER TABLE alumni.alumni ADD state NVARCHAR(50)  NULL;
  -- Backfill via dynamic SQL so the column references compile at runtime
  EXEC sp_executesql N'UPDATE alumni.alumni SET city = current_city, state = current_state WHERE city IS NULL AND current_city IS NOT NULL;';
  PRINT 'Added alumni.alumni.city + state (backfilled from current_city/current_state)';
END

PRINT '=== 004_add_sport_classification complete ===';
GO
