-- ============================================================
-- CREATE DevLegacyLinkGlobal — Dev Global Database
-- Run against: master (on localhost\SQLEXPRESS)
--
-- FULL RESET (wipe + recreate):
--   1. In SSMS: right-click DevLegacyLinkGlobal → Delete
--              (check "Close existing connections") → OK
--   2. Re-run this script from master context
--
-- NORMAL / IDEMPOTENT RUN:
--   Just run the script — tables are guarded with IF NOT EXISTS,
--   columns with IF NOT EXISTS checks, SPs with CREATE OR ALTER.
--   Safe to re-run to apply new SPs or column additions.
--
-- After first run: global-api .env must point at DevLegacyLinkGlobal.
-- ============================================================

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'DevLegacyLinkGlobal')
BEGIN
  CREATE DATABASE [DevLegacyLinkGlobal];
  PRINT 'Created database: DevLegacyLinkGlobal';
END
ELSE
  PRINT 'Database DevLegacyLinkGlobal already exists — running idempotent update';
GO

USE DevLegacyLinkGlobal;
GO

-- ─── users ───────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'users' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.users (
    id            UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    email         NVARCHAR(255)     NOT NULL UNIQUE,
    password_hash NVARCHAR(255)     NOT NULL,
    first_name    NVARCHAR(100)     NOT NULL,
    last_name     NVARCHAR(100)     NOT NULL,
    global_role   NVARCHAR(50)      NOT NULL DEFAULT 'readonly'
                    CONSTRAINT CK_users_global_role
                    CHECK (global_role IN ('platform_owner','global_admin','app_admin','coach_staff','player','readonly')),
    is_active     BIT               NOT NULL DEFAULT 1,
    last_login_at DATETIME2         NULL,
    token_version INT               NOT NULL DEFAULT 1,
    created_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_users_email       ON dbo.users(email);
  CREATE INDEX IX_users_global_role ON dbo.users(global_role);
  PRINT 'Created dbo.users';
END
ELSE
  PRINT 'dbo.users already exists — skipping';
GO

-- Ensure all users columns exist
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='token_version')
  ALTER TABLE dbo.users ADD token_version INT NOT NULL DEFAULT 1;
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='team_id')
  ALTER TABLE dbo.users ADD team_id UNIQUEIDENTIFIER NULL;
GO

-- ─── app_permissions ─────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'app_permissions' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.app_permissions (
    id         UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    user_id    UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
    app_name   NVARCHAR(50)      NOT NULL,
    role       NVARCHAR(50)      NOT NULL,
    granted_by UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.users(id),
    granted_at DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    revoked_at DATETIME2         NULL,
    CONSTRAINT UQ_user_app UNIQUE (user_id, app_name)
  );
  CREATE INDEX IX_app_permissions_user ON dbo.app_permissions(user_id);
  PRINT 'Created dbo.app_permissions';
END
ELSE
  PRINT 'dbo.app_permissions already exists — skipping';
GO

-- ─── refresh_tokens ──────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'refresh_tokens' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.refresh_tokens (
    id          UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    user_id     UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
    token_hash  NVARCHAR(255)     NOT NULL UNIQUE,
    expires_at  DATETIME2         NOT NULL,
    revoked_at  DATETIME2         NULL,
    device_info NVARCHAR(255)     NULL,
    created_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_refresh_tokens_user ON dbo.refresh_tokens(user_id);
  PRINT 'Created dbo.refresh_tokens';
END
ELSE
  PRINT 'dbo.refresh_tokens already exists — skipping';
GO

-- Ensure all refresh_tokens columns exist
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='refresh_tokens' AND COLUMN_NAME='revoked_at')
  ALTER TABLE dbo.refresh_tokens ADD revoked_at DATETIME2 NULL;
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='refresh_tokens' AND COLUMN_NAME='device_info')
  ALTER TABLE dbo.refresh_tokens ADD device_info NVARCHAR(255) NULL;
GO

-- ─── password_reset_tokens ───────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'password_reset_tokens' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.password_reset_tokens (
    id         UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    user_id    UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
    token_hash NVARCHAR(255)     NOT NULL UNIQUE,
    expires_at DATETIME2         NOT NULL,
    used_at    DATETIME2         NULL,
    created_at DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT 'Created dbo.password_reset_tokens';
END
ELSE
  PRINT 'dbo.password_reset_tokens already exists — skipping';
GO

-- ─── invite_tokens ───────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'invite_tokens' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.invite_tokens (
    id         INT               NOT NULL IDENTITY(1,1) PRIMARY KEY,
    user_id    UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.users(id),
    token_hash VARCHAR(128)      NOT NULL UNIQUE,
    expires_at DATETIME2         NOT NULL,
    used_at    DATETIME2         NULL,
    created_at DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_invite_tokens_token_hash ON dbo.invite_tokens(token_hash);
  CREATE INDEX IX_invite_tokens_user_id    ON dbo.invite_tokens(user_id);
  PRINT 'Created dbo.invite_tokens';
END
ELSE
  PRINT 'dbo.invite_tokens already exists — skipping';
GO

-- ─── audit_log ───────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'audit_log' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.audit_log (
    id           UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    actor_id     UNIQUEIDENTIFIER  NULL REFERENCES dbo.users(id),
    actor_email  NVARCHAR(255)     NULL,
    action       NVARCHAR(100)     NOT NULL,
    target_type  NVARCHAR(50)      NULL,
    target_id    NVARCHAR(255)     NULL,
    payload      NVARCHAR(MAX)     NULL,
    ip_address   NVARCHAR(50)      NULL,
    performed_at DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_audit_actor        ON dbo.audit_log(actor_id);
  CREATE INDEX IX_audit_performed_at ON dbo.audit_log(performed_at DESC);
  PRINT 'Created dbo.audit_log';
END
ELSE
  PRINT 'dbo.audit_log already exists — skipping';
GO

-- Ensure all audit_log columns exist (handles DBs created before these were added)
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='audit_log' AND COLUMN_NAME='actor_email')
  ALTER TABLE dbo.audit_log ADD actor_email NVARCHAR(255) NULL;
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='audit_log' AND COLUMN_NAME='ip_address')
  ALTER TABLE dbo.audit_log ADD ip_address NVARCHAR(50) NULL;
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='audit_log' AND COLUMN_NAME='target_type')
  ALTER TABLE dbo.audit_log ADD target_type NVARCHAR(50) NULL;
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='audit_log' AND COLUMN_NAME='target_id')
  ALTER TABLE dbo.audit_log ADD target_id NVARCHAR(255) NULL;
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='audit_log' AND COLUMN_NAME='payload')
  ALTER TABLE dbo.audit_log ADD payload NVARCHAR(MAX) NULL;
GO

-- ─── teams ───────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'teams' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.teams (
    id                UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID() PRIMARY KEY,
    name              NVARCHAR(100)     NOT NULL,
    abbr              NVARCHAR(10)      NOT NULL UNIQUE,
    sport             NVARCHAR(50)      NOT NULL DEFAULT 'football',
    level             NVARCHAR(20)      NOT NULL DEFAULT 'college'
                        CHECK (level IN ('college','high_school','club')),
    app_db            NVARCHAR(150)     NOT NULL,
    db_server         NVARCHAR(200)     NOT NULL DEFAULT 'localhost\SQLEXPRESS',
    subscription_tier NVARCHAR(20)      NOT NULL DEFAULT 'starter'
                        CHECK (subscription_tier IN ('starter','pro','enterprise')),
    is_active         BIT               NOT NULL DEFAULT 1,
    created_at        DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    expires_at        DATETIME2         NULL
  );
  CREATE INDEX IX_teams_abbr      ON dbo.teams(abbr);
  CREATE INDEX IX_teams_is_active ON dbo.teams(is_active);
  PRINT 'Created dbo.teams';
END
ELSE
  PRINT 'dbo.teams already exists — skipping';
GO

-- ─── team_config ─────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'team_config' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.team_config (
    id                  UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID() PRIMARY KEY,
    team_id             UNIQUEIDENTIFIER  NULL REFERENCES dbo.teams(id),
    team_name           NVARCHAR(100)     NOT NULL DEFAULT 'Team Portal',
    team_abbr           NVARCHAR(10)      NOT NULL DEFAULT 'TEAM',
    sport               NVARCHAR(50)      NOT NULL DEFAULT 'football',
    level               NVARCHAR(20)      NOT NULL DEFAULT 'college'
                          CHECK (level IN ('college','high_school','club')),
    logo_url            NVARCHAR(500)     NULL,
    color_primary       NVARCHAR(7)       NOT NULL DEFAULT '#1B1B2F',
    color_primary_dark  NVARCHAR(7)       NOT NULL DEFAULT '#0D0D1A',
    color_primary_light NVARCHAR(7)       NOT NULL DEFAULT '#EAEAF2',
    color_accent        NVARCHAR(7)       NOT NULL DEFAULT '#B8973D',
    color_accent_dark   NVARCHAR(7)       NOT NULL DEFAULT '#9A7A2B',
    color_accent_light  NVARCHAR(7)       NOT NULL DEFAULT '#F5EDD5',
    positions_json      NVARCHAR(MAX)     NULL,
    academic_years_json NVARCHAR(MAX)     NULL,
    alumni_label        NVARCHAR(50)      NOT NULL DEFAULT 'Alumni',
    roster_label        NVARCHAR(50)      NOT NULL DEFAULT 'Roster',
    class_label         NVARCHAR(50)      NOT NULL DEFAULT 'Recruiting Class',
    created_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE UNIQUE INDEX UQ_team_config_team_id ON dbo.team_config(team_id) WHERE team_id IS NOT NULL;
  PRINT 'Created dbo.team_config';
END
ELSE
  PRINT 'dbo.team_config already exists — skipping';
GO

-- ─── user_teams ──────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'user_teams' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.user_teams (
    id         UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID() PRIMARY KEY,
    user_id    UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.users(id),
    team_id    UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.teams(id),
    role       NVARCHAR(50)      NOT NULL DEFAULT 'readonly',
    is_active  BIT               NOT NULL DEFAULT 1,
    created_at DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_user_team UNIQUE (user_id, team_id)
  );
  CREATE INDEX IX_user_teams_user_id ON dbo.user_teams(user_id);
  CREATE INDEX IX_user_teams_team_id ON dbo.user_teams(team_id);
  PRINT 'Created dbo.user_teams';
END
ELSE
  PRINT 'dbo.user_teams already exists — skipping';
GO

-- ─── team_id on users (for current-team tracking) ────────────
IF NOT EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users' AND COLUMN_NAME = 'team_id'
)
BEGIN
  ALTER TABLE dbo.users
    ADD team_id UNIQUEIDENTIFIER NULL
        CONSTRAINT FK_users_teams FOREIGN KEY REFERENCES dbo.teams(id);
  CREATE INDEX IX_users_team_id ON dbo.users(team_id);
  PRINT 'Added team_id to dbo.users';
END
GO

-- ============================================================
-- SEED: Dev platform owner — copies credentials from prod
-- so you can log in to dev with the same account.
-- ============================================================

-- Copy password hash from LegacyLinkGlobal (same SQL Server instance)
DECLARE @PwHash    NVARCHAR(255) = (
  SELECT TOP 1 password_hash FROM LegacyLinkGlobal.dbo.users
  WHERE email = 'mswalsh68@gmail.com'
);
DECLARE @FirstName NVARCHAR(100) = (
  SELECT TOP 1 first_name FROM LegacyLinkGlobal.dbo.users
  WHERE email = 'mswalsh68@gmail.com'
);
DECLARE @LastName  NVARCHAR(100) = (
  SELECT TOP 1 last_name FROM LegacyLinkGlobal.dbo.users
  WHERE email = 'mswalsh68@gmail.com'
);

IF @PwHash IS NULL
BEGIN
  PRINT 'WARNING: mswalsh68@gmail.com not found in LegacyLinkGlobal — using placeholder hash.';
  PRINT 'Run: UPDATE DevLegacyLinkGlobal.dbo.users SET password_hash = <hash> WHERE email = ''mswalsh68@gmail.com''';
  SET @PwHash    = '$2b$12$PLACEHOLDER_UPDATE_THIS';
  SET @FirstName = 'Mike';
  SET @LastName  = 'Walsh';
END

DECLARE @DevUserId UNIQUEIDENTIFIER;

IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE email = 'mswalsh68@gmail.com')
BEGIN
  SET @DevUserId = NEWID();
  INSERT INTO dbo.users (id, email, password_hash, first_name, last_name, global_role)
  VALUES (@DevUserId, 'mswalsh68@gmail.com', @PwHash, @FirstName, @LastName, 'platform_owner');
  PRINT 'Seeded dev platform_owner: mswalsh68@gmail.com';
END
ELSE
BEGIN
  SELECT @DevUserId = id FROM dbo.users WHERE email = 'mswalsh68@gmail.com';
  -- Ensure platform_owner role
  UPDATE dbo.users SET global_role = 'platform_owner', updated_at = SYSUTCDATETIME()
  WHERE id = @DevUserId;
  PRINT 'Dev user already exists — ensured platform_owner role';
END
GO

-- ─── Register LL-DEV team ─────────────────────────────────────
DECLARE @TeamId UNIQUEIDENTIFIER;

IF NOT EXISTS (SELECT 1 FROM dbo.teams WHERE abbr = 'LL-DEV')
BEGIN
  SET @TeamId = NEWID();
  INSERT INTO dbo.teams (id, name, abbr, sport, level, app_db, db_server, subscription_tier)
  VALUES (@TeamId, 'LegacyLink Dev', 'LL-DEV', 'football', 'college',
          'DevLegacyLinkApp', 'localhost\SQLEXPRESS', 'starter');
  PRINT 'Registered LL-DEV team → DevLegacyLinkApp';
END
ELSE
BEGIN
  SELECT @TeamId = id FROM dbo.teams WHERE abbr = 'LL-DEV';
  PRINT 'LL-DEV team already registered';
END

-- Link platform_owner to LL-DEV team
DECLARE @UserId UNIQUEIDENTIFIER = (SELECT id FROM dbo.users WHERE email = 'mswalsh68@gmail.com');

IF @UserId IS NOT NULL AND @TeamId IS NOT NULL
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dbo.user_teams WHERE user_id = @UserId AND team_id = @TeamId)
  BEGIN
    INSERT INTO dbo.user_teams (user_id, team_id, role)
    VALUES (@UserId, @TeamId, 'global_admin');
    PRINT 'Linked platform_owner → LL-DEV team';
  END

  -- Set current team
  UPDATE dbo.users SET team_id = @TeamId WHERE id = @UserId AND team_id IS NULL;
END

-- team_config
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
GO

-- ─── Register USF team (for team switcher / theme testing) ───
DECLARE @UsfTeamId UNIQUEIDENTIFIER;
DECLARE @UserId2   UNIQUEIDENTIFIER = (SELECT id FROM dbo.users WHERE email = 'mswalsh68@gmail.com');

IF NOT EXISTS (SELECT 1 FROM dbo.teams WHERE abbr = 'USF')
BEGIN
  SET @UsfTeamId = NEWID();
  INSERT INTO dbo.teams (id, name, abbr, sport, level, app_db, db_server, subscription_tier)
  VALUES (@UsfTeamId, 'USF Bulls', 'USF', 'football', 'college',
          'DevLegacyLinkApp', 'localhost\SQLEXPRESS', 'starter');
  PRINT 'Registered USF team → DevLegacyLinkApp';
END
ELSE
BEGIN
  SELECT @UsfTeamId = id FROM dbo.teams WHERE abbr = 'USF';
  PRINT 'USF team already registered';
END

-- Link platform_owner to USF team
IF @UserId2 IS NOT NULL AND @UsfTeamId IS NOT NULL
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dbo.user_teams WHERE user_id = @UserId2 AND team_id = @UsfTeamId)
  BEGIN
    INSERT INTO dbo.user_teams (user_id, team_id, role)
    VALUES (@UserId2, @UsfTeamId, 'global_admin');
    PRINT 'Linked platform_owner → USF team';
  END
END

-- team_config for USF
IF NOT EXISTS (SELECT 1 FROM dbo.team_config WHERE team_id = @UsfTeamId)
BEGIN
  INSERT INTO dbo.team_config (
    team_id, team_name, team_abbr, sport, level,
    color_primary,      color_primary_dark,  color_primary_light,
    color_accent,       color_accent_dark,   color_accent_light,
    roster_label, alumni_label, class_label,
    positions_json, academic_years_json
  )
  VALUES (
    @UsfTeamId, 'USF Bulls', 'USF', 'football', 'college',
    '#006747', '#004D35', '#E8F5F0',
    '#CFC493', '#B8A87A', '#FAF7EC',
    'Roster', 'Alumni', 'Recruiting Class',
    '["QB","RB","WR","TE","OL","DL","LB","DB","K","P","LS","ATH"]',
    '["freshman","sophomore","junior","senior","graduate"]'
  );
  PRINT 'Seeded team_config for USF';
END
GO

-- ─── Ensure ALL teams in dev point at DevLegacyLinkApp ───────
-- In dev there is only one AppDB regardless of how many teams
-- exist. This lets you test team switching / theme changes
-- without needing separate AppDBs per team.
UPDATE dbo.teams
SET    app_db = 'DevLegacyLinkApp'
WHERE  app_db <> 'DevLegacyLinkApp'
   OR  app_db IS NULL;

PRINT CONCAT('Pointed ', @@ROWCOUNT, ' team(s) at DevLegacyLinkApp');
GO

-- ============================================================
-- STORED PROCEDURES — applied after all tables exist
-- CREATE OR ALTER = idempotent; safe to re-run at any time.
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Login
  @Email       NVARCHAR(255),
  @IpAddress   NVARCHAR(50)   = NULL,
  @DeviceInfo  NVARCHAR(255)  = NULL,
  @UserId       UNIQUEIDENTIFIER OUTPUT,
  @PasswordHash NVARCHAR(255)    OUTPUT,
  @UserJson     NVARCHAR(MAX)    OUTPUT,
  @ErrorCode    NVARCHAR(50)     OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

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

  IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId AND is_active = 1)
  BEGIN
    SET @ErrorCode = 'ACCOUNT_INACTIVE';
    RETURN;
  END

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
        ISNULL(tc.color_primary, '#1B1B2F') AS colorPrimary,
        ISNULL(tc.color_accent,  '#B8973D') AS colorAccent
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
        ISNULL(tc.color_primary, '#1B1B2F') AS colorPrimary,
        ISNULL(tc.color_accent,  '#B8973D') AS colorAccent
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

  UPDATE dbo.users
  SET last_login_at = SYSUTCDATETIME()
  WHERE id = @UserId;

  INSERT INTO dbo.audit_log (actor_id, actor_email, action, target_type, target_id, ip_address, payload)
  SELECT @UserId, @Email, 'login', 'user', CAST(@UserId AS NVARCHAR(100)), @IpAddress,
    JSON_OBJECT('device': ISNULL(@DeviceInfo, ''));
END;
GO

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

CREATE OR ALTER PROCEDURE dbo.sp_RefreshToken
  @OldTokenHash  NVARCHAR(255),
  @NewTokenHash  NVARCHAR(255),
  @NewExpiresAt  DATETIME2,
  @CurrentTeamId UNIQUEIDENTIFIER = NULL,
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
        ISNULL(tc.color_primary, '#1B1B2F') AS colorPrimary,
        ISNULL(tc.color_accent,  '#B8973D') AS colorAccent
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
        ISNULL(tc.color_primary, '#1B1B2F') AS colorPrimary,
        ISNULL(tc.color_accent,  '#B8973D') AS colorAccent
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

CREATE OR ALTER PROCEDURE dbo.sp_SwitchTeam
  @UserId    UNIQUEIDENTIFIER,
  @NewTeamId UNIQUEIDENTIFIER,
  @TeamJson  NVARCHAR(MAX) OUTPUT,
  @ErrorCode NVARCHAR(50)  OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  SET @TeamJson  = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.teams WHERE id = @NewTeamId AND is_active = 1)
  BEGIN
    SET @ErrorCode = 'TEAM_NOT_FOUND';
    RETURN;
  END

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

  INSERT INTO dbo.audit_log (actor_id, action, target_type, target_id, payload)
  VALUES (
    @UserId, 'team_switch', 'team', CAST(@NewTeamId AS NVARCHAR(100)),
    JSON_OBJECT('isPlatformOwner': CASE WHEN @GlobalRole = 'platform_owner' THEN 'true' ELSE 'false' END)
  );
END;
GO

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
      ISNULL(tc.color_primary, '#1B1B2F') AS colorPrimary,
      ISNULL(tc.color_accent,  '#B8973D') AS colorAccent
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
      ISNULL(tc.color_primary, '#1B1B2F') AS colorPrimary,
      ISNULL(tc.color_accent,  '#B8973D') AS colorAccent
    FROM dbo.user_teams ut
    JOIN  dbo.teams t        ON t.id      = ut.team_id
    LEFT JOIN dbo.team_config tc ON tc.team_id = t.id
    WHERE ut.user_id  = @UserId
      AND ut.is_active = 1
    ORDER BY t.name;
  END
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CreateUser
  @Email         NVARCHAR(255),
  @PasswordHash  NVARCHAR(255),
  @FirstName     NVARCHAR(100),
  @LastName      NVARCHAR(100),
  @GlobalRole    NVARCHAR(50),
  @CreatedBy     UNIQUEIDENTIFIER,
  @TeamId        UNIQUEIDENTIFIER = NULL,
  @GrantAppName  NVARCHAR(50)  = NULL,
  @GrantAppRole  NVARCHAR(50)  = NULL,
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

CREATE OR ALTER PROCEDURE dbo.sp_GetTokenVersion
  @UserId       UNIQUEIDENTIFIER,
  @TokenVersion INT OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @TokenVersion = NULL;
  SELECT @TokenVersion = token_version
  FROM   dbo.users
  WHERE  id = @UserId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CleanExpiredTokens
AS
BEGIN
  SET NOCOUNT ON;

  DELETE FROM dbo.refresh_tokens
  WHERE expires_at < DATEADD(DAY, -1, SYSUTCDATETIME())
     OR revoked_at < DATEADD(DAY, -30, SYSUTCDATETIME());
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetOrCreateUser
  @Email     NVARCHAR(255),
  @FirstName NVARCHAR(100),
  @LastName  NVARCHAR(100),
  @TeamId    UNIQUEIDENTIFIER = NULL,
  @CreatedBy UNIQUEIDENTIFIER = NULL,
  @UserId    UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode NVARCHAR(50)     OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  SET @ErrorCode = NULL;
  SET @UserId    = NULL;

  IF @TeamId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.teams WHERE id = @TeamId AND is_active = 1)
  BEGIN
    SET @ErrorCode = 'TEAM_NOT_FOUND';
    RETURN;
  END

  IF EXISTS (SELECT 1 FROM dbo.users WHERE email = @Email)
  BEGIN
    SELECT @UserId = id FROM dbo.users WHERE email = @Email;
    IF @TeamId IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.user_teams WHERE user_id = @UserId AND team_id = @TeamId)
    BEGIN
      INSERT INTO dbo.user_teams (user_id, team_id, role)
      VALUES (@UserId, @TeamId, 'readonly');
    END
    RETURN;
  END

  BEGIN TRANSACTION;

    SET @UserId = NEWID();

    INSERT INTO dbo.users (id, email, password_hash, first_name, last_name, global_role, team_id)
    VALUES (
      @UserId,
      @Email,
      'INVITE_PENDING',
      @FirstName,
      @LastName,
      'player',
      @TeamId
    );

    IF @TeamId IS NOT NULL
    BEGIN
      INSERT INTO dbo.user_teams (user_id, team_id, role)
      VALUES (@UserId, @TeamId, 'readonly');
    END

    INSERT INTO dbo.audit_log (actor_id, action, target_type, target_id, payload)
    VALUES (
      @CreatedBy,
      'user_created',
      'user',
      CAST(@UserId AS NVARCHAR(100)),
      JSON_OBJECT(
        'email':      @Email,
        'globalRole': 'player',
        'source':     'bulk_import',
        'teamId':     ISNULL(CAST(@TeamId AS NVARCHAR(100)), '')
      )
    );

  COMMIT TRANSACTION;

  SET @ErrorCode = 'CREATED';
END;
GO

-- ============================================================
-- STORED PROCEDURES — from sp_TeamConfig.sql
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.sp_GetTeamConfig
  @TeamId UNIQUEIDENTIFIER = NULL
AS
BEGIN
  SET NOCOUNT ON;

  IF @TeamId IS NOT NULL
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.team_config WHERE team_id = @TeamId)
    BEGIN
      INSERT INTO dbo.team_config (team_id, team_name, team_abbr, sport, level)
      SELECT @TeamId, t.name, t.abbr, t.sport, t.level
      FROM dbo.teams t WHERE t.id = @TeamId;
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
    FROM dbo.team_config
    WHERE team_id = @TeamId;
  END
  ELSE
  BEGIN
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
    FROM dbo.team_config
    ORDER BY created_at;
  END
END;
GO

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
  @AlumniLabel       NVARCHAR(50)  = NULL,
  @RosterLabel       NVARCHAR(50)  = NULL,
  @ClassLabel        NVARCHAR(50)  = NULL,
  @ErrorCode         NVARCHAR(50)  OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF @Level IS NOT NULL AND @Level NOT IN ('college', 'high_school', 'club')
  BEGIN
    SET @ErrorCode = 'INVALID_LEVEL';
    RETURN;
  END

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
    alumni_label        = COALESCE(@AlumniLabel,       alumni_label),
    roster_label        = COALESCE(@RosterLabel,       roster_label),
    class_label         = COALESCE(@ClassLabel,        class_label),
    updated_at          = SYSUTCDATETIME()
  WHERE (@TeamId IS NULL AND id = (SELECT TOP 1 id FROM dbo.team_config ORDER BY created_at))
     OR (team_id = @TeamId);
END;
GO

-- ============================================================
-- STORED PROCEDURES — from sp_Teams.sql
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

PRINT '';
PRINT '==========================================================';
PRINT 'DevLegacyLinkGlobal provisioned.';
PRINT '';
PRINT 'Dev rule: ALL teams → DevLegacyLinkApp (single AppDB).';
PRINT 'Add as many teams as you like to test the team switcher;';
PRINT 'app data always comes from DevLegacyLinkApp.';
PRINT '';
PRINT 'Stored procedures created/updated:';
PRINT '  sp_Login, sp_StoreRefreshToken, sp_RefreshToken,';
PRINT '  sp_Logout, sp_SwitchTeam, sp_GetUserTeams,';
PRINT '  sp_CreateUser, sp_UpdateUser, sp_GrantPermission,';
PRINT '  sp_RevokePermission, sp_TransferPlayerToAlumni,';
PRINT '  sp_GetUsers, sp_GetUserPermissions,';
PRINT '  sp_CreateInviteToken, sp_ValidateInviteToken,';
PRINT '  sp_RedeemInviteToken, sp_CheckTeamActive,';
PRINT '  sp_GetTokenVersion, sp_CleanExpiredTokens, sp_GetOrCreateUser,';
PRINT '  sp_GetTeamConfig, sp_UpdateTeamConfig,';
PRINT '  sp_GetTeams, sp_GetTeamById,';
PRINT '  sp_CreateTeam, sp_UpdateTeam';
PRINT '';
PRINT 'Next steps:';
PRINT '  1. Restart global-api (already points at DevLegacyLinkGlobal)';
PRINT '  2. npm run deploy:dev  (in ll-db-deploy)';
PRINT '==========================================================';
GO
