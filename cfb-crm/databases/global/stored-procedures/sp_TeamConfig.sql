-- ============================================================
-- GLOBAL DB — TEAM CONFIG STORED PROCEDURES
-- Run this file on: CfbGlobal database
-- Run after: 002_team_config.sql, 005_user_teams.sql
-- ============================================================

-- ============================================================
-- sp_GetTeamConfig
-- Returns the config for a specific team by @TeamId.
-- Falls back to first row if @TeamId is NULL (backward compat).
-- Auto-seeds a default row if none exists for the team.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetTeamConfig
  @TeamId UNIQUEIDENTIFIER = NULL
AS
BEGIN
  SET NOCOUNT ON;

  -- If a specific team is requested, auto-seed defaults for it
  IF @TeamId IS NOT NULL
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.team_config WHERE team_id = @TeamId)
    BEGIN
      -- Seed from teams table so name/abbr are correct
      INSERT INTO dbo.team_config (team_id, team_name, team_abbr, sport, level)
      SELECT @TeamId, t.name, t.abbr, t.sport, t.level
      FROM dbo.teams t WHERE t.id = @TeamId;
    END

    SELECT TOP 1
      id,
      team_name                AS teamName,
      team_abbr                AS teamAbbr,
      sport,
      level,
      logo_url                 AS logoUrl,
      color_primary            AS colorPrimary,
      color_primary_dark       AS colorPrimaryDark,
      color_primary_light      AS colorPrimaryLight,
      color_accent             AS colorAccent,
      color_accent_dark        AS colorAccentDark,
      color_accent_light       AS colorAccentLight,
      positions_json           AS positionsJson,
      academic_years_json      AS academicYearsJson,
      alumni_label             AS alumniLabel,
      roster_label             AS rosterLabel,
      class_label              AS classLabel,
      email_from_address       AS emailFromAddress,
      email_from_name          AS emailFromName,
      email_reply_to           AS emailReplyTo,
      email_physical_address   AS emailPhysicalAddress,
      email_daily_send_limit   AS emailDailySendLimit,
      email_monthly_send_limit AS emailMonthlySendLimit,
      updated_at               AS updatedAt
    FROM dbo.team_config
    WHERE team_id = @TeamId;
  END
  ELSE
  BEGIN
    -- Backward compat: no team_id → return first row, auto-seed if empty
    IF NOT EXISTS (SELECT 1 FROM dbo.team_config)
    BEGIN
      INSERT INTO dbo.team_config (team_name, team_abbr) VALUES ('Team Portal', 'TEAM');
    END

    SELECT TOP 1
      id,
      team_name                AS teamName,
      team_abbr                AS teamAbbr,
      sport,
      level,
      logo_url                 AS logoUrl,
      color_primary            AS colorPrimary,
      color_primary_dark       AS colorPrimaryDark,
      color_primary_light      AS colorPrimaryLight,
      color_accent             AS colorAccent,
      color_accent_dark        AS colorAccentDark,
      color_accent_light       AS colorAccentLight,
      positions_json           AS positionsJson,
      academic_years_json      AS academicYearsJson,
      alumni_label             AS alumniLabel,
      roster_label             AS rosterLabel,
      class_label              AS classLabel,
      email_from_address       AS emailFromAddress,
      email_from_name          AS emailFromName,
      email_reply_to           AS emailReplyTo,
      email_physical_address   AS emailPhysicalAddress,
      email_daily_send_limit   AS emailDailySendLimit,
      email_monthly_send_limit AS emailMonthlySendLimit,
      updated_at               AS updatedAt
    FROM dbo.team_config
    ORDER BY created_at;
  END
END;
GO

-- ============================================================
-- sp_UpdateTeamConfig
-- Updates team config for a specific team. NULL params = no
-- change (PATCH semantics). Logo URL can be cleared with ''.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateTeamConfig
  @TeamId            UNIQUEIDENTIFIER = NULL,
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
  @AlumniLabel          NVARCHAR(50)  = NULL,
  @RosterLabel          NVARCHAR(50)  = NULL,
  @ClassLabel           NVARCHAR(50)  = NULL,
  @EmailFromAddress     NVARCHAR(255) = NULL,
  @EmailFromName        NVARCHAR(200) = NULL,
  @EmailReplyTo         NVARCHAR(255) = NULL,
  @EmailPhysicalAddress NVARCHAR(500) = NULL,
  @EmailDailySendLimit  INT           = NULL,
  @EmailMonthlySendLimit INT          = NULL,
  @ErrorCode            NVARCHAR(50)  OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF @Level IS NOT NULL AND @Level NOT IN ('college', 'high_school', 'club')
  BEGIN
    SET @ErrorCode = 'INVALID_LEVEL';
    RETURN;
  END

  -- Auto-seed if the team has no config row yet
  IF @TeamId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.team_config WHERE team_id = @TeamId)
  BEGIN
    INSERT INTO dbo.team_config (team_id, team_name, team_abbr, sport, level)
    SELECT @TeamId, t.name, t.abbr, t.sport, t.level
    FROM dbo.teams t WHERE t.id = @TeamId;
  END
  ELSE IF @TeamId IS NULL AND NOT EXISTS (SELECT 1 FROM dbo.team_config)
  BEGIN
    INSERT INTO dbo.team_config (team_name, team_abbr) VALUES ('Team Portal', 'TEAM');
  END

  UPDATE dbo.team_config SET
    team_name           = COALESCE(@TeamName,          team_name),
    team_abbr           = COALESCE(@TeamAbbr,          team_abbr),
    sport               = COALESCE(@Sport,             sport),
    level               = COALESCE(@Level,             level),
    logo_url            = CASE
                            WHEN @LogoUrl IS NULL THEN logo_url
                            WHEN @LogoUrl = ''    THEN NULL
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
    alumni_label             = COALESCE(@AlumniLabel,           alumni_label),
    roster_label             = COALESCE(@RosterLabel,           roster_label),
    class_label              = COALESCE(@ClassLabel,            class_label),
    email_from_address       = COALESCE(@EmailFromAddress,      email_from_address),
    email_from_name          = COALESCE(@EmailFromName,         email_from_name),
    email_reply_to           = COALESCE(@EmailReplyTo,          email_reply_to),
    email_physical_address   = COALESCE(@EmailPhysicalAddress,  email_physical_address),
    email_daily_send_limit   = COALESCE(@EmailDailySendLimit,   email_daily_send_limit),
    email_monthly_send_limit = COALESCE(@EmailMonthlySendLimit, email_monthly_send_limit),
    updated_at               = SYSUTCDATETIME()
  WHERE (@TeamId IS NULL AND id = (SELECT TOP 1 id FROM dbo.team_config ORDER BY created_at))
     OR (team_id = @TeamId);
END;
GO
