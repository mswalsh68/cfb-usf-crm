-- ============================================================
-- APP DB — INITIAL SCHEMA
-- Creates a single tenant application database with separate
-- schemas for roster and alumni data, plus a shared dbo schema
-- for cross-cutting concerns.
--
-- Usage: Run once per tenant.
--   EXEC on: USFBullsApp, PlantPanthersApp, etc.
--
-- Create the DB first:
--   CREATE DATABASE USFBullsApp;
--   GO
--   USE USFBullsApp;
-- Then run this file.
-- ============================================================

-- ── Schemas ────────────────────────────────────────────────
CREATE SCHEMA roster;
GO
CREATE SCHEMA alumni;
GO

-- ============================================================
-- dbo schema — cross-cutting tables
-- ============================================================

-- graduation_log: audit trail for roster → alumni transfers
CREATE TABLE dbo.graduation_log (
  id                   UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  transaction_id       UNIQUEIDENTIFIER NOT NULL,
  player_id            UNIQUEIDENTIFIER NOT NULL,
  graduation_year      SMALLINT         NOT NULL,
  graduation_semester  NVARCHAR(10)     NOT NULL,
  triggered_by         UNIQUEIDENTIFIER     NULL,
  status               NVARCHAR(20)     NOT NULL DEFAULT 'success',  -- 'success' | 'failed'
  notes                NVARCHAR(MAX)        NULL,
  performed_at         DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_graduation_log_player    ON dbo.graduation_log (player_id);
CREATE INDEX IX_graduation_log_txn       ON dbo.graduation_log (transaction_id);

-- ============================================================
-- roster schema
-- ============================================================

CREATE TABLE roster.players (
  id                      UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  user_id                 UNIQUEIDENTIFIER NOT NULL,
  jersey_number           TINYINT              NULL,
  first_name              NVARCHAR(100)    NOT NULL,
  last_name               NVARCHAR(100)    NOT NULL,
  position                NVARCHAR(10)     NOT NULL,
  academic_year           NVARCHAR(20)     NOT NULL,
  status                  NVARCHAR(20)     NOT NULL DEFAULT 'active',
  height_inches           TINYINT              NULL,
  weight_lbs              SMALLINT             NULL,
  home_town               NVARCHAR(100)        NULL,
  home_state              NVARCHAR(50)         NULL,
  high_school             NVARCHAR(150)        NULL,
  recruiting_class        SMALLINT         NOT NULL,
  gpa                     DECIMAL(3,2)         NULL,
  major                   NVARCHAR(100)        NULL,
  phone                   NVARCHAR(20)         NULL,
  email                   NVARCHAR(255)        NULL,
  instagram               NVARCHAR(100)        NULL,
  twitter                 NVARCHAR(100)        NULL,
  snapchat                NVARCHAR(100)        NULL,
  emergency_contact_name  NVARCHAR(150)        NULL,
  emergency_contact_phone NVARCHAR(20)         NULL,
  notes                   NVARCHAR(MAX)        NULL,
  graduated_at            DATETIME2            NULL,
  created_at              DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at              DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_players_status   ON roster.players (status);
CREATE INDEX IX_players_position ON roster.players (position);
CREATE INDEX IX_players_name     ON roster.players (last_name, first_name);
CREATE UNIQUE INDEX UX_players_user ON roster.players (user_id);

CREATE TABLE roster.player_stats (
  id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  player_id    UNIQUEIDENTIFIER NOT NULL REFERENCES roster.players(id) ON DELETE CASCADE,
  season_year  SMALLINT         NOT NULL,
  games_played TINYINT              NULL,
  stats_json   NVARCHAR(MAX)        NULL,
  created_at   DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at   DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT UQ_player_season UNIQUE (player_id, season_year)
);

CREATE TABLE roster.player_documents (
  id             UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  player_id      UNIQUEIDENTIFIER NOT NULL REFERENCES roster.players(id) ON DELETE CASCADE,
  doc_type       NVARCHAR(50)     NOT NULL,
  file_name      NVARCHAR(255)    NOT NULL,
  azure_blob_url NVARCHAR(1000)   NOT NULL,
  uploaded_by    UNIQUEIDENTIFIER     NULL,
  uploaded_at    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
  expires_at     DATETIME2            NULL
);

-- ============================================================
-- alumni schema
-- ============================================================

CREATE TABLE alumni.alumni (
  id                   UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  user_id              UNIQUEIDENTIFIER     NULL,
  source_player_id     UNIQUEIDENTIFIER     NULL,   -- FK to roster.players.id (logical, no enforced FK for flexibility)
  first_name           NVARCHAR(100)    NOT NULL,
  last_name            NVARCHAR(100)    NOT NULL,
  graduation_year      SMALLINT         NOT NULL,
  graduation_semester  NVARCHAR(10)     NOT NULL DEFAULT 'spring',
  position             NVARCHAR(10)         NULL,
  recruiting_class     SMALLINT             NULL,
  status               NVARCHAR(20)     NOT NULL DEFAULT 'active',
  personal_email       NVARCHAR(255)        NULL,
  phone                NVARCHAR(20)         NULL,
  linkedin_url         NVARCHAR(500)        NULL,
  twitter_url          NVARCHAR(100)        NULL,
  current_employer     NVARCHAR(200)        NULL,
  current_job_title    NVARCHAR(150)        NULL,
  current_city         NVARCHAR(100)        NULL,
  current_state        NVARCHAR(50)         NULL,
  current_country      NVARCHAR(50)         NULL,
  is_donor             BIT              NOT NULL DEFAULT 0,
  last_donation_date   DATE                 NULL,
  total_donations      DECIMAL(10,2)    NOT NULL DEFAULT 0,
  engagement_score     TINYINT          NOT NULL DEFAULT 50,
  notes                NVARCHAR(MAX)        NULL,
  created_at           DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at           DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_alumni_status        ON alumni.alumni (status);
CREATE INDEX IX_alumni_grad_year     ON alumni.alumni (graduation_year);
CREATE INDEX IX_alumni_name          ON alumni.alumni (last_name, first_name);
CREATE INDEX IX_alumni_source_player ON alumni.alumni (source_player_id);

CREATE TABLE alumni.interaction_log (
  id          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  alumni_id   UNIQUEIDENTIFIER NOT NULL REFERENCES alumni.alumni(id) ON DELETE CASCADE,
  logged_by   UNIQUEIDENTIFIER     NULL,
  channel     NVARCHAR(30)     NOT NULL,
  summary     NVARCHAR(MAX)    NOT NULL,
  outcome     NVARCHAR(50)         NULL,
  follow_up_at DATETIME2           NULL,
  logged_at   DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_interaction_alumni ON alumni.interaction_log (alumni_id);

CREATE TABLE alumni.outreach_campaigns (
  id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  name             NVARCHAR(200)    NOT NULL,
  description      NVARCHAR(MAX)        NULL,
  target_audience  NVARCHAR(20)     NOT NULL,
  audience_filters NVARCHAR(MAX)        NULL,
  status           NVARCHAR(20)     NOT NULL DEFAULT 'draft',
  scheduled_at     DATETIME2            NULL,
  completed_at     DATETIME2            NULL,
  created_by       UNIQUEIDENTIFIER     NULL,
  created_at       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE alumni.outreach_messages (
  id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  campaign_id  UNIQUEIDENTIFIER NOT NULL REFERENCES alumni.outreach_campaigns(id) ON DELETE CASCADE,
  alumni_id    UNIQUEIDENTIFIER NOT NULL REFERENCES alumni.alumni(id),
  channel      NVARCHAR(20)     NOT NULL,
  status       NVARCHAR(20)     NOT NULL DEFAULT 'pending',
  content      NVARCHAR(MAX)        NULL,
  sent_at      DATETIME2            NULL,
  opened_at    DATETIME2            NULL,
  responded_at DATETIME2            NULL,
  created_at   DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_messages_campaign ON alumni.outreach_messages (campaign_id);
CREATE INDEX IX_messages_alumni   ON alumni.outreach_messages (alumni_id);
