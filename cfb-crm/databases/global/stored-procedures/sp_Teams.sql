-- ============================================================
-- GLOBAL DB — TEAMS STORED PROCEDURES
-- Run this file on: CfbGlobal database
-- Run after: 009_drop_legacy_db_columns.sql
-- ============================================================

-- ============================================================
-- sp_GetTeams
-- Returns all teams. Pass @IncludeInactive = 1 to include
-- deactivated teams (for super-admin views).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetTeams
  @IncludeInactive BIT = 0
AS
BEGIN
  SET NOCOUNT ON;

  SELECT
    id,
    name,
    abbr,
    sport,
    level,
    app_db            AS appDb,
    db_server         AS dbServer,
    subscription_tier AS subscriptionTier,
    is_active         AS isActive,
    created_at        AS createdAt,
    expires_at        AS expiresAt
  FROM  dbo.teams
  WHERE @IncludeInactive = 1 OR is_active = 1
  ORDER BY name;
END;
GO

-- ============================================================
-- sp_GetTeamById
-- Returns a single team by primary key.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetTeamById
  @TeamId    UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.teams WHERE id = @TeamId)
  BEGIN
    SET @ErrorCode = 'TEAM_NOT_FOUND';
    RETURN;
  END

  SELECT
    id,
    name,
    abbr,
    sport,
    level,
    app_db            AS appDb,
    db_server         AS dbServer,
    subscription_tier AS subscriptionTier,
    is_active         AS isActive,
    created_at        AS createdAt,
    expires_at        AS expiresAt
  FROM dbo.teams
  WHERE id = @TeamId;
END;
GO

-- ============================================================
-- sp_CreateTeam
-- Creates a new team record. Enforces unique abbreviation.
-- Called by the platform-admin onboarding flow.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateTeam
  @Name             NVARCHAR(100),
  @Abbr             NVARCHAR(10),
  @Sport            NVARCHAR(50)     = 'football',
  @Level            NVARCHAR(20)     = 'college',
  @AppDb            NVARCHAR(150),
  @DbServer         NVARCHAR(200)    = 'localhost\SQLEXPRESS',
  @SubscriptionTier NVARCHAR(20)     = 'starter',
  @ExpiresAt        DATETIME2        = NULL,
  @CreatedBy        UNIQUEIDENTIFIER,
  -- Outputs
  @NewTeamId        UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode        NVARCHAR(50)     OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  SET @ErrorCode = NULL;

  IF @Level NOT IN ('college', 'high_school', 'club')
  BEGIN
    SET @ErrorCode = 'INVALID_LEVEL';
    RETURN;
  END

  IF @SubscriptionTier NOT IN ('starter', 'pro', 'enterprise')
  BEGIN
    SET @ErrorCode = 'INVALID_TIER';
    RETURN;
  END

  IF EXISTS (SELECT 1 FROM dbo.teams WHERE abbr = @Abbr)
  BEGIN
    SET @ErrorCode = 'ABBR_ALREADY_EXISTS';
    RETURN;
  END

  SET @NewTeamId = NEWID();

  INSERT INTO dbo.teams (id, name, abbr, sport, level, app_db, db_server, subscription_tier, expires_at)
  VALUES (@NewTeamId, @Name, @Abbr, @Sport, @Level, @AppDb, @DbServer, @SubscriptionTier, @ExpiresAt);

  INSERT INTO dbo.audit_log (actor_id, action, target_type, target_id, payload)
  VALUES (
    @CreatedBy, 'team_created', 'team', CAST(@NewTeamId AS NVARCHAR(100)),
    JSON_OBJECT(
      'name':  @Name,
      'abbr':  @Abbr,
      'sport': @Sport,
      'level': @Level,
      'tier':  @SubscriptionTier
    )
  );
END;
GO

-- ============================================================
-- sp_UpdateTeam
-- Updates team details. NULL params = no change (PATCH semantics).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateTeam
  @TeamId           UNIQUEIDENTIFIER,
  @Name             NVARCHAR(100) = NULL,
  @Abbr             NVARCHAR(10)  = NULL,
  @Sport            NVARCHAR(50)  = NULL,
  @Level            NVARCHAR(20)  = NULL,
  @AppDb            NVARCHAR(150) = NULL,
  @DbServer         NVARCHAR(200) = NULL,
  @SubscriptionTier NVARCHAR(20)  = NULL,
  @IsActive         BIT           = NULL,
  @ExpiresAt        DATETIME2     = NULL,
  @ActorId          UNIQUEIDENTIFIER,
  -- Output
  @ErrorCode        NVARCHAR(50)  OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.teams WHERE id = @TeamId)
  BEGIN
    SET @ErrorCode = 'TEAM_NOT_FOUND';
    RETURN;
  END

  IF @Level IS NOT NULL AND @Level NOT IN ('college', 'high_school', 'club')
  BEGIN
    SET @ErrorCode = 'INVALID_LEVEL';
    RETURN;
  END

  IF @SubscriptionTier IS NOT NULL AND @SubscriptionTier NOT IN ('starter', 'pro', 'enterprise')
  BEGIN
    SET @ErrorCode = 'INVALID_TIER';
    RETURN;
  END

  DECLARE @Before NVARCHAR(MAX);
  SELECT @Before = JSON_OBJECT(
    'name':    name,
    'abbr':    abbr,
    'isActive': CAST(is_active AS NVARCHAR(5))
  )
  FROM dbo.teams WHERE id = @TeamId;

  UPDATE dbo.teams SET
    name              = COALESCE(@Name,             name),
    abbr              = COALESCE(@Abbr,             abbr),
    sport             = COALESCE(@Sport,            sport),
    level             = COALESCE(@Level,            level),
    app_db            = COALESCE(@AppDb,            app_db),
    db_server         = COALESCE(@DbServer,         db_server),
    subscription_tier = COALESCE(@SubscriptionTier, subscription_tier),
    is_active         = COALESCE(@IsActive,         is_active),
    expires_at        = COALESCE(@ExpiresAt,        expires_at)
  WHERE id = @TeamId;

  INSERT INTO dbo.audit_log (actor_id, action, target_type, target_id, payload)
  VALUES (
    @ActorId, 'team_updated', 'team', CAST(@TeamId AS NVARCHAR(100)),
    JSON_OBJECT('before': @Before)
  );
END;
GO
