-- ============================================================
-- CREATE LEGACYLINKGLOBAL — Run once on a fresh SQL Server
-- ============================================================
-- What this script does (in order):
--   1. Creates the LegacyLinkGlobal database
--   2. Creates all tables (auth, teams, config, permissions)
--   3. Seeds the platform_owner account
--   4. Seeds the LegacyLink internal team + team_config
--
-- After this script completes, run:
--   databases/global/stored-procedures/sp_Global_AllProcedures.sql
--
-- ADMIN: Before running, update the @PlatformEmail / @PlatformPasswordHash
-- variables below with a real bcrypt hash (cost 12).
-- Generate at: https://bcrypt-generator.com/ or:
--   node -e "require('bcryptjs').hash('YourPassword', 12).then(console.log)"
-- ============================================================

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'LegacyLinkGlobal')
BEGIN
  CREATE DATABASE LegacyLinkGlobal;
  PRINT 'Created database LegacyLinkGlobal';
END
ELSE
  PRINT 'LegacyLinkGlobal already exists — schema will be updated in place.';
GO

USE LegacyLinkGlobal;
GO

-- ============================================================
-- SECTION 1 — USERS
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'users' AND schema_id = SCHEMA_ID('dbo'))
CREATE TABLE dbo.users (
  id             UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
  email          NVARCHAR(255)     NOT NULL,
  password_hash  NVARCHAR(255)     NOT NULL,
  global_role    NVARCHAR(30)      NOT NULL DEFAULT 'readonly'
                 CONSTRAINT chk_users_global_role
                   CHECK (global_role IN ('readonly','coach_staff','global_admin','platform_owner')),
  is_active      BIT               NOT NULL DEFAULT 1,
  first_name     NVARCHAR(100)     NULL,
  last_name      NVARCHAR(100)     NULL,
  token_version  INT               NOT NULL DEFAULT 1,
  created_at     DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at     DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'uq_users_email')
  ALTER TABLE dbo.users ADD CONSTRAINT uq_users_email UNIQUE (email);
GO

-- ============================================================
-- SECTION 2 — APP PERMISSIONS
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'app_permissions' AND schema_id = SCHEMA_ID('dbo'))
CREATE TABLE dbo.app_permissions (
  id          UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
  user_id     UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.users(id) ON DELETE CASCADE,
  app         NVARCHAR(30)      NOT NULL,
  role        NVARCHAR(30)      NOT NULL,
  granted_by  UNIQUEIDENTIFIER  NULL      REFERENCES dbo.users(id),
  created_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT uq_app_permissions_user_app UNIQUE (user_id, app)
);
GO

-- ============================================================
-- SECTION 3 — REFRESH TOKENS
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'refresh_tokens' AND schema_id = SCHEMA_ID('dbo'))
CREATE TABLE dbo.refresh_tokens (
  id           UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
  user_id      UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.users(id) ON DELETE CASCADE,
  token_hash   NVARCHAR(64)      NOT NULL,
  expires_at   DATETIME2         NOT NULL,
  device_info  NVARCHAR(500)     NULL,
  created_at   DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT uq_refresh_tokens_hash UNIQUE (token_hash)
);
GO

-- ============================================================
-- SECTION 4 — AUDIT LOG (insert-only — never UPDATE/DELETE)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'audit_log' AND schema_id = SCHEMA_ID('dbo'))
CREATE TABLE dbo.audit_log (
  id           BIGINT            NOT NULL IDENTITY(1,1)  PRIMARY KEY,
  user_id      UNIQUEIDENTIFIER  NULL,
  action       NVARCHAR(100)     NOT NULL,
  target_type  NVARCHAR(50)      NULL,
  target_id    NVARCHAR(100)     NULL,
  details      NVARCHAR(MAX)     NULL,
  ip_address   NVARCHAR(45)      NULL,
  created_at   DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ============================================================
-- SECTION 5 — PASSWORD RESET TOKENS
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'password_reset_tokens' AND schema_id = SCHEMA_ID('dbo'))
CREATE TABLE dbo.password_reset_tokens (
  id          UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
  user_id     UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.users(id) ON DELETE CASCADE,
  token_hash  NVARCHAR(64)      NOT NULL,
  expires_at  DATETIME2         NOT NULL,
  used_at     DATETIME2         NULL,
  created_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ============================================================
-- SECTION 6 — INVITE TOKENS
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'invite_tokens' AND schema_id = SCHEMA_ID('dbo'))
CREATE TABLE dbo.invite_tokens (
  id          UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
  user_id     UNIQUEIDENTIFIER  NULL  REFERENCES dbo.users(id),
  email       NVARCHAR(255)     NULL,
  token_hash  NVARCHAR(64)      NOT NULL,
  expires_at  DATETIME2         NOT NULL,
  used_at     DATETIME2         NULL,
  created_by  UNIQUEIDENTIFIER  NULL  REFERENCES dbo.users(id),
  app_name    NVARCHAR(30)      NULL,
  app_role    NVARCHAR(30)      NULL,
  created_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT uq_invite_tokens_hash UNIQUE (token_hash)
);
GO

-- ============================================================
-- SECTION 7 — TEAMS
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'teams' AND schema_id = SCHEMA_ID('dbo'))
CREATE TABLE dbo.teams (
  id                 UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
  name               NVARCHAR(100)     NOT NULL,
  abbr               NVARCHAR(10)      NOT NULL,
  sport              NVARCHAR(50)      NOT NULL DEFAULT 'football',
  level              NVARCHAR(20)      NOT NULL DEFAULT 'college'
                     CONSTRAINT chk_teams_level CHECK (level IN ('college','high_school','club')),
  app_db             NVARCHAR(150)     NOT NULL DEFAULT '',
  db_server          NVARCHAR(200)     NOT NULL DEFAULT 'localhost\SQLEXPRESS',
  subscription_tier  NVARCHAR(20)      NOT NULL DEFAULT 'starter',
  is_active          BIT               NOT NULL DEFAULT 1,
  created_at         DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at         DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT uq_teams_abbr UNIQUE (abbr)
);
GO

-- ============================================================
-- SECTION 8 — USER TEAMS (multi-tenant junction)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'user_teams' AND schema_id = SCHEMA_ID('dbo'))
CREATE TABLE dbo.user_teams (
  id          UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
  user_id     UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.users(id)  ON DELETE CASCADE,
  team_id     UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.teams(id)  ON DELETE CASCADE,
  role        NVARCHAR(30)      NOT NULL DEFAULT 'readonly',
  created_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT uq_user_teams UNIQUE (user_id, team_id)
);
GO

-- ============================================================
-- SECTION 9 — TEAM CONFIG (branding + sport config)
-- Default colors = LegacyLink brand palette.
-- Clients can customise via /admin/settings after onboarding.
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'team_config' AND schema_id = SCHEMA_ID('dbo'))
CREATE TABLE dbo.team_config (
  id                   UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
  team_id              UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.teams(id)  ON DELETE CASCADE,
  team_name            NVARCHAR(100)     NULL,
  team_abbr            NVARCHAR(10)      NULL,
  sport                NVARCHAR(50)      NULL,
  level                NVARCHAR(20)      NULL,
  -- LegacyLink default palette —————————————————————————————
  primary_color        NCHAR(7)          NOT NULL DEFAULT '#1B1B2F',
  primary_dark         NCHAR(7)          NOT NULL DEFAULT '#0D0D1A',
  primary_light        NCHAR(7)          NOT NULL DEFAULT '#EAEAF2',
  accent_color         NCHAR(7)          NOT NULL DEFAULT '#B8973D',
  accent_dark          NCHAR(7)          NOT NULL DEFAULT '#9A7A2B',
  accent_light         NCHAR(7)          NOT NULL DEFAULT '#F5EDD5',
  -- ——————————————————————————————————————————————————————————
  logo_url             NVARCHAR(500)     NULL,
  roster_label         NVARCHAR(50)      NOT NULL DEFAULT 'Roster',
  alumni_label         NVARCHAR(50)      NOT NULL DEFAULT 'Alumni',
  class_label          NVARCHAR(50)      NOT NULL DEFAULT 'Recruiting Class',
  positions_json       NVARCHAR(MAX)     NULL,   -- JSON array, e.g. ["QB","RB",...]
  academic_years_json  NVARCHAR(MAX)     NULL,   -- JSON array, e.g. ["freshman","sophomore",...]
  updated_at           DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT uq_team_config_team UNIQUE (team_id)
);
GO

-- ============================================================
-- SECTION 10 — SEED: Platform Owner Account
-- ============================================================
-- ADMIN: Replace @PlatformPasswordHash with a bcrypt hash of your password.
--   node -e "require('bcryptjs').hash('YourPassword!', 12).then(console.log)"
-- ============================================================
DECLARE @PlatformEmail        NVARCHAR(255) = 'admin@legacylink.io';
DECLARE @PlatformPasswordHash NVARCHAR(255) = '$2a$12$REPLACE_WITH_REAL_BCRYPT_HASH_HERE___________________________';
DECLARE @PlatformFirstName    NVARCHAR(100) = 'Platform';
DECLARE @PlatformLastName     NVARCHAR(100) = 'Owner';

DECLARE @PlatformUserId UNIQUEIDENTIFIER;

IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE email = @PlatformEmail)
BEGIN
  SET @PlatformUserId = NEWID();
  INSERT INTO dbo.users (id, email, password_hash, global_role, first_name, last_name)
  VALUES (@PlatformUserId, @PlatformEmail, @PlatformPasswordHash, 'platform_owner',
          @PlatformFirstName, @PlatformLastName);
  PRINT 'Created platform_owner: ' + @PlatformEmail;
END
ELSE
BEGIN
  SELECT @PlatformUserId = id FROM dbo.users WHERE email = @PlatformEmail;
  PRINT 'platform_owner already exists: ' + @PlatformEmail;
END
GO

-- ============================================================
-- SECTION 11 — SEED: LegacyLink Internal Team
-- This is the "home" team. On login, users with access to this
-- team will default to it (LegacyLinkApp / DevLegacyLinkApp).
-- ============================================================
DECLARE @TeamId     UNIQUEIDENTIFIER;
DECLARE @AppDbName  NVARCHAR(150) = CASE
  WHEN @@SERVICENAME LIKE '%DEV%' OR @@SERVERNAME LIKE '%DEV%'
  THEN 'DevLegacyLinkApp'
  ELSE 'LegacyLinkApp'
END;

IF NOT EXISTS (SELECT 1 FROM dbo.teams WHERE abbr = 'LL')
BEGIN
  SET @TeamId = NEWID();
  INSERT INTO dbo.teams (id, name, abbr, sport, level, app_db, db_server, subscription_tier)
  VALUES (
    @TeamId,
    'LegacyLink',
    'LL',
    'football',
    'college',
    @AppDbName,
    @@SERVERNAME,
    'enterprise'
  );
  PRINT 'Created LegacyLink team — AppDB: ' + @AppDbName;
END
ELSE
BEGIN
  SELECT @TeamId = id FROM dbo.teams WHERE abbr = 'LL';
  PRINT 'LegacyLink team already exists.';
END
GO

-- Seed team_config with LegacyLink brand palette
DECLARE @TeamId UNIQUEIDENTIFIER = (SELECT id FROM dbo.teams WHERE abbr = 'LL');

IF @TeamId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.team_config WHERE team_id = @TeamId)
BEGIN
  INSERT INTO dbo.team_config (
    team_id, team_name, team_abbr, sport, level,
    primary_color, primary_dark, primary_light,
    accent_color,  accent_dark,  accent_light,
    roster_label, alumni_label, class_label,
    positions_json,
    academic_years_json
  )
  VALUES (
    @TeamId, 'LegacyLink', 'LL', 'football', 'college',
    '#1B1B2F', '#0D0D1A', '#EAEAF2',
    '#B8973D', '#9A7A2B', '#F5EDD5',
    'Roster', 'Alumni', 'Recruiting Class',
    '["QB","RB","WR","TE","OL","DL","LB","DB","K","P","LS","ATH"]',
    '["freshman","sophomore","junior","senior","graduate"]'
  );
  PRINT 'Seeded team_config for LegacyLink.';
END
GO

-- Link platform_owner to LegacyLink team
DECLARE @PlatformUserId UNIQUEIDENTIFIER = (SELECT id FROM dbo.users WHERE global_role = 'platform_owner');
DECLARE @TeamId         UNIQUEIDENTIFIER = (SELECT id FROM dbo.teams WHERE abbr = 'LL');

IF @PlatformUserId IS NOT NULL AND @TeamId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.user_teams WHERE user_id = @PlatformUserId AND team_id = @TeamId)
BEGIN
  INSERT INTO dbo.user_teams (user_id, team_id, role) VALUES (@PlatformUserId, @TeamId, 'global_admin');
  PRINT 'Linked platform_owner to LegacyLink team.';
END
GO

-- ============================================================
-- DONE
-- ============================================================
PRINT '';
PRINT '==========================================================';
PRINT 'LegacyLinkGlobal schema ready.';
PRINT '';
PRINT 'Next steps:';
PRINT '  1. Run: databases/global/stored-procedures/sp_Global_AllProcedures.sql';
PRINT '  2. Update the platform_owner password hash above with a real bcrypt hash.';
PRINT '  3. Run: databases/app/create_app_db.sql  (for each client AppDB)';
PRINT '==========================================================';
GO
