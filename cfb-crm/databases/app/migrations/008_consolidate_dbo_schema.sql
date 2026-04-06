SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
-- ============================================================
-- APP DB — CONSOLIDATE TO DBO SCHEMA
-- Replaces roster.* and alumni.* with dbo-only tables.
-- Introduces dbo.users (local identity cache) and dbo.users_sports.
-- 3NF: personal info (name, phone, contact) lives in dbo.users;
--      sport-specific attributes stay in dbo.players / dbo.alumni.
-- Run on: each tenant AppDB after 005_rls_policies.sql
-- ============================================================

-- ─── Step 1: Drop existing RLS policies ──────────────────────
-- Must be dropped before altering / dropping the tables they reference.

IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'roster_security_policy')
BEGIN
  DROP SECURITY POLICY dbo.roster_security_policy;
  PRINT 'Dropped roster_security_policy';
END
GO

IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'alumni_security_policy')
BEGIN
  DROP SECURITY POLICY dbo.alumni_security_policy;
  PRINT 'Dropped alumni_security_policy';
END
GO

-- ─── Step 2: dbo.users ───────────────────────────────────────
-- Local identity cache. id = CfbGlobal user GUID.
-- Personal info lives here once; players/alumni reference by user_id.

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.users'))
BEGIN
  CREATE TABLE dbo.users (
    id                      UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,   -- mirrors CfbGlobal.dbo.users.id
    email                   NVARCHAR(255)    NOT NULL,               -- login email (unique, nullable not enforced here — provisional imports use placeholder)
    first_name              NVARCHAR(100)    NOT NULL,
    last_name               NVARCHAR(100)    NOT NULL,
    phone                   NVARCHAR(20)     NULL,
    personal_email          NVARCHAR(255)    NULL,                   -- secondary/personal email if different
    home_town               NVARCHAR(100)    NULL,
    home_state              NVARCHAR(50)     NULL,
    high_school             NVARCHAR(150)    NULL,
    instagram               NVARCHAR(100)    NULL,
    twitter                 NVARCHAR(100)    NULL,
    snapchat                NVARCHAR(100)    NULL,
    emergency_contact_name  NVARCHAR(150)    NULL,
    emergency_contact_phone NVARCHAR(20)     NULL,
    created_at              DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at              DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE UNIQUE INDEX UX_users_email ON dbo.users (email);
  PRINT 'Created dbo.users';
END
ELSE
  PRINT 'dbo.users already exists — skipping';
GO

-- ─── Step 3: dbo.users_sports ────────────────────────────────
-- Junction: which sport(s) a user has been associated with
-- (as player or alumni). One row per user/sport pair.
-- username = display name for that sport context.

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.users_sports'))
BEGIN
  CREATE TABLE dbo.users_sports (
    user_id    UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id),
    sport_id   UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.sports(id),
    username   NVARCHAR(100)    NOT NULL,
    created_at DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_users_sports PRIMARY KEY (user_id, sport_id)
  );
  PRINT 'Created dbo.users_sports';
END
ELSE
  PRINT 'dbo.users_sports already exists — skipping';
GO

-- ─── Step 4: dbo.players ─────────────────────────────────────
-- Sport-specific roster record. Personal info is in dbo.users.

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.players'))
BEGIN
  CREATE TABLE dbo.players (
    id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    user_id             UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id),
    sport_id            UNIQUEIDENTIFIER NULL     REFERENCES dbo.sports(id),
    jersey_number       TINYINT          NULL,
    position            NVARCHAR(10)     NOT NULL,
    academic_year       NVARCHAR(20)     NULL
                          CHECK (academic_year IN ('freshman','sophomore','junior','senior','graduate')),
    status              NVARCHAR(20)     NOT NULL DEFAULT 'active'
                          CHECK (status IN ('active','injured','suspended','graduated','transferred','walkOn')),
    height_inches       TINYINT          NULL,
    weight_lbs          SMALLINT         NULL,
    recruiting_class    SMALLINT         NOT NULL,
    gpa                 DECIMAL(3,2)     NULL,
    major               NVARCHAR(100)    NULL,
    notes               NVARCHAR(MAX)    NULL,
    graduated_at        DATETIME2        NULL,
    user_classification NVARCHAR(20)     NOT NULL DEFAULT 'roster',
    created_at          DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at          DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_player_user_sport UNIQUE (user_id, sport_id)
  );
  CREATE INDEX IX_players_status     ON dbo.players (status);
  CREATE INDEX IX_players_position   ON dbo.players (position);
  CREATE INDEX IX_players_recruiting ON dbo.players (recruiting_class);
  CREATE INDEX IX_players_sport      ON dbo.players (sport_id) WHERE sport_id IS NOT NULL;
  PRINT 'Created dbo.players';
END
ELSE
  PRINT 'dbo.players already exists — skipping';
GO

-- ─── Step 5: dbo.alumni ──────────────────────────────────────
-- Alumni CRM record. Personal info is in dbo.users.
-- position / recruiting_class are derivable via source_player_id → dbo.players.

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.alumni'))
BEGIN
  CREATE TABLE dbo.alumni (
    id                    UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    user_id               UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id),
    sport_id              UNIQUEIDENTIFIER NULL     REFERENCES dbo.sports(id),
    source_player_id      UNIQUEIDENTIFIER NULL     REFERENCES dbo.players(id),
    graduation_year       SMALLINT         NOT NULL,
    graduation_semester   NVARCHAR(10)     NOT NULL
                            CHECK (graduation_semester IN ('spring','fall','summer')),
    status                NVARCHAR(20)     NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active','lostContact','deceased','doNotContact')),
    linkedin_url          NVARCHAR(500)    NULL,
    twitter_url           NVARCHAR(100)    NULL,
    current_employer      NVARCHAR(200)    NULL,
    current_job_title     NVARCHAR(150)    NULL,
    current_city          NVARCHAR(100)    NULL,
    current_state         NVARCHAR(50)     NULL,
    current_country       NVARCHAR(100)    NULL DEFAULT 'USA',
    is_donor              BIT              NOT NULL DEFAULT 0,
    last_donation_date    DATE             NULL,
    total_donations       DECIMAL(10,2)    NULL DEFAULT 0,
    engagement_score      TINYINT          NULL DEFAULT 50,
    communication_consent BIT              NOT NULL DEFAULT 1,
    years_on_roster       NVARCHAR(50)     NULL,
    notes                 NVARCHAR(MAX)    NULL,
    user_classification   NVARCHAR(20)     NOT NULL DEFAULT 'alumni',
    created_at            DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at            DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_alumni_user_sport UNIQUE (user_id, sport_id)
  );
  CREATE INDEX IX_alumni_grad_year ON dbo.alumni (graduation_year);
  CREATE INDEX IX_alumni_status    ON dbo.alumni (status);
  CREATE INDEX IX_alumni_is_donor  ON dbo.alumni (is_donor);
  CREATE INDEX IX_alumni_sport     ON dbo.alumni (sport_id) WHERE sport_id IS NOT NULL;
  PRINT 'Created dbo.alumni';
END
ELSE
  PRINT 'dbo.alumni already exists — skipping';
GO

-- ─── Step 6: dbo.player_stats ────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.player_stats'))
BEGIN
  CREATE TABLE dbo.player_stats (
    id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    player_id    UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.players(id) ON DELETE CASCADE,
    season_year  SMALLINT         NOT NULL,
    games_played TINYINT          NULL DEFAULT 0,
    stats_json   NVARCHAR(MAX)    NULL,
    created_at   DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at   DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_player_season UNIQUE (player_id, season_year)
  );
  CREATE INDEX IX_player_stats_player ON dbo.player_stats (player_id);
  PRINT 'Created dbo.player_stats';
END
ELSE
  PRINT 'dbo.player_stats already exists — skipping';
GO

-- ─── Step 7: dbo.player_documents ────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.player_documents'))
BEGIN
  CREATE TABLE dbo.player_documents (
    id             UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    player_id      UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.players(id) ON DELETE CASCADE,
    doc_type       NVARCHAR(50)     NOT NULL,
    file_name      NVARCHAR(255)    NOT NULL,
    azure_blob_url NVARCHAR(500)    NOT NULL,
    uploaded_by    UNIQUEIDENTIFIER NOT NULL,
    uploaded_at    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    expires_at     DATETIME2        NULL
  );
  PRINT 'Created dbo.player_documents';
END
ELSE
  PRINT 'dbo.player_documents already exists — skipping';
GO

-- ─── Step 8: dbo.graduation_log ──────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.graduation_log'))
BEGIN
  CREATE TABLE dbo.graduation_log (
    id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    transaction_id      UNIQUEIDENTIFIER NOT NULL,
    player_id           UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.players(id),
    graduation_year     SMALLINT         NOT NULL,
    graduation_semester NVARCHAR(10)     NOT NULL
                          CHECK (graduation_semester IN ('spring','fall','summer')),
    triggered_by        UNIQUEIDENTIFIER NOT NULL,
    status              NVARCHAR(20)     NOT NULL DEFAULT 'success'
                          CHECK (status IN ('success','failed','rolled_back')),
    notes               NVARCHAR(MAX)    NULL,
    performed_at        DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_grad_log_transaction ON dbo.graduation_log (transaction_id);
  CREATE INDEX IX_grad_log_player      ON dbo.graduation_log (player_id);
  PRINT 'Created dbo.graduation_log';
END
ELSE
  PRINT 'dbo.graduation_log already exists — skipping';
GO

-- ─── Step 9: dbo.outreach_campaigns ──────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.outreach_campaigns'))
BEGIN
  CREATE TABLE dbo.outreach_campaigns (
    id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    sport_id         UNIQUEIDENTIFIER NULL     REFERENCES dbo.sports(id),
    name             NVARCHAR(200)    NOT NULL,
    description      NVARCHAR(MAX)    NULL,
    target_audience  NVARCHAR(20)     NOT NULL DEFAULT 'all'
                       CHECK (target_audience IN ('all','byClass','byPosition','byStatus','custom')),
    audience_filters NVARCHAR(MAX)    NULL,
    status           NVARCHAR(20)     NOT NULL DEFAULT 'draft'
                       CHECK (status IN ('draft','scheduled','active','completed','cancelled')),
    scheduled_at     DATETIME2        NULL,
    completed_at     DATETIME2        NULL,
    created_by       UNIQUEIDENTIFIER NOT NULL,
    created_at       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_campaigns_status ON dbo.outreach_campaigns (status);
  PRINT 'Created dbo.outreach_campaigns';
END
ELSE
  PRINT 'dbo.outreach_campaigns already exists — skipping';
GO

-- ─── Step 10: dbo.outreach_messages ──────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.outreach_messages'))
BEGIN
  CREATE TABLE dbo.outreach_messages (
    id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    campaign_id  UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.outreach_campaigns(id),
    alumni_id    UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.alumni(id),
    channel      NVARCHAR(10)     NOT NULL CHECK (channel IN ('email','sms','push')),
    status       NVARCHAR(20)     NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','sent','responded','bounced','unsubscribed')),
    content      NVARCHAR(MAX)    NULL,
    sent_at      DATETIME2        NULL,
    opened_at    DATETIME2        NULL,
    responded_at DATETIME2        NULL,
    created_at   DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_messages_campaign ON dbo.outreach_messages (campaign_id);
  CREATE INDEX IX_messages_alumni   ON dbo.outreach_messages (alumni_id);
  PRINT 'Created dbo.outreach_messages';
END
ELSE
  PRINT 'dbo.outreach_messages already exists — skipping';
GO

-- ─── Step 11: dbo.interaction_log ────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.interaction_log'))
BEGIN
  CREATE TABLE dbo.interaction_log (
    id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    alumni_id    UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.alumni(id) ON DELETE CASCADE,
    logged_by    UNIQUEIDENTIFIER NOT NULL,
    channel      NVARCHAR(30)     NOT NULL,
    summary      NVARCHAR(MAX)    NOT NULL,
    outcome      NVARCHAR(50)     NULL,
    follow_up_at DATETIME2        NULL,
    logged_at    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_interactions_alumni ON dbo.interaction_log (alumni_id);
  PRINT 'Created dbo.interaction_log';
END
ELSE
  PRINT 'dbo.interaction_log already exists — skipping';
GO

-- ============================================================
-- DATA MIGRATION
-- Wrapped in a transaction. Roll back everything on failure.
-- Idempotent: all inserts check for pre-existing rows by id.
-- ============================================================

BEGIN TRY
  BEGIN TRANSACTION;

  -- ── dbo.users: merge from roster.players (preferred) then alumni.alumni ──

  IF OBJECT_ID('roster.players') IS NOT NULL
  BEGIN
    INSERT INTO dbo.users (
      id, email, first_name, last_name,
      phone, personal_email,
      home_town, home_state, high_school,
      instagram, twitter, snapchat,
      emergency_contact_name, emergency_contact_phone,
      created_at, updated_at
    )
    SELECT
      p.user_id,
      -- Use their email as login email; fall back to a unique placeholder
      ISNULL(p.email, 'provisional-' + LOWER(CAST(p.user_id AS NVARCHAR(36))) + '@import.local'),
      p.first_name,
      p.last_name,
      p.phone,
      p.email,       -- stored as personal_email (same value; may differ after account link)
      p.home_town, p.home_state, p.high_school,
      p.instagram, p.twitter, p.snapchat,
      p.emergency_contact_name, p.emergency_contact_phone,
      p.created_at, p.updated_at
    FROM roster.players p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.users u WHERE u.id = p.user_id);

    PRINT 'Migrated dbo.users from roster.players';
  END

  IF OBJECT_ID('alumni.alumni') IS NOT NULL
  BEGIN
    -- Alumni who were never on the roster (manually-added)
    INSERT INTO dbo.users (
      id, email, first_name, last_name,
      phone, personal_email,
      created_at, updated_at
    )
    SELECT
      a.user_id,
      ISNULL(a.personal_email, 'provisional-' + LOWER(CAST(a.user_id AS NVARCHAR(36))) + '@import.local'),
      a.first_name,
      a.last_name,
      a.phone,
      a.personal_email,
      a.created_at, a.updated_at
    FROM alumni.alumni a
    WHERE NOT EXISTS (SELECT 1 FROM dbo.users u WHERE u.id = a.user_id);

    PRINT 'Migrated dbo.users from alumni.alumni (new records only)';
  END

  -- ── dbo.players ──────────────────────────────────────────────

  IF OBJECT_ID('roster.players') IS NOT NULL
  BEGIN
    INSERT INTO dbo.players (
      id, user_id, sport_id,
      jersey_number, position, academic_year, status,
      height_inches, weight_lbs, recruiting_class,
      gpa, major, notes, graduated_at,
      user_classification, created_at, updated_at
    )
    SELECT
      p.id, p.user_id, p.sport_id,
      p.jersey_number, p.position, p.academic_year, p.status,
      p.height_inches, p.weight_lbs, p.recruiting_class,
      p.gpa, p.major, p.notes, p.graduated_at,
      ISNULL(p.user_classification, 'roster'),
      p.created_at, p.updated_at
    FROM roster.players p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.players dp WHERE dp.id = p.id);

    PRINT 'Migrated roster.players → dbo.players';
  END

  -- ── dbo.alumni ────────────────────────────────────────────────

  IF OBJECT_ID('alumni.alumni') IS NOT NULL
  BEGIN
    INSERT INTO dbo.alumni (
      id, user_id, sport_id, source_player_id,
      graduation_year, graduation_semester, status,
      linkedin_url, twitter_url,
      current_employer, current_job_title,
      current_city, current_state, current_country,
      is_donor, last_donation_date, total_donations,
      engagement_score, communication_consent,
      years_on_roster, notes,
      user_classification, created_at, updated_at
    )
    SELECT
      a.id,
      a.user_id,
      a.sport_id,
      -- Validate FK; set NULL if the player wasn't migrated
      CASE WHEN EXISTS (SELECT 1 FROM dbo.players p WHERE p.id = a.source_player_id)
           THEN a.source_player_id ELSE NULL END,
      a.graduation_year,
      a.graduation_semester,
      a.status,
      a.linkedin_url,
      a.twitter_url,
      a.current_employer,
      a.current_job_title,
      -- migration 004 added city/state as aliases; prefer them if populated
      ISNULL(a.city, a.current_city),
      ISNULL(a.state, a.current_state),
      a.current_country,
      a.is_donor,
      a.last_donation_date,
      a.total_donations,
      a.engagement_score,
      ISNULL(a.communication_consent, 1),
      a.years_on_roster,
      a.notes,
      ISNULL(a.user_classification, 'alumni'),
      a.created_at,
      a.updated_at
    FROM alumni.alumni a
    WHERE NOT EXISTS (SELECT 1 FROM dbo.alumni da WHERE da.id = a.id);

    PRINT 'Migrated alumni.alumni → dbo.alumni';
  END

  -- ── dbo.player_stats ─────────────────────────────────────────

  IF OBJECT_ID('roster.player_stats') IS NOT NULL
  BEGIN
    INSERT INTO dbo.player_stats (id, player_id, season_year, games_played, stats_json, created_at, updated_at)
    SELECT ps.id, ps.player_id, ps.season_year, ps.games_played, ps.stats_json, ps.created_at, ps.updated_at
    FROM roster.player_stats ps
    WHERE NOT EXISTS (SELECT 1 FROM dbo.player_stats dps WHERE dps.id = ps.id);

    PRINT 'Migrated roster.player_stats → dbo.player_stats';
  END

  -- ── dbo.player_documents ─────────────────────────────────────

  IF OBJECT_ID('roster.player_documents') IS NOT NULL
  BEGIN
    INSERT INTO dbo.player_documents (id, player_id, doc_type, file_name, azure_blob_url, uploaded_by, uploaded_at, expires_at)
    SELECT pd.id, pd.player_id, pd.doc_type, pd.file_name, pd.azure_blob_url, pd.uploaded_by, pd.uploaded_at, pd.expires_at
    FROM roster.player_documents pd
    WHERE NOT EXISTS (SELECT 1 FROM dbo.player_documents dpd WHERE dpd.id = pd.id);

    PRINT 'Migrated roster.player_documents → dbo.player_documents';
  END

  -- ── dbo.graduation_log ───────────────────────────────────────

  IF OBJECT_ID('roster.graduation_log') IS NOT NULL
  BEGIN
    INSERT INTO dbo.graduation_log (id, transaction_id, player_id, graduation_year, graduation_semester, triggered_by, status, notes, performed_at)
    SELECT gl.id, gl.transaction_id, gl.player_id, gl.graduation_year, gl.graduation_semester, gl.triggered_by, gl.status, gl.notes, gl.performed_at
    FROM roster.graduation_log gl
    WHERE NOT EXISTS (SELECT 1 FROM dbo.graduation_log dgl WHERE dgl.id = gl.id);

    PRINT 'Migrated roster.graduation_log → dbo.graduation_log';
  END

  -- ── dbo.outreach_campaigns ───────────────────────────────────

  IF OBJECT_ID('alumni.outreach_campaigns') IS NOT NULL
  BEGIN
    INSERT INTO dbo.outreach_campaigns (id, name, description, target_audience, audience_filters, status, scheduled_at, completed_at, created_by, created_at, updated_at)
    SELECT oc.id, oc.name, oc.description, oc.target_audience, oc.audience_filters, oc.status, oc.scheduled_at, oc.completed_at, oc.created_by, oc.created_at, oc.updated_at
    FROM alumni.outreach_campaigns oc
    WHERE NOT EXISTS (SELECT 1 FROM dbo.outreach_campaigns doc2 WHERE doc2.id = oc.id);

    PRINT 'Migrated alumni.outreach_campaigns → dbo.outreach_campaigns';
  END

  -- ── dbo.outreach_messages ────────────────────────────────────

  IF OBJECT_ID('alumni.outreach_messages') IS NOT NULL
  BEGIN
    INSERT INTO dbo.outreach_messages (id, campaign_id, alumni_id, channel, status, content, sent_at, opened_at, responded_at, created_at)
    SELECT om.id, om.campaign_id, om.alumni_id, om.channel, om.status, om.content, om.sent_at, om.opened_at, om.responded_at, om.created_at
    FROM alumni.outreach_messages om
    WHERE NOT EXISTS (SELECT 1 FROM dbo.outreach_messages dom WHERE dom.id = om.id);

    PRINT 'Migrated alumni.outreach_messages → dbo.outreach_messages';
  END

  -- ── dbo.interaction_log ──────────────────────────────────────

  IF OBJECT_ID('alumni.interaction_log') IS NOT NULL
  BEGIN
    INSERT INTO dbo.interaction_log (id, alumni_id, logged_by, channel, summary, outcome, follow_up_at, logged_at)
    SELECT il.id, il.alumni_id, il.logged_by, il.channel, il.summary, il.outcome, il.follow_up_at, il.logged_at
    FROM alumni.interaction_log il
    WHERE NOT EXISTS (SELECT 1 FROM dbo.interaction_log dil WHERE dil.id = il.id);

    PRINT 'Migrated alumni.interaction_log → dbo.interaction_log';
  END

  -- ── dbo.users_sports: derive from players + alumni ───────────

  INSERT INTO dbo.users_sports (user_id, sport_id, username)
  SELECT DISTINCT p.user_id, p.sport_id, u.first_name + ' ' + u.last_name
  FROM dbo.players p
  JOIN dbo.users u ON u.id = p.user_id
  WHERE p.sport_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM dbo.users_sports us WHERE us.user_id = p.user_id AND us.sport_id = p.sport_id);

  INSERT INTO dbo.users_sports (user_id, sport_id, username)
  SELECT DISTINCT a.user_id, a.sport_id, u.first_name + ' ' + u.last_name
  FROM dbo.alumni a
  JOIN dbo.users u ON u.id = a.user_id
  WHERE a.sport_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM dbo.users_sports us WHERE us.user_id = a.user_id AND us.sport_id = a.sport_id);

  PRINT 'Populated dbo.users_sports';

  COMMIT TRANSACTION;
  PRINT '=== Data migration complete ===';

END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
  DECLARE @errMsg NVARCHAR(MAX) = ERROR_MESSAGE();
  RAISERROR('Migration 008 failed: %s', 16, 1, @errMsg);
END CATCH;
GO

-- ============================================================
-- RLS: Recreate security policies on the new dbo tables
-- Filter functions (fn_roster_access, fn_alumni_access) remain
-- unchanged — they are schema-agnostic on the column parameters.
-- ============================================================

CREATE SECURITY POLICY dbo.roster_security_policy
  ADD FILTER PREDICATE dbo.fn_roster_access(
    CAST(SESSION_CONTEXT(N'user_id')   AS NVARCHAR(100)),
    CAST(SESSION_CONTEXT(N'user_role') AS NVARCHAR(50)),
    sport_id,
    user_id,
    user_classification
  ) ON dbo.players
WITH (STATE = ON);
PRINT 'Activated roster_security_policy on dbo.players';
GO

CREATE SECURITY POLICY dbo.alumni_security_policy
  ADD FILTER PREDICATE dbo.fn_alumni_access(
    CAST(SESSION_CONTEXT(N'user_id')   AS NVARCHAR(100)),
    CAST(SESSION_CONTEXT(N'user_role') AS NVARCHAR(50)),
    sport_id,
    user_id,
    user_classification
  ) ON dbo.alumni
WITH (STATE = ON);
PRINT 'Activated alumni_security_policy on dbo.alumni';
GO

-- ============================================================
-- DROP OLD TABLES & SCHEMAS
-- Run only after confirming data migration was successful.
-- FK order: child tables first.
-- ============================================================

-- alumni schema
IF OBJECT_ID('alumni.outreach_messages') IS NOT NULL DROP TABLE alumni.outreach_messages;
IF OBJECT_ID('alumni.interaction_log')   IS NOT NULL DROP TABLE alumni.interaction_log;
IF OBJECT_ID('alumni.outreach_campaigns')IS NOT NULL DROP TABLE alumni.outreach_campaigns;
IF OBJECT_ID('alumni.alumni')            IS NOT NULL DROP TABLE alumni.alumni;

-- roster schema
IF OBJECT_ID('roster.player_stats')      IS NOT NULL DROP TABLE roster.player_stats;
IF OBJECT_ID('roster.player_documents')  IS NOT NULL DROP TABLE roster.player_documents;
IF OBJECT_ID('roster.graduation_log')    IS NOT NULL DROP TABLE roster.graduation_log;
IF OBJECT_ID('roster.players')           IS NOT NULL DROP TABLE roster.players;

PRINT 'Dropped old schema tables';
GO

IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'alumni') EXEC('DROP SCHEMA alumni');
IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'roster') EXEC('DROP SCHEMA roster');
PRINT 'Dropped roster and alumni schemas';
GO

PRINT '=== 008_consolidate_dbo_schema complete ===';
GO
