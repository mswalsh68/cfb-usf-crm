-- ============================================================
-- GLOBAL DB — TEAM CONFIG STORED PROCEDURES
-- Run this file on: CfbGlobal database
-- Run after: 002_team_config.sql
-- ============================================================

-- ============================================================
-- sp_GetTeamConfig
-- Returns the single team configuration row.
-- Auto-inserts defaults if no row exists (safe to call anytime).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetTeamConfig
AS
BEGIN
  SET NOCOUNT ON;

  -- Auto-seed defaults if no config row exists
  IF NOT EXISTS (SELECT 1 FROM dbo.team_config)
  BEGIN
    INSERT INTO dbo.team_config (team_name, team_abbr) VALUES ('Team Portal', 'TEAM');
  END

  SELECT TOP 1
    id,
    team_name           AS teamName,
    team_abbr           AS teamAbbr,
    sport,
    level,
    logo_url            AS logoUrl,
    color_primary       AS colorPrimary,
    color_primary_dark  AS colorPrimaryDark,
    color_primary_light AS colorPrimaryLight,
    color_accent        AS colorAccent,
    color_accent_dark   AS colorAccentDark,
    color_accent_light  AS colorAccentLight,
    positions_json      AS positionsJson,
    academic_years_json AS academicYearsJson,
    alumni_label        AS alumniLabel,
    roster_label        AS rosterLabel,
    class_label         AS classLabel,
    updated_at          AS updatedAt
  FROM dbo.team_config;
END;
GO

-- ============================================================
-- sp_UpdateTeamConfig
-- Updates team config. NULL params = no change (PATCH semantics).
-- Logo URL can be explicitly cleared by passing empty string.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateTeamConfig
  @TeamName          NVARCHAR(100) = NULL,
  @TeamAbbr          NVARCHAR(10)  = NULL,
  @Sport             NVARCHAR(50)  = NULL,
  @Level             NVARCHAR(20)  = NULL,
  @LogoUrl           NVARCHAR(500) = NULL,
  @ColorPrimary      NVARCHAR(7)   = NULL,
  @ColorPrimaryDark  NVARCHAR(7)   = NULL,
  @ColorPrimaryLight NVARCHAR(7)   = NULL,
  @ColorAccent       NVARCHAR(7)   = NULL,
  @ColorAccentDark   NVARCHAR(7)   = NULL,
  @ColorAccentLight  NVARCHAR(7)   = NULL,
  @PositionsJson     NVARCHAR(MAX) = NULL,
  @AcademicYearsJson NVARCHAR(MAX) = NULL,
  @AlumniLabel       NVARCHAR(50)  = NULL,
  @RosterLabel       NVARCHAR(50)  = NULL,
  @ClassLabel        NVARCHAR(50)  = NULL,
  @ErrorCode         NVARCHAR(50)  OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  -- Validate level if provided
  IF @Level IS NOT NULL AND @Level NOT IN ('college', 'high_school', 'club')
  BEGIN
    SET @ErrorCode = 'INVALID_LEVEL';
    RETURN;
  END

  -- Auto-seed if missing
  IF NOT EXISTS (SELECT 1 FROM dbo.team_config)
  BEGIN
    INSERT INTO dbo.team_config (team_name, team_abbr) VALUES ('Team Portal', 'TEAM');
  END

  UPDATE dbo.team_config SET
    team_name           = COALESCE(@TeamName,          team_name),
    team_abbr           = COALESCE(@TeamAbbr,          team_abbr),
    sport               = COALESCE(@Sport,             sport),
    level               = COALESCE(@Level,             level),
    -- Logo URL: NULL param = no change, empty string = clear it
    logo_url            = CASE
                            WHEN @LogoUrl IS NULL    THEN logo_url
                            WHEN @LogoUrl = ''       THEN NULL
                            ELSE @LogoUrl
                          END,
    color_primary       = COALESCE(@ColorPrimary,      color_primary),
    color_primary_dark  = COALESCE(@ColorPrimaryDark,  color_primary_dark),
    color_primary_light = COALESCE(@ColorPrimaryLight, color_primary_light),
    color_accent        = COALESCE(@ColorAccent,       color_accent),
    color_accent_dark   = COALESCE(@ColorAccentDark,   color_accent_dark),
    color_accent_light  = COALESCE(@ColorAccentLight,  color_accent_light),
    positions_json      = COALESCE(@PositionsJson,     positions_json),
    academic_years_json = COALESCE(@AcademicYearsJson, academic_years_json),
    alumni_label        = COALESCE(@AlumniLabel,       alumni_label),
    roster_label        = COALESCE(@RosterLabel,       roster_label),
    class_label         = COALESCE(@ClassLabel,        class_label),
    updated_at          = SYSUTCDATETIME();
END;
GO
