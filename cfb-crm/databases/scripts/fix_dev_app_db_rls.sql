-- ============================================================
-- FIX DevLegacyLinkApp — RLS + team_config
-- Run once against DevLegacyLinkApp after create_dev_app_db.sql
-- failed on the fn_user_access and team_config steps.
-- ============================================================

USE DevLegacyLinkApp;
GO

-- ─── Fix RLS ─────────────────────────────────────────────────
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'user_access_policy')
BEGIN
  DROP SECURITY POLICY dbo.user_access_policy;
  PRINT 'Dropped user_access_policy';
END
GO

-- Drop old broken function if it exists
IF OBJECT_ID('dbo.fn_user_access', 'IF') IS NOT NULL
BEGIN
  DROP FUNCTION dbo.fn_user_access;
  PRINT 'Dropped old fn_user_access';
END
GO

CREATE FUNCTION dbo.fn_user_access(
  @session_user_id   NVARCHAR(100),
  @session_user_role NVARCHAR(50),
  @row_sport_id      UNIQUEIDENTIFIER,
  @row_user_id       UNIQUEIDENTIFIER,
  @row_status_id     INT
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
  SELECT 1 AS access_granted
  WHERE
    EXISTS (
      SELECT 1 FROM dbo.user_roles ur
      WHERE ur.user_id    = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
        AND ur.sport_id   = @row_sport_id
        AND ur.role       = 'coach_admin'
        AND ur.revoked_at IS NULL
    )
    OR
    (
      @row_status_id = 1
      AND EXISTS (
        SELECT 1 FROM dbo.user_roles ur
        WHERE ur.user_id    = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
          AND ur.sport_id   = @row_sport_id
          AND ur.role       = 'roster_only_admin'
          AND ur.revoked_at IS NULL
      )
    )
    OR
    @row_user_id = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
    OR
    (
      @row_sport_id IS NULL
      AND TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER) IS NOT NULL
    );
GO

CREATE SECURITY POLICY dbo.user_access_policy
  ADD FILTER PREDICATE dbo.fn_user_access(
    CAST(SESSION_CONTEXT(N'user_id')   AS NVARCHAR(100)),
    CAST(SESSION_CONTEXT(N'user_role') AS NVARCHAR(50)),
    sport_id,
    id,
    status_id
  ) ON dbo.users
WITH (STATE = ON);
PRINT 'Created RLS policy: user_access_policy';
GO

-- ─── Fix team_config in LegacyLinkGlobal ─────────────────────
USE LegacyLinkGlobal;
GO

DECLARE @TeamId UNIQUEIDENTIFIER = (SELECT id FROM dbo.teams WHERE abbr = 'LL-DEV');

IF @TeamId IS NULL
BEGIN
  SET @TeamId = NEWID();
  INSERT INTO dbo.teams (id, name, abbr, sport, level, app_db, db_server, subscription_tier)
  VALUES (@TeamId, 'LegacyLink Dev', 'LL-DEV', 'football', 'college',
          'DevLegacyLinkApp', 'localhost\SQLEXPRESS', 'starter');
  PRINT 'Registered LL-DEV team';
END
ELSE
  PRINT 'LL-DEV team already registered';

IF NOT EXISTS (SELECT 1 FROM dbo.team_config WHERE team_id = @TeamId)
BEGIN
  INSERT INTO dbo.team_config (
    team_id, team_name, team_abbr, sport, level,
    color_primary,      color_primary_dark,  color_primary_light,
    color_accent,       color_accent_dark,   color_accent_light,
    roster_label, alumni_label, class_label,
    positions_json, academic_years_json
  )
  VALUES (
    @TeamId, 'LegacyLink Dev', 'LL-DEV', 'football', 'college',
    '#1B1B2F', '#0D0D1A', '#EAEAF2',
    '#B8973D', '#9A7A2B', '#F5EDD5',
    'Roster', 'Alumni', 'Recruiting Class',
    '["QB","RB","WR","TE","OL","DL","LB","DB","K","P","LS","ATH"]',
    '["freshman","sophomore","junior","senior","graduate"]'
  );
  PRINT 'Seeded team_config for LL-DEV';
END
ELSE
  PRINT 'team_config for LL-DEV already exists';
GO

PRINT '=== DevLegacyLinkApp RLS + team_config fix complete ===';
GO
