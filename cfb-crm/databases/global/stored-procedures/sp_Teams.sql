-- ============================================================
-- GLOBAL DB — TEAMS STORED PROCEDURES
-- Run this file on: CfbGlobal database
-- Run after: 004_multi_tenant.sql
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
    roster_db         AS rosterDb,
    alumni_db         AS alumniDb,
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
    roster_db         AS rosterDb,
    alumni_db         AS alumniDb,
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
-- Called by the LegacyLink super-admin onboarding flow when
-- provisioning a new client.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateTeam
  @Name             NVARCHAR(100),
  @Abbr             NVARCHAR(10),
  @Sport            NVARCHAR(50)     = 'football',
  @Level            NVARCHAR(20)     = 'college',
  @RosterDb         NVARCHAR(100),
  @AlumniDb         NVARCHAR(100),
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

  -- Validate level
  IF @Level NOT IN ('college', 'high_school', 'club')
  BEGIN
    SET @ErrorCode = 'INVALID_LEVEL';
    RETURN;
  END

  -- Validate subscription tier
  IF @SubscriptionTier NOT IN ('starter', 'pro', 'enterprise')
  BEGIN
    SET @ErrorCode = 'INVALID_TIER';
    RETURN;
  END

  -- Enforce unique abbreviation
  IF EXISTS (SELECT 1 FROM dbo.teams WHERE abbr = @Abbr)
  BEGIN
    SET @ErrorCode = 'ABBR_ALREADY_EXISTS';
    RETURN;
  END

  SET @NewTeamId = NEWID();

  INSERT INTO dbo.teams (id, name, abbr, sport, level, roster_db, alumni_db, db_server, subscription_tier, expires_at)
  VALUES (@NewTeamId, @Name, @Abbr, @Sport, @Level, @RosterDb, @AlumniDb, @DbServer, @SubscriptionTier, @ExpiresAt);

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
  @RosterDb         NVARCHAR(100) = NULL,
  @AlumniDb         NVARCHAR(100) = NULL,
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

  -- Capture before state for audit
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
    roster_db         = COALESCE(@RosterDb,         roster_db),
    alumni_db         = COALESCE(@AlumniDb,         alumni_db),
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

-- ============================================================
-- sp_Login  (updated — adds teamId + team details to UserJson)
-- Validates credentials, returns user + app permissions + team
-- as JSON. The API signs the JWT from this payload — no
-- credential logic ever touches application code.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_Login
  @Email       NVARCHAR(255),
  @IpAddress   NVARCHAR(50)   = NULL,
  @DeviceInfo  NVARCHAR(255)  = NULL,
  -- Outputs
  @UserId       UNIQUEIDENTIFIER OUTPUT,
  @PasswordHash NVARCHAR(255)    OUTPUT,
  @UserJson     NVARCHAR(MAX)    OUTPUT,  -- full user + permissions + team payload
  @ErrorCode    NVARCHAR(50)     OUTPUT   -- NULL = success
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  -- Fetch user
  SELECT
    @UserId       = u.id,
    @PasswordHash = u.password_hash
  FROM dbo.users u
  WHERE u.email = @Email;

  IF @UserId IS NULL
  BEGIN
    SET @ErrorCode = 'USER_NOT_FOUND';
    RETURN;
  END

  -- Check account is active
  IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId AND is_active = 1)
  BEGIN
    SET @ErrorCode = 'ACCOUNT_INACTIVE';
    RETURN;
  END

  -- Build user + permissions + team JSON (API signs the JWT from this)
  SELECT @UserJson = (
    SELECT
      u.id,
      u.email,
      u.first_name    AS firstName,
      u.last_name     AS lastName,
      u.global_role   AS globalRole,
      u.is_active     AS isActive,
      u.created_at    AS createdAt,
      -- Team context embedded in every token
      u.team_id       AS teamId,
      t.name          AS teamName,
      t.abbr          AS teamAbbr,
      t.roster_db     AS rosterDb,
      t.alumni_db     AS alumniDb,
      t.db_server     AS dbServer,
      (
        SELECT
          ap.app_name   AS app,
          ap.role,
          ap.granted_at AS grantedAt,
          ap.granted_by AS grantedBy
        FROM dbo.app_permissions ap
        WHERE ap.user_id    = u.id
          AND ap.revoked_at IS NULL
        FOR JSON PATH
      ) AS appPermissions
    FROM dbo.users u
    LEFT JOIN dbo.teams t ON t.id = u.team_id
    WHERE u.id = @UserId
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
  );

  -- Update last login + write audit
  UPDATE dbo.users
  SET last_login_at = SYSUTCDATETIME()
  WHERE id = @UserId;

  INSERT INTO dbo.audit_log (actor_id, actor_email, action, target_type, target_id, ip_address, payload)
  SELECT @UserId, @Email, 'login', 'user', CAST(@UserId AS NVARCHAR(100)), @IpAddress,
    JSON_OBJECT('device': ISNULL(@DeviceInfo, ''));
END;
GO

-- ============================================================
-- sp_CreateUser  (updated — accepts and stores @TeamId)
-- Creates a user account and optionally grants initial app
-- permissions. Password hashing stays in application code.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateUser
  @Email         NVARCHAR(255),
  @PasswordHash  NVARCHAR(255),
  @FirstName     NVARCHAR(100),
  @LastName      NVARCHAR(100),
  @GlobalRole    NVARCHAR(50),
  @CreatedBy     UNIQUEIDENTIFIER,
  @TeamId        UNIQUEIDENTIFIER = NULL,  -- NULL = no team assignment yet
  -- Optional: immediately grant access to an app
  @GrantAppName  NVARCHAR(50)     = NULL,
  @GrantAppRole  NVARCHAR(50)     = NULL,
  -- Outputs
  @NewUserId     UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode     NVARCHAR(50)     OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  SET @ErrorCode = NULL;

  -- Validate role
  IF @GlobalRole NOT IN ('global_admin','app_admin','coach_staff','player','readonly')
  BEGIN
    SET @ErrorCode = 'INVALID_ROLE';
    RETURN;
  END

  -- Validate team if provided
  IF @TeamId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.teams WHERE id = @TeamId AND is_active = 1)
  BEGIN
    SET @ErrorCode = 'TEAM_NOT_FOUND';
    RETURN;
  END

  -- Duplicate email check
  IF EXISTS (SELECT 1 FROM dbo.users WHERE email = @Email)
  BEGIN
    SET @ErrorCode = 'EMAIL_ALREADY_EXISTS';
    RETURN;
  END

  BEGIN TRANSACTION;

    SET @NewUserId = NEWID();

    INSERT INTO dbo.users (id, email, password_hash, first_name, last_name, global_role, team_id)
    VALUES (@NewUserId, @Email, @PasswordHash, @FirstName, @LastName, @GlobalRole, @TeamId);

    -- Optionally grant app permission immediately
    IF @GrantAppName IS NOT NULL AND @GrantAppRole IS NOT NULL
    BEGIN
      INSERT INTO dbo.app_permissions (user_id, app_name, role, granted_by)
      VALUES (@NewUserId, @GrantAppName, @GrantAppRole, @CreatedBy);
    END

    -- Audit
    INSERT INTO dbo.audit_log (actor_id, action, target_type, target_id, payload)
    VALUES (
      @CreatedBy, 'user_created', 'user', CAST(@NewUserId AS NVARCHAR(100)),
      JSON_OBJECT(
        'email':       @Email,
        'globalRole':  @GlobalRole,
        'teamId':      ISNULL(CAST(@TeamId AS NVARCHAR(100)), ''),
        'grantedApp':  ISNULL(@GrantAppName, ''),
        'grantedRole': ISNULL(@GrantAppRole, '')
      )
    );

  COMMIT TRANSACTION;
END;
GO
