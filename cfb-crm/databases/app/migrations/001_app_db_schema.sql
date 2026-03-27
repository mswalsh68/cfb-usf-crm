-- ============================================================
-- APP DATABASE SCHEMA — v1
-- Run on: each tenant AppDB (e.g. USFBullsApp, PlantPanthersApp)
-- Creates two schemas:
--   roster  — active player roster CRM
--   alumni  — alumni CRM and outreach
-- Stored procedures live in dbo schema (SQL Server convention).
-- ============================================================

-- ─── Schemas ──────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'roster')
  EXEC('CREATE SCHEMA roster');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'alumni')
  EXEC('CREATE SCHEMA alumni');
GO

-- ============================================================
-- ROSTER SCHEMA
-- ============================================================

-- ─── roster.players ──────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'roster' AND t.name = 'players')
BEGIN
  CREATE TABLE roster.players (
    id                      UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    user_id                 UNIQUEIDENTIFIER  NOT NULL UNIQUE,
    jersey_number           TINYINT,
    first_name              NVARCHAR(100)     NOT NULL,
    last_name               NVARCHAR(100)     NOT NULL,
    position                NVARCHAR(10)      NOT NULL
                              CHECK (position IN ('QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH')),
    academic_year           NVARCHAR(20)
                              CHECK (academic_year IN ('freshman','sophomore','junior','senior','graduate')),
    status                  NVARCHAR(20)      NOT NULL DEFAULT 'active'
                              CHECK (status IN ('active','injured','suspended','graduated','transferred','walkOn')),
    height_inches           TINYINT,
    weight_lbs              SMALLINT,
    home_town               NVARCHAR(100),
    home_state              NVARCHAR(50),
    high_school             NVARCHAR(150),
    recruiting_class        SMALLINT          NOT NULL,
    gpa                     DECIMAL(3,2),
    major                   NVARCHAR(100),
    phone                   NVARCHAR(20),
    email                   NVARCHAR(255),
    instagram               NVARCHAR(100),
    twitter                 NVARCHAR(100),
    snapchat                NVARCHAR(100),
    emergency_contact_name  NVARCHAR(150),
    emergency_contact_phone NVARCHAR(20),
    notes                   NVARCHAR(MAX),
    graduated_at            DATETIME2,
    created_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );

  CREATE INDEX idx_players_user_id    ON roster.players(user_id);
  CREATE INDEX idx_players_status     ON roster.players(status);
  CREATE INDEX idx_players_position   ON roster.players(position);
  CREATE INDEX idx_players_recruiting ON roster.players(recruiting_class);

  PRINT 'Created roster.players';
END
ELSE
  PRINT 'roster.players already exists — skipping';
GO

-- ─── roster.player_stats ─────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'roster' AND t.name = 'player_stats')
BEGIN
  CREATE TABLE roster.player_stats (
    id           UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    player_id    UNIQUEIDENTIFIER  NOT NULL REFERENCES roster.players(id) ON DELETE CASCADE,
    season_year  SMALLINT          NOT NULL,
    games_played TINYINT           DEFAULT 0,
    stats_json   NVARCHAR(MAX),
    created_at   DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at   DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_player_season UNIQUE (player_id, season_year)
  );

  CREATE INDEX idx_player_stats_player ON roster.player_stats(player_id);

  PRINT 'Created roster.player_stats';
END
ELSE
  PRINT 'roster.player_stats already exists — skipping';
GO

-- ─── roster.player_documents ─────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'roster' AND t.name = 'player_documents')
BEGIN
  CREATE TABLE roster.player_documents (
    id             UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    player_id      UNIQUEIDENTIFIER  NOT NULL REFERENCES roster.players(id) ON DELETE CASCADE,
    doc_type       NVARCHAR(50)      NOT NULL,
    file_name      NVARCHAR(255)     NOT NULL,
    azure_blob_url NVARCHAR(500)     NOT NULL,
    uploaded_by    UNIQUEIDENTIFIER  NOT NULL,
    uploaded_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    expires_at     DATETIME2
  );

  PRINT 'Created roster.player_documents';
END
ELSE
  PRINT 'roster.player_documents already exists — skipping';
GO

-- ─── roster.graduation_log ───────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'roster' AND t.name = 'graduation_log')
BEGIN
  CREATE TABLE roster.graduation_log (
    id                    UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    transaction_id        UNIQUEIDENTIFIER  NOT NULL,
    player_id             UNIQUEIDENTIFIER  NOT NULL REFERENCES roster.players(id),
    graduation_year       SMALLINT          NOT NULL,
    graduation_semester   NVARCHAR(10)      NOT NULL
                            CHECK (graduation_semester IN ('spring','fall','summer')),
    triggered_by          UNIQUEIDENTIFIER  NOT NULL,
    status                NVARCHAR(20)      NOT NULL DEFAULT 'success'
                            CHECK (status IN ('success','failed','rolled_back')),
    notes                 NVARCHAR(MAX),
    performed_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );

  CREATE INDEX idx_grad_log_transaction ON roster.graduation_log(transaction_id);
  CREATE INDEX idx_grad_log_player      ON roster.graduation_log(player_id);

  PRINT 'Created roster.graduation_log';
END
ELSE
  PRINT 'roster.graduation_log already exists — skipping';
GO

-- ============================================================
-- ALUMNI SCHEMA
-- ============================================================

-- ─── alumni.alumni ───────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'alumni' AND t.name = 'alumni')
BEGIN
  CREATE TABLE alumni.alumni (
    id                    UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    user_id               UNIQUEIDENTIFIER  NOT NULL UNIQUE,
    source_player_id      UNIQUEIDENTIFIER  NOT NULL,
    first_name            NVARCHAR(100)     NOT NULL,
    last_name             NVARCHAR(100)     NOT NULL,
    graduation_year       SMALLINT          NOT NULL,
    graduation_semester   NVARCHAR(10)      NOT NULL
                            CHECK (graduation_semester IN ('spring','fall','summer')),
    position              NVARCHAR(10)      NOT NULL,
    recruiting_class      SMALLINT          NOT NULL,
    status                NVARCHAR(20)      NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active','lostContact','deceased','doNotContact')),
    personal_email        NVARCHAR(255),
    phone                 NVARCHAR(20),
    linkedin_url          NVARCHAR(500),
    twitter_url           NVARCHAR(100),
    current_employer      NVARCHAR(200),
    current_job_title     NVARCHAR(150),
    current_city          NVARCHAR(100),
    current_state         NVARCHAR(50),
    current_country       NVARCHAR(100)     DEFAULT 'USA',
    is_donor              BIT               NOT NULL DEFAULT 0,
    last_donation_date    DATE,
    total_donations       DECIMAL(10,2)     DEFAULT 0,
    engagement_score      TINYINT           DEFAULT 50,
    notes                 NVARCHAR(MAX),
    created_at            DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at            DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );

  CREATE INDEX idx_alumni_user_id   ON alumni.alumni(user_id);
  CREATE INDEX idx_alumni_grad_year ON alumni.alumni(graduation_year);
  CREATE INDEX idx_alumni_status    ON alumni.alumni(status);
  CREATE INDEX idx_alumni_is_donor  ON alumni.alumni(is_donor);

  PRINT 'Created alumni.alumni';
END
ELSE
  PRINT 'alumni.alumni already exists — skipping';
GO

-- ─── alumni.outreach_campaigns ───────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'alumni' AND t.name = 'outreach_campaigns')
BEGIN
  CREATE TABLE alumni.outreach_campaigns (
    id                UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    name              NVARCHAR(200)     NOT NULL,
    description       NVARCHAR(MAX),
    target_audience   NVARCHAR(20)      NOT NULL DEFAULT 'all'
                        CHECK (target_audience IN ('all','byClass','byPosition','byStatus','custom')),
    audience_filters  NVARCHAR(MAX),
    status            NVARCHAR(20)      NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft','scheduled','active','completed','cancelled')),
    scheduled_at      DATETIME2,
    completed_at      DATETIME2,
    created_by        UNIQUEIDENTIFIER  NOT NULL,
    created_at        DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at        DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );

  CREATE INDEX idx_campaigns_status ON alumni.outreach_campaigns(status);

  PRINT 'Created alumni.outreach_campaigns';
END
ELSE
  PRINT 'alumni.outreach_campaigns already exists — skipping';
GO

-- ─── alumni.outreach_messages ────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'alumni' AND t.name = 'outreach_messages')
BEGIN
  CREATE TABLE alumni.outreach_messages (
    id          UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    campaign_id UNIQUEIDENTIFIER  NOT NULL REFERENCES alumni.outreach_campaigns(id),
    alumni_id   UNIQUEIDENTIFIER  NOT NULL REFERENCES alumni.alumni(id),
    channel     NVARCHAR(10)      NOT NULL
                  CHECK (channel IN ('email','sms','push')),
    status      NVARCHAR(20)      NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','sent','responded','bounced','unsubscribed')),
    content     NVARCHAR(MAX),
    sent_at     DATETIME2,
    opened_at   DATETIME2,
    responded_at DATETIME2,
    created_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );

  CREATE INDEX idx_messages_campaign ON alumni.outreach_messages(campaign_id);
  CREATE INDEX idx_messages_alumni   ON alumni.outreach_messages(alumni_id);

  PRINT 'Created alumni.outreach_messages';
END
ELSE
  PRINT 'alumni.outreach_messages already exists — skipping';
GO

-- ─── alumni.interaction_log ──────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'alumni' AND t.name = 'interaction_log')
BEGIN
  CREATE TABLE alumni.interaction_log (
    id           UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    alumni_id    UNIQUEIDENTIFIER  NOT NULL REFERENCES alumni.alumni(id) ON DELETE CASCADE,
    logged_by    UNIQUEIDENTIFIER  NOT NULL,
    channel      NVARCHAR(30)      NOT NULL,
    summary      NVARCHAR(MAX)     NOT NULL,
    outcome      NVARCHAR(50),
    follow_up_at DATETIME2,
    logged_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );

  CREATE INDEX idx_interactions_alumni ON alumni.interaction_log(alumni_id);

  PRINT 'Created alumni.interaction_log';
END
ELSE
  PRINT 'alumni.interaction_log already exists — skipping';
GO

PRINT '=== App DB schema v1 complete ===';
GO
