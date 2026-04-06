SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
-- ============================================================
-- APP DB — CONSOLIDATE PLAYERS + ALUMNI INTO dbo.users
-- Removes dbo.players and dbo.alumni tables entirely.
-- Player/alumni status is now a flag (status_id) on dbo.users.
-- All sport-specific and career columns merged into dbo.users.
--
-- Status types:
--   1 = current_player
--   2 = alumni
--   3 = removed
--
-- Graduate = UPDATE status_id = 2
-- Remove   = UPDATE status_id = 3
--
-- Create player flow: create account in CfbGlobal first,
-- pull that userID into AppDB — match on existing global ID.
--
-- Run on: each tenant AppDB after 008_consolidate_dbo_schema.sql
-- ============================================================

-- ─── Step 1: Drop existing RLS policies ──────────────────────
-- (They currently target dbo.players / dbo.alumni from migration 008)

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

-- ─── Step 2: dbo.player_status_types ─────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('dbo.player_status_types'))
BEGIN
  CREATE TABLE dbo.player_status_types (
    id   INT          NOT NULL PRIMARY KEY,
    name NVARCHAR(50) NOT NULL UNIQUE
  );
  INSERT INTO dbo.player_status_types (id, name) VALUES
    (1, 'current_player'),
    (2, 'alumni'),
    (3, 'removed');
  PRINT 'Created and seeded dbo.player_status_types';
END
ELSE
  PRINT 'dbo.player_status_types already exists — skipping';
GO

-- ─── Step 3: Add all player/alumni columns to dbo.users ──────
-- status_id is nullable: NULL = staff / coach (no player status)

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'status_id')
BEGIN
  ALTER TABLE dbo.users ADD status_id INT NULL REFERENCES dbo.player_status_types(id);
  EXEC sp_executesql N'CREATE INDEX IX_users_status ON dbo.users (status_id) WHERE status_id IS NOT NULL;';
  PRINT 'Added dbo.users.status_id';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'sport_id')
BEGIN
  ALTER TABLE dbo.users ADD sport_id UNIQUEIDENTIFIER NULL REFERENCES dbo.sports(id);
  EXEC sp_executesql N'CREATE INDEX IX_users_sport ON dbo.users (sport_id) WHERE sport_id IS NOT NULL;';
  PRINT 'Added dbo.users.sport_id';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'jersey_number')
BEGIN
  ALTER TABLE dbo.users ADD jersey_number TINYINT NULL;
  PRINT 'Added dbo.users.jersey_number';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'position')
BEGIN
  ALTER TABLE dbo.users ADD position NVARCHAR(10) NULL;
  PRINT 'Added dbo.users.position';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'academic_year')
BEGIN
  ALTER TABLE dbo.users ADD academic_year NVARCHAR(20) NULL;
  PRINT 'Added dbo.users.academic_year';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'height_inches')
BEGIN
  ALTER TABLE dbo.users ADD height_inches TINYINT NULL;
  PRINT 'Added dbo.users.height_inches';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'weight_lbs')
BEGIN
  ALTER TABLE dbo.users ADD weight_lbs SMALLINT NULL;
  PRINT 'Added dbo.users.weight_lbs';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'recruiting_class')
BEGIN
  ALTER TABLE dbo.users ADD recruiting_class SMALLINT NULL;
  PRINT 'Added dbo.users.recruiting_class';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'gpa')
BEGIN
  ALTER TABLE dbo.users ADD gpa DECIMAL(3,2) NULL;
  PRINT 'Added dbo.users.gpa';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'major')
BEGIN
  ALTER TABLE dbo.users ADD major NVARCHAR(100) NULL;
  PRINT 'Added dbo.users.major';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'graduated_at')
BEGIN
  ALTER TABLE dbo.users ADD graduated_at DATETIME2 NULL;
  PRINT 'Added dbo.users.graduated_at';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'graduation_year')
BEGIN
  ALTER TABLE dbo.users ADD graduation_year SMALLINT NULL;
  PRINT 'Added dbo.users.graduation_year';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'graduation_semester')
BEGIN
  ALTER TABLE dbo.users ADD graduation_semester NVARCHAR(10) NULL;
  PRINT 'Added dbo.users.graduation_semester';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'linkedin_url')
BEGIN
  ALTER TABLE dbo.users ADD linkedin_url NVARCHAR(500) NULL;
  PRINT 'Added dbo.users.linkedin_url';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'twitter_url')
BEGIN
  ALTER TABLE dbo.users ADD twitter_url NVARCHAR(100) NULL;
  PRINT 'Added dbo.users.twitter_url';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'current_employer')
BEGIN
  ALTER TABLE dbo.users ADD current_employer NVARCHAR(200) NULL;
  PRINT 'Added dbo.users.current_employer';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'current_job_title')
BEGIN
  ALTER TABLE dbo.users ADD current_job_title NVARCHAR(150) NULL;
  PRINT 'Added dbo.users.current_job_title';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'current_city')
BEGIN
  ALTER TABLE dbo.users ADD current_city NVARCHAR(100) NULL;
  PRINT 'Added dbo.users.current_city';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'current_state')
BEGIN
  ALTER TABLE dbo.users ADD current_state NVARCHAR(50) NULL;
  PRINT 'Added dbo.users.current_state';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'current_country')
BEGIN
  ALTER TABLE dbo.users ADD current_country NVARCHAR(100) NULL DEFAULT 'USA';
  PRINT 'Added dbo.users.current_country';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'is_donor')
BEGIN
  ALTER TABLE dbo.users ADD is_donor BIT NOT NULL DEFAULT 0;
  PRINT 'Added dbo.users.is_donor';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'last_donation_date')
BEGIN
  ALTER TABLE dbo.users ADD last_donation_date DATE NULL;
  PRINT 'Added dbo.users.last_donation_date';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'total_donations')
BEGIN
  ALTER TABLE dbo.users ADD total_donations DECIMAL(10,2) NULL DEFAULT 0;
  PRINT 'Added dbo.users.total_donations';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'engagement_score')
BEGIN
  ALTER TABLE dbo.users ADD engagement_score TINYINT NULL DEFAULT 50;
  PRINT 'Added dbo.users.engagement_score';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'communication_consent')
BEGIN
  ALTER TABLE dbo.users ADD communication_consent BIT NOT NULL DEFAULT 1;
  PRINT 'Added dbo.users.communication_consent';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'years_on_roster')
BEGIN
  ALTER TABLE dbo.users ADD years_on_roster NVARCHAR(50) NULL;
  PRINT 'Added dbo.users.years_on_roster';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'notes')
BEGIN
  ALTER TABLE dbo.users ADD notes NVARCHAR(MAX) NULL;
  PRINT 'Added dbo.users.notes';
END
GO

-- ─── Step 4: Migrate data from dbo.players into dbo.users ────

IF OBJECT_ID('dbo.players') IS NOT NULL
BEGIN
  -- Merge sport-specific columns from dbo.players into existing dbo.users rows
  EXEC sp_executesql N'
    UPDATE u SET
      status_id        = CASE p.status
                           WHEN ''graduated''   THEN 2
                           WHEN ''transferred'' THEN 3
                           ELSE 1
                         END,
      sport_id         = p.sport_id,
      jersey_number    = p.jersey_number,
      position         = p.position,
      academic_year    = p.academic_year,
      height_inches    = p.height_inches,
      weight_lbs       = p.weight_lbs,
      recruiting_class = p.recruiting_class,
      gpa              = p.gpa,
      major            = p.major,
      graduated_at     = p.graduated_at,
      notes            = p.notes,
      updated_at       = SYSUTCDATETIME()
    FROM dbo.users u
    JOIN dbo.players p ON p.user_id = u.id;
  ';
  PRINT 'Migrated dbo.players → dbo.users columns';
END
GO

-- ─── Step 5: Migrate data from dbo.alumni into dbo.users ─────

IF OBJECT_ID('dbo.alumni') IS NOT NULL
BEGIN
  EXEC sp_executesql N'
    UPDATE u SET
      status_id             = 2,   -- alumni
      sport_id              = COALESCE(u.sport_id, a.sport_id),
      graduation_year       = a.graduation_year,
      graduation_semester   = a.graduation_semester,
      linkedin_url          = a.linkedin_url,
      twitter_url           = a.twitter_url,
      current_employer      = a.current_employer,
      current_job_title     = a.current_job_title,
      current_city          = a.current_city,
      current_state         = a.current_state,
      current_country       = ISNULL(a.current_country, ''USA''),
      is_donor              = a.is_donor,
      last_donation_date    = a.last_donation_date,
      total_donations       = ISNULL(a.total_donations, 0),
      engagement_score      = ISNULL(a.engagement_score, 50),
      communication_consent = ISNULL(a.communication_consent, 1),
      years_on_roster       = a.years_on_roster,
      notes                 = ISNULL(a.notes, u.notes),
      updated_at            = SYSUTCDATETIME()
    FROM dbo.users u
    JOIN dbo.alumni a ON a.user_id = u.id;
  ';
  PRINT 'Migrated dbo.alumni → dbo.users columns';
END
GO

-- ─── Step 6: Retarget child-table FKs from players/alumni to dbo.users ──
-- Each operation: drop old FK → sp_rename column → add new FK.

-- dbo.player_stats: player_id → user_id
IF OBJECT_ID('dbo.player_stats') IS NOT NULL
  AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.player_stats') AND name = 'player_id')
BEGIN
  -- Map player_id values to the corresponding user_id
  EXEC sp_executesql N'
    UPDATE ps SET ps.player_id = p.user_id
    FROM dbo.player_stats ps
    JOIN dbo.players p ON p.id = ps.player_id
    WHERE EXISTS (SELECT 1 FROM dbo.players pp WHERE pp.id = ps.player_id);
  ';

  -- Drop FK and index, rename column, add new FK
  DECLARE @fkName NVARCHAR(256);
  SELECT @fkName = fk.name
  FROM sys.foreign_keys fk
  JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
  JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
  WHERE fk.parent_object_id = OBJECT_ID('dbo.player_stats') AND c.name = 'player_id';

  IF @fkName IS NOT NULL
    EXEC('ALTER TABLE dbo.player_stats DROP CONSTRAINT ' + @fkName);

  IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.player_stats') AND name = 'IX_player_stats_player')
    DROP INDEX IX_player_stats_player ON dbo.player_stats;

  EXEC sp_rename 'dbo.player_stats.player_id', 'user_id', 'COLUMN';
  ALTER TABLE dbo.player_stats ADD CONSTRAINT FK_player_stats_user FOREIGN KEY (user_id) REFERENCES dbo.users(id) ON DELETE CASCADE;
  CREATE INDEX IX_player_stats_user ON dbo.player_stats (user_id);
  PRINT 'Retargeted dbo.player_stats.player_id → user_id → dbo.users';
END
GO

-- dbo.player_documents: player_id → user_id
IF OBJECT_ID('dbo.player_documents') IS NOT NULL
  AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.player_documents') AND name = 'player_id')
BEGIN
  EXEC sp_executesql N'
    UPDATE pd SET pd.player_id = p.user_id
    FROM dbo.player_documents pd
    JOIN dbo.players p ON p.id = pd.player_id
    WHERE EXISTS (SELECT 1 FROM dbo.players pp WHERE pp.id = pd.player_id);
  ';

  DECLARE @fkName2 NVARCHAR(256);
  SELECT @fkName2 = fk.name
  FROM sys.foreign_keys fk
  JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
  JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
  WHERE fk.parent_object_id = OBJECT_ID('dbo.player_documents') AND c.name = 'player_id';

  IF @fkName2 IS NOT NULL
    EXEC('ALTER TABLE dbo.player_documents DROP CONSTRAINT ' + @fkName2);

  EXEC sp_rename 'dbo.player_documents.player_id', 'user_id', 'COLUMN';
  ALTER TABLE dbo.player_documents ADD CONSTRAINT FK_player_documents_user FOREIGN KEY (user_id) REFERENCES dbo.users(id) ON DELETE CASCADE;
  PRINT 'Retargeted dbo.player_documents.player_id → user_id → dbo.users';
END
GO

-- dbo.graduation_log: player_id → user_id
IF OBJECT_ID('dbo.graduation_log') IS NOT NULL
  AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.graduation_log') AND name = 'player_id')
BEGIN
  EXEC sp_executesql N'
    UPDATE gl SET gl.player_id = p.user_id
    FROM dbo.graduation_log gl
    JOIN dbo.players p ON p.id = gl.player_id
    WHERE EXISTS (SELECT 1 FROM dbo.players pp WHERE pp.id = gl.player_id);
  ';

  DECLARE @fkName3 NVARCHAR(256);
  SELECT @fkName3 = fk.name
  FROM sys.foreign_keys fk
  JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
  JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
  WHERE fk.parent_object_id = OBJECT_ID('dbo.graduation_log') AND c.name = 'player_id';

  IF @fkName3 IS NOT NULL
    EXEC('ALTER TABLE dbo.graduation_log DROP CONSTRAINT ' + @fkName3);

  IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.graduation_log') AND name = 'IX_grad_log_player')
    DROP INDEX IX_grad_log_player ON dbo.graduation_log;

  EXEC sp_rename 'dbo.graduation_log.player_id', 'user_id', 'COLUMN';
  ALTER TABLE dbo.graduation_log ADD CONSTRAINT FK_grad_log_user FOREIGN KEY (user_id) REFERENCES dbo.users(id);
  CREATE INDEX IX_grad_log_user ON dbo.graduation_log (user_id);
  PRINT 'Retargeted dbo.graduation_log.player_id → user_id → dbo.users';
END
GO

-- dbo.interaction_log: alumni_id → user_id
IF OBJECT_ID('dbo.interaction_log') IS NOT NULL
  AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.interaction_log') AND name = 'alumni_id')
BEGIN
  EXEC sp_executesql N'
    UPDATE il SET il.alumni_id = a.user_id
    FROM dbo.interaction_log il
    JOIN dbo.alumni a ON a.id = il.alumni_id
    WHERE EXISTS (SELECT 1 FROM dbo.alumni aa WHERE aa.id = il.alumni_id);
  ';

  DECLARE @fkName4 NVARCHAR(256);
  SELECT @fkName4 = fk.name
  FROM sys.foreign_keys fk
  JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
  JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
  WHERE fk.parent_object_id = OBJECT_ID('dbo.interaction_log') AND c.name = 'alumni_id';

  IF @fkName4 IS NOT NULL
    EXEC('ALTER TABLE dbo.interaction_log DROP CONSTRAINT ' + @fkName4);

  IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.interaction_log') AND name = 'IX_interactions_alumni')
    DROP INDEX IX_interactions_alumni ON dbo.interaction_log;

  EXEC sp_rename 'dbo.interaction_log.alumni_id', 'user_id', 'COLUMN';
  ALTER TABLE dbo.interaction_log ADD CONSTRAINT FK_interaction_log_user FOREIGN KEY (user_id) REFERENCES dbo.users(id) ON DELETE CASCADE;
  CREATE INDEX IX_interaction_log_user ON dbo.interaction_log (user_id);
  PRINT 'Retargeted dbo.interaction_log.alumni_id → user_id → dbo.users';
END
GO

-- dbo.outreach_messages: alumni_id → user_id
IF OBJECT_ID('dbo.outreach_messages') IS NOT NULL
  AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.outreach_messages') AND name = 'alumni_id')
BEGIN
  EXEC sp_executesql N'
    UPDATE om SET om.alumni_id = a.user_id
    FROM dbo.outreach_messages om
    JOIN dbo.alumni a ON a.id = om.alumni_id
    WHERE EXISTS (SELECT 1 FROM dbo.alumni aa WHERE aa.id = om.alumni_id);
  ';

  DECLARE @fkName5 NVARCHAR(256);
  SELECT @fkName5 = fk.name
  FROM sys.foreign_keys fk
  JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
  JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
  WHERE fk.parent_object_id = OBJECT_ID('dbo.outreach_messages') AND c.name = 'alumni_id';

  IF @fkName5 IS NOT NULL
    EXEC('ALTER TABLE dbo.outreach_messages DROP CONSTRAINT ' + @fkName5);

  IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.outreach_messages') AND name = 'IX_messages_alumni')
    DROP INDEX IX_messages_alumni ON dbo.outreach_messages;

  EXEC sp_rename 'dbo.outreach_messages.alumni_id', 'user_id', 'COLUMN';
  ALTER TABLE dbo.outreach_messages ADD CONSTRAINT FK_outreach_messages_user FOREIGN KEY (user_id) REFERENCES dbo.users(id);
  CREATE INDEX IX_outreach_messages_user ON dbo.outreach_messages (user_id);
  PRINT 'Retargeted dbo.outreach_messages.alumni_id → user_id → dbo.users';
END
GO

-- dbo.season_players: player_id → user_id
IF OBJECT_ID('dbo.season_players') IS NOT NULL
  AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.season_players') AND name = 'player_id')
BEGIN
  EXEC sp_executesql N'
    UPDATE sp SET sp.player_id = p.user_id
    FROM dbo.season_players sp
    JOIN dbo.players p ON p.id = sp.player_id
    WHERE EXISTS (SELECT 1 FROM dbo.players pp WHERE pp.id = sp.player_id);
  ';

  -- Drop composite PK, rename column, recreate PK
  DECLARE @pkName NVARCHAR(256);
  SELECT @pkName = name FROM sys.key_constraints
  WHERE parent_object_id = OBJECT_ID('dbo.season_players') AND type = 'PK';

  IF @pkName IS NOT NULL
    EXEC('ALTER TABLE dbo.season_players DROP CONSTRAINT ' + @pkName);

  EXEC sp_rename 'dbo.season_players.player_id', 'user_id', 'COLUMN';
  ALTER TABLE dbo.season_players ADD CONSTRAINT PK_season_players PRIMARY KEY (season_id, user_id);
  PRINT 'Retargeted dbo.season_players.player_id → user_id → dbo.users';
END
GO

-- ─── Step 7: Drop dbo.players and dbo.alumni ─────────────────
-- FK constraints pointing to these tables have all been retargeted above.

IF OBJECT_ID('dbo.alumni')  IS NOT NULL DROP TABLE dbo.alumni;
IF OBJECT_ID('dbo.players') IS NOT NULL DROP TABLE dbo.players;
PRINT 'Dropped dbo.players and dbo.alumni';
GO

-- ─── Step 8: Drop old RLS filter functions + recreate for dbo.users ──

IF OBJECT_ID('dbo.fn_roster_access') IS NOT NULL DROP FUNCTION dbo.fn_roster_access;
IF OBJECT_ID('dbo.fn_alumni_access') IS NOT NULL DROP FUNCTION dbo.fn_alumni_access;
GO

-- Unified access function for dbo.users.
-- Allows:
--   coach_admin for this sport         → sees all users (status 1 + 2)
--   roster_only_admin for this sport   → sees status 1 only
--   user sees their own row            → always
--   sport_id IS NULL (transition)      → any authenticated user

CREATE OR ALTER FUNCTION dbo.fn_user_access(
  @session_user_id  NVARCHAR(100),
  @session_user_role NVARCHAR(50),
  @row_sport_id     UNIQUEIDENTIFIER,
  @row_user_id      UNIQUEIDENTIFIER,
  @row_status_id    INT
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
    -- Roster-only admin sees current players only
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

CREATE SECURITY POLICY dbo.user_access_policy
  ADD FILTER PREDICATE dbo.fn_user_access(
    CAST(SESSION_CONTEXT(N'user_id')   AS NVARCHAR(100)),
    CAST(SESSION_CONTEXT(N'user_role') AS NVARCHAR(50)),
    sport_id,
    id,
    status_id
  ) ON dbo.users
WITH (STATE = ON);
PRINT 'Activated user_access_policy on dbo.users';
GO

PRINT '=== 009_users_status_consolidation complete ===';
GO
