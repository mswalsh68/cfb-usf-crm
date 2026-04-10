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
-- This script also registers the team in the GlobalDB (@GlobalDb variable).
-- ============================================================

-- ─── ADMIN: Configure these before running ──────────────────
DECLARE @ClientName  NVARCHAR(100) = 'Plant Panthers Football';  -- Full display name
DECLARE @ClientAbbr  NVARCHAR(10)  = 'PLANT';                   -- Short code (unique)
DECLARE @AppDbName   NVARCHAR(150) = 'PlantPanthersApp';         -- SQL Server DB name
DECLARE @Sport       NVARCHAR(50)  = 'football';                 -- football | basketball | baseball | soccer | softball | volleyball | other
DECLARE @Level       NVARCHAR(20)  = 'high_school';              -- college | high_school | club
DECLARE @DbServer    NVARCHAR(200) = 'localhost\SQLEXPRESS';     -- SQL Server instance
DECLARE @Tier        NVARCHAR(20)  = 'starter';                  -- starter | pro | enterprise
DECLARE @GlobalDb    NVARCHAR(150) = 'LegacyLinkGlobal';         -- LegacyLinkGlobal (prod) | DevLegacyLinkGlobal (dev)
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
    completed_at     DATETIME2         NULL,
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
-- fn_user_access receives the row's id column as @UserId.
-- The security policy passes dbo.users.id when evaluating each row.
-- SESSION_CONTEXT keys: 'user_id' and 'user_role'
-- ============================================================

-- Drop existing policy first so we can CREATE OR ALTER the function it references
IF EXISTS (
  SELECT 1 FROM sys.security_policies
  WHERE name = 'user_access_policy' AND schema_id = SCHEMA_ID('dbo')
)
BEGIN
  DROP SECURITY POLICY dbo.user_access_policy;
  PRINT 'Dropped existing RLS policy for refresh';
END
GO

-- fn_user_access: sport-aware row-level security.
-- Receives column values from each dbo.users row via the security policy.
CREATE OR ALTER FUNCTION dbo.fn_user_access(
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
    -- Coach admin sees everyone for this sport (players + alumni)
    EXISTS (
      SELECT 1 FROM dbo.user_roles ur
      WHERE ur.user_id    = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
        AND ur.sport_id   = @row_sport_id
        AND ur.role       = 'coach_admin'
        AND ur.revoked_at IS NULL
    )
    OR
    -- Roster-only admin sees current players only (status_id=1)
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
    -- Users always see their own row
    @row_user_id = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
    OR
    -- Transition bypass: rows not yet assigned a sport
    (
      @row_sport_id IS NULL
      AND TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER) IS NOT NULL
    );
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'user_access_policy')
BEGIN
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
END
GO

-- ============================================================
-- STEP 17 — MIGRATION HISTORY (tracks which migrations ran)
-- Keeps column name 'migration_name' to match ll-db-deploy tool.
-- New AppDBs are created from this script so all migrations are
-- immediately marked as applied — deploy tool will skip them.
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'migration_history' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.migration_history (
    id             INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    migration_name NVARCHAR(260) NOT NULL UNIQUE,
    applied_at     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    applied_by     NVARCHAR(100) NOT NULL DEFAULT SYSTEM_USER
  );

  -- Mark all migrations as already applied (this script supersedes them)
  INSERT INTO dbo.migration_history (migration_name) VALUES
    ('001_app_db_schema.sql'),
    ('002_migrate_data.sql'),
    ('003_rbac_infrastructure.sql'),
    ('004_add_sport_classification.sql'),
    ('005_rls_policies.sql'),
    ('006_nullable_user_id.sql'),
    ('008_consolidate_dbo_schema.sql'),
    ('009_users_status_consolidation.sql'),
    ('010_campaign_completed_at.sql'),
    ('011_drop_current_country.sql'),
    ('012_email_infrastructure.sql'),
    ('013_welcome_post_seed.sql');

  PRINT 'Created dbo.migration_history (all historical migrations pre-marked)';
END
GO

-- ============================================================
-- STEP 18 — SEED: All standard sports
-- AppDB is multi-sport — seed all 7 standard sports up-front.
-- Coaches/admins are then assigned sport-specific roles.
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM dbo.sports WHERE abbr = 'FB')
  INSERT INTO dbo.sports (id, name, abbr) VALUES (NEWID(), 'Football',   'FB');
IF NOT EXISTS (SELECT 1 FROM dbo.sports WHERE abbr = 'BB')
  INSERT INTO dbo.sports (id, name, abbr) VALUES (NEWID(), 'Basketball', 'BB');
IF NOT EXISTS (SELECT 1 FROM dbo.sports WHERE abbr = 'BA')
  INSERT INTO dbo.sports (id, name, abbr) VALUES (NEWID(), 'Baseball',   'BA');
IF NOT EXISTS (SELECT 1 FROM dbo.sports WHERE abbr = 'SO')
  INSERT INTO dbo.sports (id, name, abbr) VALUES (NEWID(), 'Soccer',     'SO');
IF NOT EXISTS (SELECT 1 FROM dbo.sports WHERE abbr = 'SB')
  INSERT INTO dbo.sports (id, name, abbr) VALUES (NEWID(), 'Softball',   'SB');
IF NOT EXISTS (SELECT 1 FROM dbo.sports WHERE abbr = 'VB')
  INSERT INTO dbo.sports (id, name, abbr) VALUES (NEWID(), 'Volleyball', 'VB');
IF NOT EXISTS (SELECT 1 FROM dbo.sports WHERE abbr = 'OT')
  INSERT INTO dbo.sports (id, name, abbr) VALUES (NEWID(), 'Other',      'OT');
PRINT 'Seeded standard sports (FB, BB, BA, SO, SB, VB, OT)';
GO

-- ============================================================
-- STEP 19 — REGISTER TEAM IN GlobalDB
-- ============================================================
-- Uses dynamic SQL to target whichever GlobalDB was set above
-- (@GlobalDb = 'LegacyLinkGlobal' for prod, 'DevLegacyLinkGlobal' for dev).
-- Both GlobalDBs must be on the same SQL Server instance.
DECLARE @ClientName  NVARCHAR(100) = 'Plant Panthers Football'; -- ← keep in sync with top
DECLARE @ClientAbbr  NVARCHAR(10)  = 'PLANT';
DECLARE @AppDbName   NVARCHAR(150) = 'PlantPanthersApp';
DECLARE @Sport       NVARCHAR(50)  = 'football';
DECLARE @Level       NVARCHAR(20)  = 'high_school';
DECLARE @DbServer    NVARCHAR(200) = 'localhost\SQLEXPRESS';
DECLARE @Tier        NVARCHAR(20)  = 'starter';
DECLARE @GlobalDb    NVARCHAR(150) = 'LegacyLinkGlobal'; -- ← keep in sync with top

DECLARE @TeamId UNIQUEIDENTIFIER;
DECLARE @sql    NVARCHAR(MAX);

-- Switch to the correct GlobalDB
SET @sql = N'USE [' + @GlobalDb + N']';
EXEC sp_executesql @sql;

SET @sql = N'
IF NOT EXISTS (SELECT 1 FROM [' + @GlobalDb + N'].dbo.teams WHERE abbr = @Abbr)
BEGIN
  INSERT INTO [' + @GlobalDb + N'].dbo.teams (id, name, abbr, sport, level, app_db, db_server, subscription_tier)
  VALUES (@TeamId, @Name, @Abbr, @Sport, @Level, @AppDb, @Server, @Tier);
END
SELECT id FROM [' + @GlobalDb + N'].dbo.teams WHERE abbr = @Abbr;
';

SET @TeamId = NEWID();
EXEC sp_executesql @sql,
  N'@TeamId UNIQUEIDENTIFIER, @Name NVARCHAR(100), @Abbr NVARCHAR(10), @Sport NVARCHAR(50),
    @Level NVARCHAR(20), @AppDb NVARCHAR(150), @Server NVARCHAR(200), @Tier NVARCHAR(20)',
  @TeamId, @ClientName, @ClientAbbr, @Sport, @Level, @AppDbName, @DbServer, @Tier;

-- Re-fetch actual ID (in case team already existed)
SET @sql = N'SELECT @TeamId = id FROM [' + @GlobalDb + N'].dbo.teams WHERE abbr = @Abbr';
EXEC sp_executesql @sql,
  N'@TeamId UNIQUEIDENTIFIER OUTPUT, @Abbr NVARCHAR(10)',
  @TeamId OUTPUT, @ClientAbbr;

PRINT 'Team registered/confirmed in ' + @GlobalDb + ': ' + @ClientAbbr;

-- Seed team_config with LegacyLink default palette
-- Clients can customise this later via /admin/settings
SET @sql = N'
IF NOT EXISTS (SELECT 1 FROM [' + @GlobalDb + N'].dbo.team_config WHERE team_id = @TeamId)
  INSERT INTO [' + @GlobalDb + N'].dbo.team_config (
    team_id, team_name, team_abbr, sport, level,
    color_primary,     color_primary_dark, color_primary_light,
    color_accent,      color_accent_dark,  color_accent_light,
    roster_label, alumni_label, class_label,
    positions_json, academic_years_json
  ) VALUES (
    @TeamId, @Name, @Abbr, @Sport, @Level,
    N''#1B1B2F'', N''#0D0D1A'', N''#EAEAF2'',
    N''#B8973D'', N''#9A7A2B'', N''#F5EDD5'',
    N''Roster'', N''Alumni'', N''Recruiting Class'',
    @Positions, @AcademicYears
  );
';

DECLARE @Positions    NVARCHAR(MAX) = CASE @Sport
  WHEN 'football'   THEN '["QB","RB","WR","TE","OL","DL","LB","DB","K","P","LS","ATH"]'
  WHEN 'basketball' THEN '["PG","SG","SF","PF","C"]'
  WHEN 'baseball'   THEN '["P","C","1B","2B","3B","SS","LF","CF","RF","DH"]'
  WHEN 'soccer'     THEN '["GK","DEF","MID","FWD"]'
  WHEN 'softball'   THEN '["P","C","1B","2B","3B","SS","LF","CF","RF","DP"]'
  WHEN 'volleyball' THEN '["S","OH","MB","RS","L","DS"]'
  ELSE '[]'
END;
DECLARE @AcademicYears NVARCHAR(MAX) = CASE @Level
  WHEN 'college'     THEN '["freshman","sophomore","junior","senior","graduate"]'
  WHEN 'high_school' THEN '["9th","10th","11th","12th"]'
  WHEN 'club'        THEN '["year1","year2","year3","year4"]'
  ELSE '["freshman","sophomore","junior","senior"]'
END;

EXEC sp_executesql @sql,
  N'@TeamId UNIQUEIDENTIFIER, @Name NVARCHAR(100), @Abbr NVARCHAR(10),
    @Sport NVARCHAR(50), @Level NVARCHAR(20),
    @Positions NVARCHAR(MAX), @AcademicYears NVARCHAR(MAX)',
  @TeamId, @ClientName, @ClientAbbr, @Sport, @Level, @Positions, @AcademicYears;

PRINT 'team_config seeded/confirmed for: ' + @ClientAbbr;
GO

-- ============================================================
-- STEP 20 — EMAIL INFRASTRUCTURE
-- outreach_campaigns email columns, email_unsubscribes,
-- feed_posts, and feed_post_reads.
-- (Mirrors migration 012_email_infrastructure.sql)
-- ============================================================

-- Email columns on outreach_campaigns
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='outreach_campaigns' AND COLUMN_NAME='subject_line')
  ALTER TABLE dbo.outreach_campaigns ADD subject_line NVARCHAR(500) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='outreach_campaigns' AND COLUMN_NAME='body_html')
  ALTER TABLE dbo.outreach_campaigns ADD body_html NVARCHAR(MAX) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='outreach_campaigns' AND COLUMN_NAME='from_name')
  ALTER TABLE dbo.outreach_campaigns ADD from_name NVARCHAR(200) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='outreach_campaigns' AND COLUMN_NAME='reply_to_email')
  ALTER TABLE dbo.outreach_campaigns ADD reply_to_email NVARCHAR(255) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='outreach_campaigns' AND COLUMN_NAME='campaign_type')
  ALTER TABLE dbo.outreach_campaigns ADD campaign_type NVARCHAR(20) NOT NULL DEFAULT 'outreach';
GO
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='outreach_campaigns' AND COLUMN_NAME='physical_address')
  ALTER TABLE dbo.outreach_campaigns ADD physical_address NVARCHAR(500) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='outreach_campaigns' AND COLUMN_NAME='started_at')
  ALTER TABLE dbo.outreach_campaigns ADD started_at DATETIME2 NULL;
GO

-- Email dispatch columns on outreach_messages
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='outreach_messages' AND COLUMN_NAME='email_address')
  ALTER TABLE dbo.outreach_messages ADD email_address NVARCHAR(255) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='outreach_messages' AND COLUMN_NAME='unsubscribe_token')
  ALTER TABLE dbo.outreach_messages ADD unsubscribe_token UNIQUEIDENTIFIER NULL;
GO

-- CAN-SPAM opt-out store
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name='email_unsubscribes' AND schema_id=SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.email_unsubscribes (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    user_id         UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
    token           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    channel         NVARCHAR(20)     NOT NULL DEFAULT 'email',
    unsubscribed_at DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_unsub_user_channel UNIQUE (user_id, channel)
  );
  CREATE UNIQUE INDEX uix_email_unsubscribes_token ON dbo.email_unsubscribes(token);
  PRINT 'Created dbo.email_unsubscribes';
END
GO

-- Newsfeed posts
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name='feed_posts' AND schema_id=SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.feed_posts (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    created_by      UNIQUEIDENTIFIER NOT NULL,
    title           NVARCHAR(300)    NULL,
    body_html       NVARCHAR(MAX)    NOT NULL,
    audience        NVARCHAR(30)     NOT NULL DEFAULT 'all',
    audience_json   NVARCHAR(MAX)    NULL,
    sport_id        UNIQUEIDENTIFIER NULL REFERENCES dbo.sports(id),
    is_pinned       BIT              NOT NULL DEFAULT 0,
    is_welcome_post BIT              NOT NULL DEFAULT 0,
    campaign_id     UNIQUEIDENTIFIER NULL REFERENCES dbo.outreach_campaigns(id),
    published_at    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    created_at      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX idx_feed_posts_audience ON dbo.feed_posts(audience);
  CREATE INDEX idx_feed_posts_sport    ON dbo.feed_posts(sport_id);
  CREATE INDEX idx_feed_posts_pinned   ON dbo.feed_posts(is_pinned, published_at DESC);
  PRINT 'Created dbo.feed_posts';
END
GO

-- Read receipts
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name='feed_post_reads' AND schema_id=SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.feed_post_reads (
    id      UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    post_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.feed_posts(id) ON DELETE CASCADE,
    user_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id),
    read_at DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_post_read UNIQUE (post_id, user_id)
  );
  CREATE INDEX idx_feed_reads_post ON dbo.feed_post_reads(post_id);
  CREATE INDEX idx_feed_reads_user ON dbo.feed_post_reads(user_id);
  PRINT 'Created dbo.feed_post_reads';
END
GO

-- ============================================================
-- STEP 21 — SEED WELCOME POST
--
-- Inserts a pinned welcome post visible to all roles.
-- Body HTML uses white-label tokens resolved at render time
-- by the web app via useTeamConfig():
--   {{TEAM_NAME}}     -> team name from GlobalDB team_config
--   {{PRIMARY_COLOR}} -> team primary color (hex)
--   {{ACCENT_COLOR}}  -> team accent color (hex)
--   {{SPORT_EMOJI}}   -> sport-specific emoji
--
-- Emoji stored as HTML decimal entities to avoid sqlcmd
-- encoding issues with supplementary Unicode characters.
--
-- created_by = 00000000-0000-0000-0000-000000000001 (system sentinel)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM dbo.feed_posts WHERE is_welcome_post = 1)
BEGIN
  DECLARE @WelcomeHtml NVARCHAR(MAX) =
    N'<div style="background:{{PRIMARY_COLOR}};border-radius:12px;padding:32px 28px;text-align:center;margin-bottom:20px;">'
  + N'<div style="font-size:52px;margin-bottom:12px;">{{SPORT_EMOJI}}</div>'
  + N'<h1 style="color:#ffffff;font-size:24px;font-weight:800;margin:0 0 8px 0;letter-spacing:-0.3px;">Welcome to {{TEAM_NAME}}</h1>'
  + N'<p style="color:rgba(255,255,255,0.75);font-size:15px;margin:0;line-height:1.5;">Your team management platform is live and ready to go.</p>'
  + N'</div>'
  + N'<p style="font-size:15px;color:#374151;line-height:1.7;margin:0 0 16px 0;">Everything your staff needs to run your program, in one place:</p>'
  + N'<div style="display:flex;flex-direction:column;gap:10px;margin-bottom:20px;">'
  + N'<div style="display:flex;gap:14px;align-items:flex-start;padding:14px 16px;background:#f9fafb;border-radius:10px;border-left:4px solid {{ACCENT_COLOR}};">'
  + N'<span style="font-size:20px;flex-shrink:0;margin-top:1px;">{{SPORT_EMOJI}}</span>'
  + N'<div><strong style="color:#111827;display:block;margin-bottom:3px;font-size:14px;">Roster</strong>'
  + N'<span style="font-size:13px;color:#6b7280;line-height:1.5;">Add and manage active players &#8212; positions, jersey numbers, academic years, and contact info.</span>'
  + N'</div></div>'
  + N'<div style="display:flex;gap:14px;align-items:flex-start;padding:14px 16px;background:#f9fafb;border-radius:10px;border-left:4px solid {{ACCENT_COLOR}};">'
  + N'<span style="font-size:20px;flex-shrink:0;margin-top:1px;">&#127891;</span>'
  + N'<div><strong style="color:#111827;display:block;margin-bottom:3px;font-size:14px;">Alumni CRM</strong>'
  + N'<span style="font-size:13px;color:#6b7280;line-height:1.5;">Stay connected with graduates. Log interactions, track employment, and keep lifelong relationships strong.</span>'
  + N'</div></div>'
  + N'<div style="display:flex;gap:14px;align-items:flex-start;padding:14px 16px;background:#f9fafb;border-radius:10px;border-left:4px solid {{ACCENT_COLOR}};">'
  + N'<span style="font-size:20px;flex-shrink:0;margin-top:1px;">&#128236;</span>'
  + N'<div><strong style="color:#111827;display:block;margin-bottom:3px;font-size:14px;">Communications</strong>'
  + N'<span style="font-size:13px;color:#6b7280;line-height:1.5;">Send targeted emails to players or alumni, post to this feed, and track open rates &#8212; all in one hub.</span>'
  + N'</div></div>'
  + N'<div style="display:flex;gap:14px;align-items:flex-start;padding:14px 16px;background:#f9fafb;border-radius:10px;border-left:4px solid {{ACCENT_COLOR}};">'
  + N'<span style="font-size:20px;flex-shrink:0;margin-top:1px;">&#9881;</span>'
  + N'<div><strong style="color:#111827;display:block;margin-bottom:3px;font-size:14px;">Team Settings</strong>'
  + N'<span style="font-size:13px;color:#6b7280;line-height:1.5;">Customize team colors, positions, and labels &#8212; changes apply instantly across the entire platform.</span>'
  + N'</div></div>'
  + N'</div>'
  + N'<p style="font-size:12px;color:#9ca3af;text-align:center;border-top:1px solid #e5e7eb;padding-top:14px;margin:0;">This post was pinned automatically when your account was set up.</p>';

  INSERT INTO dbo.feed_posts (
    id,
    created_by,
    title,
    body_html,
    audience,
    is_pinned,
    is_welcome_post
  )
  VALUES (
    NEWID(),
    CAST('00000000-0000-0000-0000-000000000001' AS UNIQUEIDENTIFIER),
    N'Welcome to {{TEAM_NAME}}',
    @WelcomeHtml,
    N'all',
    1,
    1
  );

  PRINT 'Seeded welcome post';
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
