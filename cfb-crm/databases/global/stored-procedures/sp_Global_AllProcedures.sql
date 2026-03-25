-- ============================================================
-- GLOBAL DB — ALL STORED PROCEDURES
-- Run this file on: CfbGlobal database
-- Requires: HASHBYTES support (Azure SQL — built in)
-- Run after: 001_initial_schema.sql
-- ============================================================

-- ============================================================
-- sp_Login
-- Validates credentials, returns user + app permissions as JSON.
-- The API calls this, receives the JSON, signs a JWT, done.
-- No credential logic ever touches application code.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_Login
  @Email       NVARCHAR(255),
  @IpAddress   NVARCHAR(50)   = NULL,
  @DeviceInfo  NVARCHAR(255)  = NULL,
  -- Outputs
  @UserId      UNIQUEIDENTIFIER OUTPUT,
  @PasswordHash NVARCHAR(255) OUTPUT,
  @UserJson    NVARCHAR(MAX)  OUTPUT,  -- full user + permissions payload
  @ErrorCode   NVARCHAR(50)   OUTPUT   -- NULL = success
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
      u.first_name       AS firstName,
      u.last_name        AS lastName,
      u.global_role      AS globalRole,
      u.is_active        AS isActive,
      u.created_at       AS createdAt,
      t.id               AS teamId,
      t.name             AS teamName,
      t.roster_db        AS rosterDb,
      t.alumni_db        AS alumniDb,
      t.db_server        AS dbServer,
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
-- Validates an existing refresh token, revokes it, issues a new one.
-- Entire rotation is atomic — no partial state possible.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_RefreshToken
  @OldTokenHash  NVARCHAR(255),
  @NewTokenHash  NVARCHAR(255),
  @NewExpiresAt  DATETIME2,
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

    -- Validate existing token
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

    -- Check user still active
    IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId AND is_active = 1)
    BEGIN
      ROLLBACK TRANSACTION;
      SET @ErrorCode = 'ACCOUNT_INACTIVE';
      RETURN;
    END

    -- Revoke old token
    UPDATE dbo.refresh_tokens
    SET revoked_at = SYSUTCDATETIME()
    WHERE token_hash = @OldTokenHash;

    -- Issue new token
    INSERT INTO dbo.refresh_tokens (user_id, token_hash, expires_at)
    VALUES (@UserId, @NewTokenHash, @NewExpiresAt);

  COMMIT TRANSACTION;

  -- Return fresh user payload for new access token
  SELECT @UserJson = (
    SELECT
      u.id,
      u.email,
      u.first_name       AS firstName,
      u.last_name        AS lastName,
      u.global_role      AS globalRole,
      u.is_active        AS isActive,
      t.id               AS teamId,
      t.name             AS teamName,
      t.roster_db        AS rosterDb,
      t.alumni_db        AS alumniDb,
      t.db_server        AS dbServer,
      (
        SELECT ap.app_name AS app, ap.role, ap.granted_at AS grantedAt, ap.granted_by AS grantedBy
        FROM dbo.app_permissions ap
        WHERE ap.user_id = u.id AND ap.revoked_at IS NULL
        FOR JSON PATH
      ) AS appPermissions
    FROM dbo.users u
    LEFT JOIN dbo.teams t ON t.id = u.team_id
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
-- sp_CreateUser
-- Creates a user account and optionally grants initial app permissions.
-- Password hashing: the API passes the bcrypt hash — hashing stays in
-- application code (bcrypt is not natively available in SQL Server).
-- All other logic — validation, audit, duplicate check — lives here.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateUser
  @Email         NVARCHAR(255),
  @PasswordHash  NVARCHAR(255),
  @FirstName     NVARCHAR(100),
  @LastName      NVARCHAR(100),
  @GlobalRole    NVARCHAR(50),
  @CreatedBy     UNIQUEIDENTIFIER,
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

  -- Validate role
  IF @GlobalRole NOT IN ('global_admin','app_admin','coach_staff','player','readonly')
  BEGIN
    SET @ErrorCode = 'INVALID_ROLE';
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

    INSERT INTO dbo.users (id, email, password_hash, first_name, last_name, global_role)
    VALUES (@NewUserId, @Email, @PasswordHash, @FirstName, @LastName, @GlobalRole);

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
        'email':      @Email,
        'globalRole': @GlobalRole,
        'grantedApp': ISNULL(@GrantAppName, ''),
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

  IF @GlobalRole IS NOT NULL AND @GlobalRole NOT IN ('global_admin','app_admin','coach_staff','player','readonly')
  BEGIN
    SET @ErrorCode = 'INVALID_ROLE';
    RETURN;
  END

  -- Capture before state for audit
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
-- Grants a user access to an app. Revokes any existing grant first
-- so there is never more than one active permission row per user+app.
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

    -- Revoke existing active permission for this app
    UPDATE dbo.app_permissions
    SET revoked_at = SYSUTCDATETIME()
    WHERE user_id  = @UserId
      AND app_name = @AppName
      AND revoked_at IS NULL;

    -- Grant new permission
    INSERT INTO dbo.app_permissions (user_id, app_name, role, granted_by)
    VALUES (@UserId, @AppName, @Role, @GrantedBy);

    -- Audit
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
-- Revokes a user's access to an app.
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
-- sp_TransferPlayerToAlumni  (called by sp_GraduatePlayer)
-- Swaps app_permissions: roster → alumni, writes audit.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_TransferPlayerToAlumni
  @UserId    UNIQUEIDENTIFIER,
  @GrantedBy NVARCHAR(100)
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @GrantedByGuid UNIQUEIDENTIFIER = TRY_CAST(@GrantedBy AS UNIQUEIDENTIFIER);

  -- Revoke roster access
  UPDATE dbo.app_permissions
  SET revoked_at = SYSUTCDATETIME()
  WHERE user_id  = @UserId
    AND app_name = 'roster'
    AND revoked_at IS NULL;

  -- Grant alumni access (readonly — alumni can view their own profile)
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
-- Paginated user list with optional filters. Used by Global Admin screen.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetUsers
  @Search     NVARCHAR(255) = NULL,
  @GlobalRole NVARCHAR(50)  = NULL,
  @Page       INT           = 1,
  @PageSize   INT           = 50,
  -- Outputs
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
-- Returns all permission rows for a user (current + historical).
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
-- Invalidates any existing unused invite for a user, then inserts
-- a new one. Caller passes the sha256 hash of the raw token.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateInviteToken
  @UserId    UNIQUEIDENTIFIER,
  @TokenHash VARCHAR(128),
  @ExpiresAt DATETIME2
AS
BEGIN
  SET NOCOUNT ON;

  -- Expire any previous unused invite tokens for this user
  UPDATE dbo.invite_tokens
  SET    used_at = SYSUTCDATETIME()
  WHERE  user_id = @UserId AND used_at IS NULL;

  INSERT INTO dbo.invite_tokens (user_id, token_hash, expires_at)
  VALUES (@UserId, @TokenHash, @ExpiresAt);
END;
GO

-- ============================================================
-- sp_ValidateInviteToken
-- Returns the user's first name and email if the token is valid
-- (unused, not expired). Returns empty set if invalid.
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
-- Validates the token, sets the user's password hash, activates
-- the account, and marks the token used — all in one transaction.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_RedeemInviteToken
  @TokenHash    VARCHAR(128),
  @PasswordHash VARCHAR(255),
  @ErrorCode    NVARCHAR(50) OUTPUT,
  @UserId       UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  SET @UserId    = NULL;

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
-- sp_CleanExpiredTokens
-- Housekeeping — run on a schedule (e.g. Azure SQL Agent, daily).
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
