SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
-- ============================================================
-- APP DB — RBAC INFRASTRUCTURE
-- Phase 0: Foundation tables required before any feature work.
-- Run on: each tenant AppDB (e.g. USFBullsApp)
-- Run after: 001_app_db_schema.sql
-- ============================================================

-- ─── Sports (organizational unit within a tenant) ─────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.sports'))
BEGIN
  CREATE TABLE dbo.sports (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    name            NVARCHAR(100)    NOT NULL,
    abbr            NVARCHAR(20)     NOT NULL,
    color_override  NVARCHAR(7)      NULL,       -- hex color, overrides tenant primary
    custom_fields   NVARCHAR(MAX)    NULL,       -- JSON
    is_active       BIT              NOT NULL DEFAULT 1,
    created_at      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT 'Created dbo.sports';
END

-- ─── User roles (sport-scoped, replaces app_permissions) ─────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.user_roles'))
BEGIN
  CREATE TABLE dbo.user_roles (
    id          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    user_id     UNIQUEIDENTIFIER NOT NULL,
    sport_id    UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.sports(id),
    role        NVARCHAR(50)     NOT NULL,   -- coach_admin | roster_only_admin | account_owner
    granted_at  DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    granted_by  UNIQUEIDENTIFIER NOT NULL,
    revoked_at  DATETIME2        NULL,
    is_active   AS (CASE WHEN revoked_at IS NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END) PERSISTED,
    CONSTRAINT UQ_user_sport_role UNIQUE (user_id, sport_id, role)
  );
  CREATE INDEX IX_user_roles_user   ON dbo.user_roles (user_id) WHERE revoked_at IS NULL;
  CREATE INDEX IX_user_roles_sport  ON dbo.user_roles (sport_id) WHERE revoked_at IS NULL;
  PRINT 'Created dbo.user_roles';
END

-- ─── Audit log (INSERT-ONLY — immutable FERPA compliance trail) ──
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.audit_log'))
BEGIN
  CREATE TABLE dbo.audit_log (
    audit_id      BIGINT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    timestamp     DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    user_id       UNIQUEIDENTIFIER NULL,
    user_role     NVARCHAR(50)     NULL,
    action        NVARCHAR(50)     NOT NULL,  -- create|read|update|delete|login|role_change|export
    resource_type NVARCHAR(50)     NULL,      -- roster_member|alumni|announcement|season|role_assignment
    resource_id   UNIQUEIDENTIFIER NULL,
    sport_id      UNIQUEIDENTIFIER NULL,
    ip_address    NVARCHAR(45)     NULL,
    success       BIT              NOT NULL DEFAULT 1,
    details       NVARCHAR(MAX)    NULL       -- JSON: changed fields, old/new values
  );
  CREATE INDEX IX_audit_log_user      ON dbo.audit_log (user_id, timestamp);
  CREATE INDEX IX_audit_log_resource  ON dbo.audit_log (resource_type, resource_id);
  CREATE INDEX IX_audit_log_timestamp ON dbo.audit_log (timestamp);
  PRINT 'Created dbo.audit_log';
END

-- DENY UPDATE/DELETE on audit_log to the application role
-- (run as a DBA after creating the app DB user)
-- DENY UPDATE ON dbo.audit_log TO [app_user];
-- DENY DELETE ON dbo.audit_log TO [app_user];

-- ─── Seasons ──────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.seasons'))
BEGIN
  CREATE TABLE dbo.seasons (
    id         UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    sport_id   UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.sports(id),
    name       NVARCHAR(100)    NOT NULL,
    start_date DATE             NULL,
    end_date   DATE             NULL,
    status     NVARCHAR(20)     NOT NULL DEFAULT 'upcoming',  -- upcoming|active|completed|archived
    created_at DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_seasons_sport ON dbo.seasons (sport_id);
  PRINT 'Created dbo.seasons';
END

-- ─── Season roster assignments ────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.season_players'))
BEGIN
  CREATE TABLE dbo.season_players (
    season_id  UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.seasons(id),
    player_id  UNIQUEIDENTIFIER NOT NULL,
    assigned_at DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    assigned_by UNIQUEIDENTIFIER NOT NULL,
    PRIMARY KEY (season_id, player_id)
  );
  PRINT 'Created dbo.season_players';
END

-- ─── Announcements (broadcast CRM — Starter tier) ────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.announcements'))
BEGIN
  CREATE TABLE dbo.announcements (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    sport_id        UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.sports(id),
    title           NVARCHAR(200)    NOT NULL,
    body            NVARCHAR(MAX)    NOT NULL,
    target_audience NVARCHAR(20)     NOT NULL,  -- roster|alumni|all
    created_by      UNIQUEIDENTIFIER NOT NULL,
    created_at      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_announcements_sport ON dbo.announcements (sport_id, created_at DESC);
  PRINT 'Created dbo.announcements';
END

-- ─── Migration history (per-tenant, tracks applied migrations) ─
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.migration_history'))
BEGIN
  CREATE TABLE dbo.migration_history (
    migration_id       INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    migration_name     NVARCHAR(200) NOT NULL UNIQUE,
    checksum           NVARCHAR(64)  NOT NULL,   -- SHA-256 of migration file contents
    applied_at         DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    applied_by         NVARCHAR(100) NOT NULL DEFAULT 'migration_runner',
    execution_time_ms  INT           NULL
  );
  PRINT 'Created dbo.migration_history';
END

PRINT '=== 003_rbac_infrastructure complete ===';
GO
