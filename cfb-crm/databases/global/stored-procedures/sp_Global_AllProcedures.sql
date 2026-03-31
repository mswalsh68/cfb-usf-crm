-- ============================================================
-- GLOBAL DB — ALL STORED PROCEDURES
-- Run this file on: CfbGlobal database
-- Requires: HASHBYTES support (Azure SQL — built in)
-- Run after: 001_initial_schema.sql
-- ============================================================

-- ============================================================
-- sp_Login
-- Validates credentials; returns user + teams array + app
-- permissions as JSON. The API bcrypt-compares the password,
-- signs the JWT from the returned JSON. No cred logic in code.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_Login
  @Email       NVARCHAR(255),
  @IpAddress   NVARCHAR(50)   = NULL,
  @DeviceInfo  NVARCHAR(255)  = NULL,
  -- Outputs
  @UserId       UNIQUEIDENTIFIER OUTPUT,
  @PasswordHash NVARCHAR(255)    OUTPUT,
  @UserJson     NVARCHAR(MAX)    OUTPUT,  -- full user + teams + permissions payload
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

  DECLARE @GlobalRole NVARCHAR(50);
  SELECT @GlobalRole = global_role FROM dbo.users WHERE id = @UserId;

  -- Build teams JSON:
  --   platform_owner  -> all active teams
  --   everyone else   -> their user_teams rows
  DECLARE @TeamsJson NVARCHAR(MAX);

  IF @GlobalRole = 'platform_owner'
  BEGIN
    SELECT @TeamsJson = (
      SELECT
        t.id               AS teamId,
        t.abbr,
        t.name,
        'platform_owner'   AS role,
        tc.logo_url        AS logoUrl,
        ISNULL(tc.color_primary, '#006747') AS colorPrimary,
        ISNULL(tc.color_accent,  '#CFC493') AS colorAccent
      FROM dbo.teams t
      LEFT JOIN dbo.team_config tc ON tc.team_id = t.id
      WHERE t.is_active = 1
      ORDER BY t.name
      FOR JSON PATH
    );
  END
  ELSE
  BEGIN
    SELECT @TeamsJson = (
      SELECT
        t.id    AS teamId,
        t.abbr,
        t.name,
        ut.role,
        tc.logo_url AS logoUrl,
        ISNULL(tc.color_primary, '#006747') AS colorPrimary,
        ISNULL(tc.color_accent,  '#CFC493') AS colorAccent
      FROM dbo.user_teams ut
      JOIN  dbo.teams t        ON t.id      = ut.team_id
      LEFT JOIN dbo.team_config tc ON tc.team_id = t.id
      WHERE ut.user_id  = @UserId
        AND ut.is_active = 1
      ORDER BY t.name
      FOR JSON PATH
    );
  END

  IF @TeamsJson IS NULL SET @TeamsJson = '[]';

  -- Resolve current team (first alphabetically)
  DECLARE @CurrentTeamId UNIQUEIDENTIFIER;
  DECLARE @AppDb         NVARCHAR(100) = '';
  DECLARE @DbServer      NVARCHAR(200) = '';

  IF @GlobalRole = 'platform_owner'
  BEGIN
    SELECT TOP 1
      @CurrentTeamId = t.id,
      @AppDb         = t.app_db,
      @DbServer      = t.db_server
    FROM dbo.teams t
    WHERE t.is_active = 1
    ORDER BY t.name;
  END
  ELSE
  BEGIN
    SELECT TOP 1
      @CurrentTeamId = t.id,
      @AppDb         = t.app_db,
      @DbServer      = t.db_server
    FROM dbo.user_teams ut
    JOIN dbo.teams t ON t.id = ut.team_id
    WHERE ut.user_id  = @UserId
      AND ut.is_active = 1
    ORDER BY t.name;
  END

  -- Build full payload JSON
  SELECT @UserJson = (
    SELECT
      u.id,
      u.email,
      u.first_name                          AS firstName,
      u.last_name                           AS lastName,
      u.global_role                         AS globalRole,
      u.is_active                           AS isActive,
      u.created_at                          AS createdAt,
      CAST(@CurrentTeamId AS NVARCHAR(100)) AS currentTeamId,
      @AppDb                                AS appDb,
      @DbServer                             AS dbServer,
      JSON_QUERY(@TeamsJson)                AS teams,
      (
        SELECT
          ap.app_name   AS app,
          ap.role,
          ap.granted_at AS grantedAt,
          ap.granted_by AS grantedBy
        FROM dbo.app_permissions ap
        WHERE ap.user_id   = u.id
          AND ap.revoked_at IS NULL
        FOR JSON PATH
      ) AS appPermissions
    FROM dbo.users u
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
-- sp_StoreRefreshToken
-- Stores a hashed refresh token after successful login.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_StoreRefreshToken
  @UserId     UNIQUEIDENTIFIER,
  @TokenHash  NVARCHAR(255),
  @ExpiresAt  DATETIME2,
  @DeviceInfo NVARCHAR(255) = NULL
AS
BEGIN
  SET NOCOUNT ON;

  INSERT INTO dbo.refresh_tokens (user_id, token_hash, expires_at, device_info)
  VALUES (@UserId, @TokenHash, @ExpiresAt, @DeviceInfo);
END;
GO

-- ============================================================
-- sp_RefreshToken
-- Validates an existing refresh token, revokes it, issues a
-- new one. Returns fresh user payload including teams array.
-- Entire rotation is atomic — no partial state possible.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_RefreshToken
  @OldTokenHash  NVARCHAR(255),
  @NewTokenHash  NVARCHAR(255),
  @NewExpiresAt  DATETIME2,
  @CurrentTeamId UNIQUEIDENTIFIER = NULL,   -- client's active team; used to pin DB routing
  -- Outputs
  @UserJson      NVARCHAR(MAX) OUTPUT,
  @ErrorCode     NVARCHAR(50)  OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  SET @ErrorCode = NULL;

  DECLARE @UserId UNIQUEIDENTIFIER;

  BEGIN TRANSACTION;

    SELECT @UserId = user_id
    FROM dbo.refresh_tokens
    WHERE token_hash  = @OldTokenHash
      AND revoked_at  IS NULL
      AND expires_at  > SYSUTCDATETIME();

    IF @UserId IS NULL
    BEGIN
      ROLLBACK TRANSACTION;
      SET @ErrorCode = 'TOKEN_INVALID_OR_EXPIRED';
      RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId AND is_active = 1)
    BEGIN
      ROLLBACK TRANSACTION;
      SET @ErrorCode = 'ACCOUNT_INACTIVE';
      RETURN;
    END

    UPDATE dbo.refresh_tokens
    SET revoked_at = SYSUTCDATETIME()
    WHERE token_hash = @OldTokenHash;

    INSERT INTO dbo.refresh_tokens (user_id, token_hash, expires_at)
    VALUES (@UserId, @NewTokenHash, @NewExpiresAt);

  COMMIT TRANSACTION;

  -- Build fresh user payload (same structure as sp_Login)
  DECLARE @GlobalRole NVARCHAR(50);
  SELECT @GlobalRole = global_role FROM dbo.users WHERE id = @UserId;

  DECLARE @TeamsJson NVARCHAR(MAX);

  IF @GlobalRole = 'platform_owner'
  BEGIN
    SELECT @TeamsJson = (
      SELECT
        t.id               AS teamId,
        t.abbr,
        t.name,
        'platform_owner'   AS role,
        tc.logo_url        AS logoUrl,
        ISNULL(tc.color_primary, '#006747') AS colorPrimary,
        ISNULL(tc.color_accent,  '#CFC493') AS colorAccent
      FROM dbo.teams t
      LEFT JOIN dbo.team_config tc ON tc.team_id = t.id
      WHERE t.is_active = 1
      ORDER BY t.name
      FOR JSON PATH
    );
  END
  ELSE
  BEGIN
    SELECT @TeamsJson = (
      SELECT
        t.id    AS teamId,
        t.abbr,
        t.name,
        ut.role,
        tc.logo_url AS logoUrl,
        ISNULL(tc.color_primary, '#006747') AS colorPrimary,
        ISNULL(tc.color_accent,  '#CFC493') AS colorAccent
      FROM dbo.user_teams ut
      JOIN  dbo.teams t        ON t.id      = ut.team_id
      LEFT JOIN dbo.team_config tc ON tc.team_id = t.id
      WHERE ut.user_id  = @UserId
        AND ut.is_active = 1
      ORDER BY t.name
      FOR JSON PATH
    );
  END

  IF @TeamsJson IS NULL SET @TeamsJson = '[]';

  DECLARE @ResolvedTeamId UNIQUEIDENTIFIER;
  DECLARE @AppDb          NVARCHAR(100) = '';
  DECLARE @DbServer       NVARCHAR(200) = '';

  -- Try to pin to the client's requested team first (validates access too)
  IF @CurrentTeamId IS NOT NULL
  BEGIN
    SELECT TOP 1
      @CurrentTeamId = t.id,
      @AppDb         = t.app_db,
      @DbServer      = t.db_server
    FROM dbo.teams t
    WHERE t.is_active = 1
    ORDER BY t.name;
  END

  -- Fall back to first-alphabetical team if requested team not found / not provided
  IF @ResolvedTeamId IS NULL
  BEGIN
    SELECT TOP 1
      @CurrentTeamId = t.id,
      @AppDb         = t.app_db,
      @DbServer      = t.db_server
    FROM dbo.user_teams ut
    JOIN dbo.teams t ON t.id = ut.team_id
    WHERE ut.user_id  = @UserId
      AND ut.is_active = 1
    ORDER BY t.name;
  END

  SELECT @UserJson = (
    SELECT
      u.id,
      u.email,
      u.first_name                          AS firstName,
      u.last_name                           AS lastName,
      u.global_role                         AS globalRole,
      u.is_active                           AS isActive,
      CAST(@CurrentTeamId AS NVARCHAR(100)) AS currentTeamId,
      @AppDb                                AS appDb,
      @DbServer                             AS dbServer,
      JSON_QUERY(@TeamsJson)                AS teams,
      (
        SELECT ap.app_name AS app, ap.role, ap.granted_at AS grantedAt, ap.granted_by AS grantedBy
        FROM dbo.app_permissions ap
        WHERE ap.user_id = u.id AND ap.revoked_at IS NULL
        FOR JSON PATH
      ) AS appPermissions
    FROM dbo.users u
    WHERE u.id = @UserId
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
  );
END;
GO

-- ============================================================
-- sp_Logout
-- Revokes a refresh token by its hash.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_Logout
  @TokenHash NVARCHAR(255)
AS
BEGIN
  SET NOCOUNT ON;

  UPDATE dbo.refresh_tokens
  SET revoked_at = SYSUTCDATETIME()
  WHERE token_hash = @TokenHash
    AND revoked_at IS NULL;
END;
GO

-- ============================================================
-- sp_SwitchTeam
-- Validates a user can access @NewTeamId, returns team details
-- so the API can re-issue the JWT with updated currentTeamId.
-- platform_owner bypasses the user_teams membership check.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_SwitchTeam
  @UserId    UNIQUEIDENTIFIER,
  @NewTeamId UNIQUEIDENTIFIER,
  -- Outputs
  @TeamJson  NVARCHAR(MAX) OUTPUT,
  @ErrorCode NVARCHAR(50)  OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  SET @TeamJson  = NULL;

  -- Does the target team exist and is it active?
  IF NOT EXISTS (SELECT 1 FROM dbo.teams WHERE id = @NewTeamId AND is_active = 1)
  BEGIN
    SET @ErrorCode = 'TEAM_NOT_FOUND';
    RETURN;
  END

  -- Validate access (platform_owner bypasses user_teams check)
  DECLARE @GlobalRole NVARCHAR(50);
  SELECT @GlobalRole = global_role FROM dbo.users WHERE id = @UserId;

  IF @GlobalRole <> 'platform_owner'
  BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM dbo.user_teams
      WHERE user_id  = @UserId
        AND team_id  = @NewTeamId
        AND is_active = 1
    )
    BEGIN
      SET @ErrorCode = 'ACCESS_DENIED';
      RETURN;
    END
  END

  -- Return team details for JWT re-issue + ThemeProvider refresh
  SELECT @TeamJson = (
    SELECT
      t.id        AS teamId,
      t.name,
      t.abbr,
      t.app_db AS appDb,
      t.db_server AS dbServer,
      tc.logo_url            AS logoUrl,
      tc.color_primary       AS colorPrimary,
      tc.color_primary_dark  AS colorPrimaryDark,
      tc.color_primary_light AS colorPrimaryLight,
      tc.color_accent        AS colorAccent,
      tc.color_accent_dark   AS colorAccentDark,
      tc.color_accent_light  AS colorAccentLight,
      tc.positions_json      AS positionsJson,
      tc.academic_years_json AS academicYearsJson,
      tc.alumni_label        AS alumniLabel,
      tc.roster_label        AS rosterLabel,
      tc.class_label         AS classLabel
    FROM dbo.teams t
    LEFT JOIN dbo.team_config tc ON tc.team_id = t.id
    WHERE t.id = @NewTeamId
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
  );

  -- Audit the switch
  INSERT INTO dbo.audit_log (actor_id, action, target_type, target_id, payload)
  VALUES (
    @UserId, 'team_switch', 'team', CAST(@NewTeamId AS NVARCHAR(100)),
    JSON_OBJECT('isPlatformOwner': CASE WHEN @GlobalRole = 'platform_owner' THEN 'true' ELSE 'false' END)
  );
END;
GO

-- ============================================================
-- sp_GetUserTeams
-- Returns all teams a user has access to.
-- platform_owner gets all active teams.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetUserTeams
  @UserId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @GlobalRole NVARCHAR(50);
  SELECT @GlobalRole = global_role FROM dbo.users WHERE id = @UserId;

  IF @GlobalRole = 'platform_owner'
  BEGIN
    SELECT
      t.id               AS teamId,
      t.abbr,
      t.name,
      t.sport,
      t.level,
      t.is_active        AS isActive,
      'platform_owner'   AS role,
      tc.logo_url        AS logoUrl,
      ISNULL(tc.color_primary, '#006747') AS colorPrimary,
      ISNULL(tc.color_accent,  '#CFC493') AS colorAccent
    FROM dbo.teams t
    LEFT JOIN dbo.team_config tc ON tc.team_id = t.id
    WHERE t.is_active = 1
    ORDER BY t.name;
  END
  ELSE
  BEGIN
    SELECT
      t.id    AS teamId,
      t.abbr,
      t.name,
      t.sport,
      t.level,
      t.is_active     AS isActive,
      ut.role,
      tc.logo_url     AS logoUrl,
      ISNULL(tc.color_primary, '#006747') AS colorPrimary,
      ISNULL(tc.color_accent,  '#CFC493') AS colorAccent
    FROM dbo.user_teams ut
    JOIN  dbo.teams t        ON t.id      = ut.team_id
    LEFT JOIN dbo.team_config tc ON tc.team_id = t.id
    WHERE ut.user_id  = @UserId
      AND ut.is_active = 1
    ORDER BY t.name;
  END
END;
GO

-- ============================================================
-- sp_CreateUser
-- Creates a user and optionally grants initial app permissions.
-- Also inserts into user_teams when @TeamId is provided.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateUser
  @Email         NVARCHAR(255),
  @PasswordHash  NVARCHAR(255),
  @FirstName     NVARCHAR(100),
  @LastName      NVARCHAR(100),
  @GlobalRole    NVARCHAR(50),
  @CreatedBy     UNIQUEIDENTIFIER,
  @TeamId        UNIQUEIDENTIFIER = NULL,
  -- Optional: immediately grant access to an app
  @GrantAppName  NVARCHAR(50)  = NULL,
  @GrantAppRole  NVARCHAR(50)  = NULL,
  -- Output
  @NewUserId     UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode     NVARCHAR(50)      OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  SET @ErrorCode = NULL;

  IF @GlobalRole NOT IN ('global_admin','app_admin','coach_staff','player','readonly','platform_owner')
  BEGIN
    SET @ErrorCode = 'INVALID_ROLE';
    RETURN;
  END

  IF EXISTS (SELECT 1 FROM dbo.users WHERE email = @Email)
  BEGIN
    SET @ErrorCode = 'EMAIL_ALREADY_EXISTS';
    RETURN;
  END

  IF @TeamId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.teams WHERE id = @TeamId AND is_active = 1)
  BEGIN
    SET @ErrorCode = 'TEAM_NOT_FOUND';
    RETURN;
  END

  BEGIN TRANSACTION;

    SET @NewUserId = NEWID();

    INSERT INTO dbo.users (id, email, password_hash, first_name, last_name, global_role, team_id)
    VALUES (@NewUserId, @Email, @PasswordHash, @FirstName, @LastName, @GlobalRole, @TeamId);

    IF @TeamId IS NOT NULL
    BEGIN
      INSERT INTO dbo.user_teams (user_id, team_id, role)
      VALUES (
        @NewUserId,
        @TeamId,
        CASE @GlobalRole
          WHEN 'global_admin' THEN 'global_admin'
          WHEN 'app_admin'    THEN 'app_admin'
          WHEN 'coach_staff'  THEN 'coach_staff'
          ELSE 'readonly'
        END
      );
    END

    IF @GrantAppName IS NOT NULL AND @GrantAppRole IS NOT NULL
    BEGIN
      INSERT INTO dbo.app_permissions (user_id, app_name, role, granted_by)
      VALUES (@NewUserId, @GrantAppName, @GrantAppRole, @CreatedBy);
    END

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

-- ============================================================
-- sp_UpdateUser
-- Updates role and/or active status. Global admin only (enforced in API).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateUser
  @TargetUserId  UNIQUEIDENTIFIER,
  @GlobalRole    NVARCHAR(50)  = NULL,
  @IsActive      BIT           = NULL,
  @ActorId       UNIQUEIDENTIFIER,
  @ErrorCode     NVARCHAR(50)  OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @TargetUserId)
  BEGIN
    SET @ErrorCode = 'USER_NOT_FOUND';
    RETURN;
  END

  IF @GlobalRole IS NOT NULL AND @GlobalRole NOT IN ('global_admin','app_admin','coach_staff','player','readonly','platform_owner')
  BEGIN
    SET @ErrorCode = 'INVALID_ROLE';
    RETURN;
  END

  DECLARE @Before NVARCHAR(MAX);
  SELECT @Before = JSON_OBJECT('globalRole': global_role, 'isActive': CAST(is_active AS NVARCHAR))
  FROM dbo.users WHERE id = @TargetUserId;

  UPDATE dbo.users SET
    global_role = COALESCE(@GlobalRole, global_role),
    is_active   = COALESCE(@IsActive,   is_active),
    updated_at  = SYSUTCDATETIME()
  WHERE id = @TargetUserId;

  INSERT INTO dbo.audit_log (actor_id, action, target_type, target_id, payload)
  VALUES (
    @ActorId, 'user_updated', 'user', CAST(@TargetUserId AS NVARCHAR(100)),
    JSON_OBJECT('before': @Before, 'newRole': ISNULL(@GlobalRole,''), 'newActive': ISNULL(CAST(@IsActive AS NVARCHAR),''))
  );
END;
GO

-- ============================================================
-- sp_GrantPermission
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GrantPermission
  @UserId    UNIQUEIDENTIFIER,
  @AppName   NVARCHAR(50),
  @Role      NVARCHAR(50),
  @GrantedBy UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  SET @ErrorCode = NULL;

  IF @AppName NOT IN ('roster','alumni','global-admin')
  BEGIN
    SET @ErrorCode = 'INVALID_APP';
    RETURN;
  END

  IF @Role NOT IN ('global_admin','app_admin','coach_staff','player','readonly')
  BEGIN
    SET @ErrorCode = 'INVALID_ROLE';
    RETURN;
  END

  BEGIN TRANSACTION;

    UPDATE dbo.app_permissions
    SET revoked_at = SYSUTCDATETIME()
    WHERE user_id  = @UserId
      AND app_name = @AppName
      AND revoked_at IS NULL;

    INSERT INTO dbo.app_permissions (user_id, app_name, role, granted_by)
    VALUES (@UserId, @AppName, @Role, @GrantedBy);

    INSERT INTO dbo.audit_log (actor_id, action, target_type, target_id, payload)
    VALUES (
      @GrantedBy, 'permission_granted', 'user', CAST(@UserId AS NVARCHAR(100)),
      JSON_OBJECT('app': @AppName, 'role': @Role)
    );

  COMMIT TRANSACTION;
END;
GO

-- ============================================================
-- sp_RevokePermission
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_RevokePermission
  @UserId    UNIQUEIDENTIFIER,
  @AppName   NVARCHAR(50),
  @RevokedBy UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF NOT EXISTS (
    SELECT 1 FROM dbo.app_permissions
    WHERE user_id = @UserId AND app_name = @AppName AND revoked_at IS NULL
  )
  BEGIN
    SET @ErrorCode = 'PERMISSION_NOT_FOUND';
    RETURN;
  END

  UPDATE dbo.app_permissions
  SET revoked_at = SYSUTCDATETIME()
  WHERE user_id  = @UserId
    AND app_name = @AppName
    AND revoked_at IS NULL;

  INSERT INTO dbo.audit_log (actor_id, action, target_type, target_id, payload)
  VALUES (
    @RevokedBy, 'permission_revoked', 'user', CAST(@UserId AS NVARCHAR(100)),
    JSON_OBJECT('app': @AppName)
  );
END;
GO

-- ============================================================
-- sp_TransferPlayerToAlumni
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_TransferPlayerToAlumni
  @UserId    UNIQUEIDENTIFIER,
  @GrantedBy NVARCHAR(100)
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @GrantedByGuid UNIQUEIDENTIFIER = TRY_CAST(@GrantedBy AS UNIQUEIDENTIFIER);

  UPDATE dbo.app_permissions
  SET revoked_at = SYSUTCDATETIME()
  WHERE user_id  = @UserId
    AND app_name = 'roster'
    AND revoked_at IS NULL;

  IF NOT EXISTS (
    SELECT 1 FROM dbo.app_permissions
    WHERE user_id = @UserId AND app_name = 'alumni' AND revoked_at IS NULL
  )
  BEGIN
    INSERT INTO dbo.app_permissions (user_id, app_name, role, granted_by)
    VALUES (@UserId, 'alumni', 'readonly', @GrantedByGuid);
  END

  INSERT INTO dbo.audit_log (actor_id, action, target_type, target_id, payload)
  VALUES (
    @GrantedByGuid, 'player_graduated_to_alumni', 'user', CAST(@UserId AS NVARCHAR(100)),
    JSON_OBJECT('rosterRevoked': 'true', 'alumniGranted': 'true')
  );
END;
GO

-- ============================================================
-- sp_GetUsers
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetUsers
  @Search     NVARCHAR(255) = NULL,
  @GlobalRole NVARCHAR(50)  = NULL,
  @Page       INT           = 1,
  @PageSize   INT           = 50,
  @TotalCount INT           OUTPUT
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @Offset INT = (@Page - 1) * @PageSize;
  DECLARE @SearchWild NVARCHAR(257) = '%' + ISNULL(@Search, '') + '%';

  SELECT @TotalCount = COUNT(*)
  FROM dbo.users u
  WHERE (@Search IS NULL OR u.email LIKE @SearchWild OR u.first_name LIKE @SearchWild OR u.last_name LIKE @SearchWild)
    AND (@GlobalRole IS NULL OR u.global_role = @GlobalRole);

  SELECT
    u.id,
    u.email,
    u.first_name        AS firstName,
    u.last_name         AS lastName,
    u.global_role       AS globalRole,
    u.is_active         AS isActive,
    u.last_login_at     AS lastLoginAt,
    u.created_at        AS createdAt,
    (
      SELECT COUNT(*) FROM dbo.app_permissions ap
      WHERE ap.user_id = u.id AND ap.revoked_at IS NULL
    ) AS activePermissionCount
  FROM dbo.users u
  WHERE (@Search IS NULL OR u.email LIKE @SearchWild OR u.first_name LIKE @SearchWild OR u.last_name LIKE @SearchWild)
    AND (@GlobalRole IS NULL OR u.global_role = @GlobalRole)
  ORDER BY u.last_name, u.first_name
  OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- ============================================================
-- sp_GetUserPermissions
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetUserPermissions
  @UserId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;

  SELECT
    ap.id,
    ap.app_name      AS appName,
    ap.role,
    ap.granted_at    AS grantedAt,
    ap.revoked_at    AS revokedAt,
    gb.email         AS grantedByEmail,
    CASE WHEN ap.revoked_at IS NULL THEN 1 ELSE 0 END AS isActive
  FROM dbo.app_permissions ap
  JOIN dbo.users gb ON gb.id = ap.granted_by
  WHERE ap.user_id = @UserId
  ORDER BY ap.granted_at DESC;
END;
GO

-- ============================================================
-- sp_CreateInviteToken
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateInviteToken
  @UserId    UNIQUEIDENTIFIER,
  @TokenHash VARCHAR(128),
  @ExpiresAt DATETIME2
AS
BEGIN
  SET NOCOUNT ON;

  UPDATE dbo.invite_tokens
  SET    used_at = SYSUTCDATETIME()
  WHERE  user_id = @UserId AND used_at IS NULL;

  INSERT INTO dbo.invite_tokens (user_id, token_hash, expires_at)
  VALUES (@UserId, @TokenHash, @ExpiresAt);
END;
GO

-- ============================================================
-- sp_ValidateInviteToken
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ValidateInviteToken
  @TokenHash VARCHAR(128)
AS
BEGIN
  SET NOCOUNT ON;

  SELECT u.first_name AS firstName, u.last_name AS lastName, u.email
  FROM   dbo.invite_tokens it
  JOIN   dbo.users u ON u.id = it.user_id
  WHERE  it.token_hash = @TokenHash
    AND  it.used_at    IS NULL
    AND  it.expires_at  > SYSUTCDATETIME();
END;
GO

-- ============================================================
-- sp_RedeemInviteToken
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_RedeemInviteToken
  @TokenHash    VARCHAR(128),
  @PasswordHash VARCHAR(255),
  @ErrorCode    NVARCHAR(50)  OUTPUT,
  @UserId       UNIQUEIDENTIFIER OUTPUT,
  @Email        NVARCHAR(255) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  SET @UserId    = NULL;
  SET @Email     = NULL;

  SELECT @UserId = it.user_id
  FROM   dbo.invite_tokens it
  WHERE  it.token_hash = @TokenHash
    AND  it.used_at    IS NULL
    AND  it.expires_at  > SYSUTCDATETIME();

  IF @UserId IS NULL
  BEGIN
    SET @ErrorCode = 'INVALID_OR_EXPIRED';
    RETURN;
  END

  SELECT @Email = email FROM dbo.users WHERE id = @UserId;

  BEGIN TRANSACTION;
  BEGIN TRY
    UPDATE dbo.users
    SET    password_hash = @PasswordHash,
           is_active     = 1
    WHERE  id = @UserId;

    UPDATE dbo.invite_tokens
    SET    used_at = SYSUTCDATETIME()
    WHERE  token_hash = @TokenHash;

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @ErrorCode = 'TRANSACTION_FAILED';
  END CATCH
END;
GO

-- ============================================================
-- sp_CheckTeamActive
-- Returns whether a team's subscription is currently active.
-- Used by requireActiveTeam middleware.
-- ============================================================
IF OBJECT_ID('dbo.sp_CheckTeamActive', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CheckTeamActive;
GO

CREATE PROCEDURE dbo.sp_CheckTeamActive
  @TeamId   UNIQUEIDENTIFIER,
  @IsActive BIT OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @IsActive = 0;

  SELECT @IsActive = CAST(is_active AS BIT)
  FROM   dbo.teams
  WHERE  id = @TeamId;
END;
GO

-- ============================================================
-- sp_CleanExpiredTokens
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CleanExpiredTokens
AS
BEGIN
  SET NOCOUNT ON;

  DELETE FROM dbo.refresh_tokens
  WHERE expires_at < DATEADD(DAY, -1, SYSUTCDATETIME())
     OR revoked_at < DATEADD(DAY, -30, SYSUTCDATETIME());
END;
GO
