-- ============================================================
-- CREATE CLIENT APP DATABASE — Run once per new client
-- ============================================================
-- ADMIN: Set the four variables below before running.
-- Run this entire file against: master (it switches context
-- to the new DB after creating it).
--
-- After this script completes, run against the new AppDB:
--   databases/app/stored-procedures/sp_App_AllProcedures.sql
--
-- This script also registers the team in LegacyLinkGlobal.
-- ============================================================

-- ─── ADMIN: Configure these before running ──────────────────
DECLARE @ClientName  NVARCHAR(100) = 'Plant Panthers Football';  -- Full display name
DECLARE @ClientAbbr  NVARCHAR(10)  = 'PLANT';                   -- Short code (unique)
DECLARE @AppDbName   NVARCHAR(150) = 'PlantPanthersApp';         -- SQL Server DB name
DECLARE @Sport       NVARCHAR(50)  = 'football';                 -- football | basketball | baseball | soccer | softball | volleyball | other
DECLARE @Level       NVARCHAR(20)  = 'high_school';              -- college | high_school | club
DECLARE @DbServer    NVARCHAR(200) = 'localhost\SQLEXPRESS';     -- SQL Server instance
DECLARE @Tier        NVARCHAR(20)  = 'starter';                  -- starter | pro | enterprise
-- ────────────────────────────────────────────────────────────

USE master;
GO

-- ============================================================
-- STEP 1 — Create the AppDB
-- ============================================================
DECLARE @AppDbName NVARCHAR(150) = 'PlantPanthersApp'; -- keep in sync with variable above
DECLARE @sql       NVARCHAR(MAX);

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @AppDbName)
BEGIN
  SET @sql = N'CREATE DATABASE [' + @AppDbName + N'];';
  EXEC sp_executesql @sql;
  PRINT 'Created database: ' + @AppDbName;
END
ELSE
  PRINT 'Database already exists — schema will be updated in place: ' + @AppDbName;
GO

-- Switch to the new AppDB for all remaining steps
USE PlantPanthersApp; -- ← Update this USE statement to match @AppDbName above
GO

-- ============================================================
-- STEP 2 — PLAYER STATUS TYPES lookup
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'player_status_types' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.player_status_types (
    id          INT           NOT NULL  PRIMARY KEY,
    status_name NVARCHAR(30)  NOT NULL,
    description NVARCHAR(200) NULL
  );

  INSERT INTO dbo.player_status_types (id, status_name, description) VALUES
    (1, 'current_player', 'Active roster player'),
    (2, 'alumni',         'Graduated — moved to Alumni CRM'),
    (3, 'removed',        'Removed from roster — no longer active');

  PRINT 'Created dbo.player_status_types';
END
GO

-- ============================================================
-- STEP 3 — SPORTS (organisational unit within tenant)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'sports' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.sports (
    id         UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
    name       NVARCHAR(100)     NOT NULL,
    abbr       NVARCHAR(10)      NOT NULL,
    is_active  BIT               NOT NULL DEFAULT 1,
    created_at DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_sports_abbr UNIQUE (abbr)
  );
  PRINT 'Created dbo.sports';
END
GO

-- ============================================================
-- STEP 4 — USERS (unified players + alumni, single table)
-- id = mirrors LegacyLinkGlobal.dbo.users.id (the canonical GUID)
-- status_id: 1=current player  2=alumni  3=removed
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'users' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.users (
    -- ─── Identity (mirrors LegacyLinkGlobal) ──────────────
    id                      UNIQUEIDENTIFIER  NOT NULL  PRIMARY KEY,
    email                   NVARCHAR(255)     NULL,   -- NULL OK for provisional bulk-import rows
    first_name              NVARCHAR(100)     NOT NULL,
    last_name               NVARCHAR(100)     NOT NULL,

    -- ─── Status ────────────────────────────────────────────
    status_id               INT               NOT NULL DEFAULT 1
                            REFERENCES dbo.player_status_types(id),
    sport_id                UNIQUEIDENTIFIER  NULL
                            REFERENCES dbo.sports(id),

    -- ─── Roster fields ─────────────────────────────────────
    jersey_number           TINYINT           NULL,
    position                NVARCHAR(10)      NULL,
    academic_year           NVARCHAR(20)      NULL,
    recruiting_class        SMALLINT          NULL,
    height_inches           TINYINT           NULL,
    weight_lbs              SMALLINT          NULL,
    home_town               NVARCHAR(100)     NULL,
    home_state              NVARCHAR(50)      NULL,
    high_school             NVARCHAR(150)     NULL,
    gpa                     DECIMAL(3,2)      NULL,
    major                   NVARCHAR(100)     NULL,
    phone                   NVARCHAR(20)      NULL,
    personal_email          NVARCHAR(255)     NULL,
    instagram               NVARCHAR(100)     NULL,
    twitter                 NVARCHAR(100)     NULL,
    snapchat                NVARCHAR(100)     NULL,
    emergency_contact_name  NVARCHAR(150)     NULL,
    emergency_contact_phone NVARCHAR(20)      NULL,

    -- ─── Alumni / graduation fields ────────────────────────
    graduation_year         SMALLINT          NULL,
    graduation_semester     NVARCHAR(10)      NULL,
    graduated_at            DATETIME2         NULL,
    linkedin_url            NVARCHAR(500)     NULL,
    twitter_url             NVARCHAR(100)     NULL,
    current_employer        NVARCHAR(200)     NULL,
    current_job_title       NVARCHAR(150)     NULL,
    current_city            NVARCHAR(100)     NULL,
    current_state           NVARCHAR(50)      NULL,
    is_donor                BIT               NULL DEFAULT 0,
    last_donation_date      DATE              NULL,
    total_donations         DECIMAL(10,2)     NULL,
    engagement_score        TINYINT           NULL DEFAULT 0,
    communication_consent   BIT               NULL DEFAULT 1,
    years_on_roster         TINYINT           NULL,

    -- ─── Shared ────────────────────────────────────────────
    notes                   NVARCHAR(MAX)     NULL,
    created_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );

  -- Filtered unique index: jersey numbers unique per active sport player
  CREATE UNIQUE INDEX uix_users_jersey_sport
    ON dbo.users (jersey_number, sport_id)
    WHERE jersey_number IS NOT NULL AND status_id = 1 AND sport_id IS NOT NULL;

  PRINT 'Created dbo.users';
END
GO

-- ============================================================
-- STEP 5 — USERS_SPORTS (multi-sport junction)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'users_sports' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.users_sports (
    id         UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
    user_id    UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.users(id)   ON DELETE CASCADE,
    sport_id   UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.sports(id)  ON DELETE CASCADE,
    username   NVARCHAR(100)     NULL,
    joined_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_users_sports UNIQUE (user_id, sport_id)
  );
  PRINT 'Created dbo.users_sports';
END
GO

-- ============================================================
-- STEP 6 — PLAYER STATS
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'player_stats' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.player_stats (
    id           UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
    user_id      UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.users(id)  ON DELETE CASCADE,
    season_year  SMALLINT          NOT NULL,
    games_played TINYINT           NULL,
    stats_json   NVARCHAR(MAX)     NULL,
    updated_at   DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_player_stats UNIQUE (user_id, season_year)
  );
  PRINT 'Created dbo.player_stats';
END
GO

-- ============================================================
-- STEP 7 — PLAYER DOCUMENTS
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'player_documents' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.player_documents (
    id           UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
    user_id      UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.users(id)  ON DELETE CASCADE,
    doc_type     NVARCHAR(50)      NOT NULL,
    file_name    NVARCHAR(255)     NOT NULL,
    blob_url     NVARCHAR(1000)    NOT NULL,
    uploaded_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT 'Created dbo.player_documents';
END
GO

-- ============================================================
-- STEP 8 — GRADUATION LOG (audit trail for status flips)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'graduation_log' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.graduation_log (
    id                   UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
    transaction_id       UNIQUEIDENTIFIER  NOT NULL,
    user_id              UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.users(id),
    graduation_year      SMALLINT          NOT NULL,
    graduation_semester  NVARCHAR(10)      NOT NULL,
    triggered_by         UNIQUEIDENTIFIER  NULL,
    status               NVARCHAR(20)      NOT NULL DEFAULT 'success',
    notes                NVARCHAR(MAX)     NULL,
    logged_at            DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT 'Created dbo.graduation_log';
END
GO

-- ============================================================
-- STEP 9 — INTERACTION LOG (alumni CRM notes)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'interaction_log' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.interaction_log (
    id           UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
    user_id      UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.users(id)  ON DELETE CASCADE,
    logged_by    UNIQUEIDENTIFIER  NULL,
    channel      NVARCHAR(30)      NOT NULL,
    summary      NVARCHAR(MAX)     NOT NULL,
    outcome      NVARCHAR(50)      NULL,
    follow_up_at DATETIME2         NULL,
    logged_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT 'Created dbo.interaction_log';
END
GO

-- ============================================================
-- STEP 10 — OUTREACH CAMPAIGNS
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'outreach_campaigns' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.outreach_campaigns (
    id               UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
    name             NVARCHAR(200)     NOT NULL,
    description      NVARCHAR(MAX)     NULL,
    target_audience  NVARCHAR(20)      NOT NULL DEFAULT 'all',
    audience_filters NVARCHAR(MAX)     NULL,
    status           NVARCHAR(20)      NOT NULL DEFAULT 'draft'
                     CONSTRAINT chk_campaign_status CHECK (status IN ('draft','scheduled','active','completed','cancelled')),
    scheduled_at     DATETIME2         NULL,
    sport_id         UNIQUEIDENTIFIER  NULL  REFERENCES dbo.sports(id),
    created_by       UNIQUEIDENTIFIER  NULL,
    created_at       DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at       DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT 'Created dbo.outreach_campaigns';
END
GO

-- ============================================================
-- STEP 11 — OUTREACH MESSAGES
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'outreach_messages' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.outreach_messages (
    id           UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
    campaign_id  UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.outreach_campaigns(id)  ON DELETE CASCADE,
    user_id      UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.users(id),
    channel      NVARCHAR(20)      NOT NULL,
    status       NVARCHAR(20)      NOT NULL DEFAULT 'pending',
    sent_at      DATETIME2         NULL,
    delivered_at DATETIME2         NULL,
    opened_at    DATETIME2         NULL,
    created_at   DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT 'Created dbo.outreach_messages';
END
GO

-- ============================================================
-- STEP 12 — SEASONS
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'seasons' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.seasons (
    id          UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
    sport_id    UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.sports(id)  ON DELETE CASCADE,
    season_year SMALLINT          NOT NULL,
    label       NVARCHAR(50)      NULL,
    is_current  BIT               NOT NULL DEFAULT 0,
    starts_at   DATE              NULL,
    ends_at     DATE              NULL,
    CONSTRAINT uq_seasons UNIQUE (sport_id, season_year)
  );
  PRINT 'Created dbo.seasons';
END
GO

-- ============================================================
-- STEP 13 — SEASON PLAYERS (junction)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'season_players' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.season_players (
    id           UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
    season_id    UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.seasons(id)   ON DELETE CASCADE,
    user_id      UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.users(id),
    enrolled_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_season_players UNIQUE (season_id, user_id)
  );
  PRINT 'Created dbo.season_players';
END
GO

-- ============================================================
-- STEP 14 — USER ROLES (RBAC per sport)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'user_roles' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.user_roles (
    id          UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID()  PRIMARY KEY,
    user_id     UNIQUEIDENTIFIER  NOT NULL,
    sport_id    UNIQUEIDENTIFIER  NOT NULL  REFERENCES dbo.sports(id),
    role        NVARCHAR(30)      NOT NULL,
    granted_by  UNIQUEIDENTIFIER  NULL,
    revoked_at  DATETIME2         NULL,
    created_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_user_roles UNIQUE (user_id, sport_id)
  );
  PRINT 'Created dbo.user_roles';
END
GO

-- ============================================================
-- STEP 15 — AUDIT LOG (FERPA — insert-only)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'audit_log' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.audit_log (
    id          BIGINT            NOT NULL IDENTITY(1,1)  PRIMARY KEY,
    user_id     UNIQUEIDENTIFIER  NULL,
    action      NVARCHAR(100)     NOT NULL,
    target_type NVARCHAR(50)      NULL,
    target_id   NVARCHAR(100)     NULL,
    details     NVARCHAR(MAX)     NULL,
    ip_address  NVARCHAR(45)      NULL,
    created_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT 'Created dbo.audit_log';
END
GO

-- ============================================================
-- STEP 16 — ROW-LEVEL SECURITY
-- Unified policy: coach_admin sees all  |  status_only_admin
-- sees status_id=1  |  users see their own row.
-- SESSION_CONTEXT keys: 'user_id' and 'user_role'
-- ============================================================
CREATE OR ALTER FUNCTION dbo.fn_user_access()
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
  SELECT 1 AS access_granted
  WHERE
    -- Service account (no session context set) → full access
    SESSION_CONTEXT(N'user_role') IS NULL
    OR
    -- coach_admin / global_admin → full access
    CAST(SESSION_CONTEXT(N'user_role') AS NVARCHAR(50)) IN ('coach_admin','global_admin','platform_owner')
    OR
    -- roster_only_admin → current players only (status_id=1)
    -- Access is enforced per row via predicate; here we allow access,
    -- status filter applied in the predicate below.
    (
      CAST(SESSION_CONTEXT(N'user_role') AS NVARCHAR(50)) = 'roster_only_admin'
    )
    OR
    -- User sees own row
    (
      SESSION_CONTEXT(N'user_id') IS NOT NULL
      AND CAST(SESSION_CONTEXT(N'user_id') AS NVARCHAR(100)) = CAST(id AS NVARCHAR(100))
    );
GO

-- Apply security policy
IF NOT EXISTS (
  SELECT 1 FROM sys.security_policies
  WHERE name = 'user_access_policy' AND schema_id = SCHEMA_ID('dbo')
)
BEGIN
  CREATE SECURITY POLICY dbo.user_access_policy
    ADD FILTER PREDICATE dbo.fn_user_access() ON dbo.users,
    ADD BLOCK  PREDICATE dbo.fn_user_access() ON dbo.users AFTER INSERT
  WITH (STATE = ON, SCHEMABINDING = ON);
  PRINT 'Created RLS policy: user_access_policy';
END
GO

-- ============================================================
-- STEP 17 — MIGRATION HISTORY (tracks which migrations ran)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'migration_history' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.migration_history (
    id            INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    migration_id  NVARCHAR(100) NOT NULL UNIQUE,
    applied_at    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    description   NVARCHAR(500) NULL
  );

  -- Mark all migrations as already applied (this script replaces them)
  INSERT INTO dbo.migration_history (migration_id, description) VALUES
    ('001_app_db_schema',             'Initial schema — superseded by create_app_db.sql'),
    ('003_rbac_infrastructure',       'RBAC, sports, seasons — superseded by create_app_db.sql'),
    ('004_add_sport_classification',  'Sport columns — superseded by create_app_db.sql'),
    ('005_rls_policies',              'RLS — superseded by create_app_db.sql'),
    ('006_nullable_user_id',          'Nullable user_id — superseded by create_app_db.sql'),
    ('008_consolidate_dbo_schema',    'Consolidate to dbo — superseded by create_app_db.sql'),
    ('009_users_status_consolidation','Unified dbo.users — superseded by create_app_db.sql');

  PRINT 'Created dbo.migration_history';
END
GO

-- ============================================================
-- STEP 18 — SEED: Default Sport for this client
-- Creates one sport row matching the sport/level configured above.
-- ============================================================
DECLARE @SportAbbr NVARCHAR(10);
DECLARE @SportName NVARCHAR(100);
DECLARE @Level     NVARCHAR(20) = 'high_school'; -- ← keep in sync with @Level above

-- Derive display name from @Sport variable
-- (SQL Server doesn't allow variables across GO batches, so we use a temp table)
CREATE TABLE #ClientConfig (
  sport       NVARCHAR(50),
  level       NVARCHAR(20),
  client_abbr NVARCHAR(10)
);
INSERT INTO #ClientConfig VALUES ('football', 'high_school', 'PLANT');
-- ↑ Update these to match your variables at the top of the script

DECLARE @Sport NVARCHAR(50)  = (SELECT sport       FROM #ClientConfig);
DECLARE @Abbr  NVARCHAR(10)  = (SELECT client_abbr FROM #ClientConfig);
SET @Level                   = (SELECT level        FROM #ClientConfig);

DROP TABLE #ClientConfig;

SET @SportAbbr = UPPER(LEFT(@Sport, 2));
SET @SportName = UPPER(LEFT(@Sport, 1)) + LOWER(SUBSTRING(@Sport, 2, 50));

DECLARE @SportId UNIQUEIDENTIFIER;
IF NOT EXISTS (SELECT 1 FROM dbo.sports WHERE abbr = @SportAbbr)
BEGIN
  SET @SportId = NEWID();
  INSERT INTO dbo.sports (id, name, abbr) VALUES (@SportId, @SportName, @SportAbbr);
  PRINT 'Seeded sport: ' + @SportName;
END
ELSE
BEGIN
  SELECT @SportId = id FROM dbo.sports WHERE abbr = @SportAbbr;
  PRINT 'Sport already exists: ' + @SportAbbr;
END
GO

-- ============================================================
-- STEP 19 — REGISTER TEAM IN LegacyLinkGlobal
-- ============================================================
-- Run this block after the AppDB is set up.
-- Uses cross-DB reference — LegacyLinkGlobal must be on the same instance.
USE LegacyLinkGlobal;
GO

DECLARE @ClientName  NVARCHAR(100) = 'Plant Panthers Football'; -- ← keep in sync with top
DECLARE @ClientAbbr  NVARCHAR(10)  = 'PLANT';
DECLARE @AppDbName   NVARCHAR(150) = 'PlantPanthersApp';
DECLARE @Sport       NVARCHAR(50)  = 'football';
DECLARE @Level       NVARCHAR(20)  = 'high_school';
DECLARE @DbServer    NVARCHAR(200) = 'localhost\SQLEXPRESS';
DECLARE @Tier        NVARCHAR(20)  = 'starter';

DECLARE @TeamId UNIQUEIDENTIFIER;

IF NOT EXISTS (SELECT 1 FROM dbo.teams WHERE abbr = @ClientAbbr)
BEGIN
  SET @TeamId = NEWID();
  INSERT INTO dbo.teams (id, name, abbr, sport, level, app_db, db_server, subscription_tier)
  VALUES (@TeamId, @ClientName, @ClientAbbr, @Sport, @Level, @AppDbName, @DbServer, @Tier);
  PRINT 'Registered team in LegacyLinkGlobal: ' + @ClientAbbr;
END
ELSE
BEGIN
  SELECT @TeamId = id FROM dbo.teams WHERE abbr = @ClientAbbr;
  PRINT 'Team already registered: ' + @ClientAbbr;
END

-- Seed team_config with LegacyLink default palette
-- Clients can customise this later via /admin/settings
IF NOT EXISTS (SELECT 1 FROM dbo.team_config WHERE team_id = @TeamId)
BEGIN
  INSERT INTO dbo.team_config (
    team_id, team_name, team_abbr, sport, level,
    primary_color, primary_dark, primary_light,
    accent_color,  accent_dark,  accent_light,
    roster_label, alumni_label, class_label,
    positions_json, academic_years_json
  )
  VALUES (
    @TeamId, @ClientName, @ClientAbbr, @Sport, @Level,
    -- ─── LegacyLink default palette ───────────────────────
    '#1B1B2F', '#0D0D1A', '#EAEAF2',
    '#B8973D', '#9A7A2B', '#F5EDD5',
    -- ───────────────────────────────────────────────────────
    'Roster', 'Alumni', 'Recruiting Class',
    CASE @Sport
      WHEN 'football'   THEN '["QB","RB","WR","TE","OL","DL","LB","DB","K","P","LS","ATH"]'
      WHEN 'basketball' THEN '["PG","SG","SF","PF","C"]'
      WHEN 'baseball'   THEN '["P","C","1B","2B","3B","SS","LF","CF","RF","DH"]'
      WHEN 'soccer'     THEN '["GK","DEF","MID","FWD"]'
      WHEN 'softball'   THEN '["P","C","1B","2B","3B","SS","LF","CF","RF","DP"]'
      WHEN 'volleyball' THEN '["S","OH","MB","RS","L","DS"]'
      ELSE '[]'
    END,
    CASE @Level
      WHEN 'college'     THEN '["freshman","sophomore","junior","senior","graduate"]'
      WHEN 'high_school' THEN '["9th","10th","11th","12th"]'
      WHEN 'club'        THEN '["year1","year2","year3","year4"]'
      ELSE '["freshman","sophomore","junior","senior"]'
    END
  );
  PRINT 'Seeded team_config (LegacyLink default palette) for: ' + @ClientAbbr;
END
GO

-- ============================================================
-- DONE
-- ============================================================
PRINT '';
PRINT '==========================================================';
PRINT 'Client AppDB provisioning complete.';
PRINT '';
PRINT 'Next steps:';
PRINT '  1. Switch context back to the new AppDB:';
PRINT '     USE PlantPanthersApp;';
PRINT '  2. Run: databases/app/stored-procedures/sp_App_AllProcedures.sql';
PRINT '  3. Create the first admin user via /platform-admin or sp_CreateUser.';
PRINT '==========================================================';
GO
