-- ============================================================
-- RECREATE PHSPanthersApp — Drop and provision from scratch
-- Team: Plant Panthers  |  Abbr: PHS  |  Sport: football (high_school)
-- Run against: master (script switches context internally)
--
-- Safe to run when there is no live data in PHSPanthersApp.
-- After this script, run: sp_App_AllProcedures.sql against PHSPanthersApp
--   OR just run:  npm run deploy:prod:sps  (in ll-db-deploy)
-- ============================================================

USE master;
GO

-- ============================================================
-- DROP existing DB
-- ============================================================
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'PHSPanthersApp')
BEGIN
  ALTER DATABASE PHSPanthersApp SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  DROP DATABASE PHSPanthersApp;
  PRINT 'Dropped database: PHSPanthersApp';
END
GO

-- ============================================================
-- STEP 1 — Create the AppDB
-- ============================================================
DECLARE @AppDbName NVARCHAR(150) = 'PHSPanthersApp';
DECLARE @sql       NVARCHAR(MAX);

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @AppDbName)
BEGIN
  SET @sql = N'CREATE DATABASE [' + @AppDbName + N'];';
  EXEC sp_executesql @sql;
  PRINT 'Created database: ' + @AppDbName;
END
GO

USE PHSPanthersApp;
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
-- STEP 3 — SPORTS
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
-- STEP 4 — USERS
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'users' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.users (
    id                      UNIQUEIDENTIFIER  NOT NULL  PRIMARY KEY,
    email                   NVARCHAR(255)     NULL,
    first_name              NVARCHAR(100)     NOT NULL,
    last_name               NVARCHAR(100)     NOT NULL,
    status_id               INT               NOT NULL DEFAULT 1
                            REFERENCES dbo.player_status_types(id),
    sport_id                UNIQUEIDENTIFIER  NULL
                            REFERENCES dbo.sports(id),
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
    notes                   NVARCHAR(MAX)     NULL,
    created_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );

  CREATE UNIQUE INDEX uix_users_jersey_sport
    ON dbo.users (jersey_number, sport_id)
    WHERE jersey_number IS NOT NULL AND status_id = 1 AND sport_id IS NOT NULL;

  PRINT 'Created dbo.users';
END
GO

-- ============================================================
-- STEP 5 — USERS_SPORTS
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
-- STEP 8 — GRADUATION LOG
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
-- STEP 9 — INTERACTION LOG
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
-- STEP 13 — SEASON PLAYERS
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
-- STEP 15 — AUDIT LOG
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
-- ============================================================
IF EXISTS (
  SELECT 1 FROM sys.security_policies
  WHERE name = 'user_access_policy' AND schema_id = SCHEMA_ID('dbo')
)
BEGIN
  DROP SECURITY POLICY dbo.user_access_policy;
  PRINT 'Dropped existing RLS policy for refresh';
END
GO

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
    EXISTS (
      SELECT 1 FROM dbo.user_roles ur
      WHERE ur.user_id    = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
        AND ur.sport_id   = @row_sport_id
        AND ur.role       = 'coach_admin'
        AND ur.revoked_at IS NULL
    )
    OR
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
    @row_user_id = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
    OR
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
-- STEP 17 — MIGRATION HISTORY (all migrations pre-marked)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'migration_history' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.migration_history (
    id             INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    migration_name NVARCHAR(260) NOT NULL UNIQUE,
    applied_at     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    applied_by     NVARCHAR(100) NOT NULL DEFAULT SYSTEM_USER
  );

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
    ('011_drop_current_country.sql');

  PRINT 'Created dbo.migration_history (all historical migrations pre-marked)';
END
GO

-- ============================================================
-- STEP 18 — SEED: Standard sports
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
PRINT 'Seeded standard sports';
GO

-- ============================================================
-- STEP 19 — REGISTER / UPDATE team in LegacyLinkGlobal
-- (team already exists — IF NOT EXISTS skips the INSERT,
--  team_config seeded if not already present)
-- ============================================================
USE LegacyLinkGlobal;
GO

DECLARE @ClientName  NVARCHAR(100) = 'Plant Panthers';
DECLARE @ClientAbbr  NVARCHAR(10)  = 'PHS';
DECLARE @AppDbName   NVARCHAR(150) = 'PHSPanthersApp';
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
    @TeamId, @ClientName, @ClientAbbr, @Sport, @Level,
    '#1B1B2F', '#0D0D1A', '#EAEAF2',
    '#B8973D', '#9A7A2B', '#F5EDD5',
    'Roster', 'Alumni', 'Recruiting Class',
    '["QB","RB","WR","TE","OL","DL","LB","DB","K","P","LS","ATH"]',
    '["9th","10th","11th","12th"]'
  );
  PRINT 'Seeded team_config for: ' + @ClientAbbr;
END
GO

-- ============================================================
-- DONE — Next step: push SPs
--   npm run deploy:prod:sps   (in ll-db-deploy)
-- ============================================================
PRINT '';
PRINT '==========================================================';
PRINT 'PHSPanthersApp recreated successfully.';
PRINT 'Run sp_App_AllProcedures.sql against PHSPanthersApp';
PRINT 'OR:  npm run deploy:prod:sps  (in ll-db-deploy)';
PRINT '==========================================================';
GO
