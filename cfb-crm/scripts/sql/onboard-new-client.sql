-- ============================================================
-- LEGACYLINK — Onboard New Client
-- Run against: CfbGlobal (master DB connection is fine too)
-- ============================================================
-- ADMIN: Fill in the variables below, then run the full script.
--        Safe to run twice — all steps are idempotent.
-- ============================================================

USE CfbGlobal;
GO

-- ─── ADMIN: Set these before running ────────────────────────
DECLARE @ClientCode  NVARCHAR(10)  = 'HSFC';
DECLARE @ClientName  NVARCHAR(100) = 'Hillsborough High School Football';
DECLARE @ClientAbbr  NVARCHAR(10)  = 'HSFC';
DECLARE @Sport       NVARCHAR(50)  = 'football';
DECLARE @Level       NVARCHAR(20)  = 'high_school';   -- college | high_school | club
DECLARE @DbServer    NVARCHAR(200) = 'localhost\SQLEXPRESS';
-- ────────────────────────────────────────────────────────────

DECLARE @RosterDb NVARCHAR(110) = @ClientCode + '_Roster';
DECLARE @AlumniDb NVARCHAR(110) = @ClientCode + '_Alumni';
DECLARE @NewTeamId UNIQUEIDENTIFIER;
DECLARE @sql      NVARCHAR(MAX);

PRINT '============================================================';
PRINT 'Onboarding client: ' + @ClientName;
PRINT 'Roster DB : ' + @RosterDb;
PRINT 'Alumni DB : ' + @AlumniDb;
PRINT '============================================================';

-- ─── 1. Validate inputs ──────────────────────────────────────
IF @ClientCode IS NULL OR LEN(LTRIM(RTRIM(@ClientCode))) = 0
  THROW 50001, '@ClientCode is required.', 1;

IF @Level NOT IN ('college', 'high_school', 'club')
  THROW 50002, '@Level must be college, high_school, or club.', 1;

IF EXISTS (SELECT 1 FROM dbo.teams WHERE abbr = @ClientAbbr)
BEGIN
  PRINT 'Client ' + @ClientAbbr + ' already exists in teams table — skipping registration.';
  SELECT @NewTeamId = id FROM dbo.teams WHERE abbr = @ClientAbbr;
END

-- ─── 2. Create Roster database ──────────────────────────────
SET @sql = N'
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N''' + @RosterDb + N''')
BEGIN
  CREATE DATABASE [' + @RosterDb + N'];
  PRINT ''Created database ' + @RosterDb + N''';
END
ELSE
  PRINT ''Database ' + @RosterDb + N' already exists — skipping'';
';
EXEC sp_executesql @sql;
PRINT 'Step 2 complete: Roster database ready.';
GO

-- re-declare after GO
DECLARE @ClientCode  NVARCHAR(10)  = 'HSFC';
DECLARE @RosterDb    NVARCHAR(110) = @ClientCode + '_Roster';
DECLARE @AlumniDb    NVARCHAR(110) = @ClientCode + '_Alumni';
DECLARE @sql         NVARCHAR(MAX);

-- ─── 3. Create Alumni database ───────────────────────────────
SET @sql = N'
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N''' + @AlumniDb + N''')
BEGIN
  CREATE DATABASE [' + @AlumniDb + N'];
  PRINT ''Created database ' + @AlumniDb + N''';
END
ELSE
  PRINT ''Database ' + @AlumniDb + N' already exists — skipping'';
';
EXEC sp_executesql @sql;
PRINT 'Step 3 complete: Alumni database ready.';
GO

-- re-declare after GO
DECLARE @ClientCode  NVARCHAR(10)  = 'HSFC';
DECLARE @RosterDb    NVARCHAR(110) = @ClientCode + '_Roster';
DECLARE @AlumniDb    NVARCHAR(110) = @ClientCode + '_Alumni';
DECLARE @sql         NVARCHAR(MAX);

-- ─── 4. Apply Roster schema ──────────────────────────────────
-- players table (includes 002 email/social columns)
-- Note: position CHECK constraint is omitted for sport-agnostic provisioning.
SET @sql = N'USE [' + @RosterDb + N'];
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = ''players'')
BEGIN
  CREATE TABLE dbo.players (
    id                      UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    user_id                 UNIQUEIDENTIFIER  NOT NULL UNIQUE,
    jersey_number           TINYINT,
    first_name              NVARCHAR(100)     NOT NULL,
    last_name               NVARCHAR(100)     NOT NULL,
    position                NVARCHAR(10)      NOT NULL,
    academic_year           NVARCHAR(20),
    status                  NVARCHAR(20)      NOT NULL DEFAULT ''active''
                              CHECK (status IN (''active'',''injured'',''suspended'',''graduated'',''transferred'',''walkOn'')),
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
  PRINT ''Created players table'';
END
ELSE PRINT ''players table already exists — skipping'';';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @RosterDb + N'];
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = ''player_stats'')
BEGIN
  CREATE TABLE dbo.player_stats (
    id           UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    player_id    UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.players(id) ON DELETE CASCADE,
    season_year  SMALLINT          NOT NULL,
    games_played TINYINT           DEFAULT 0,
    stats_json   NVARCHAR(MAX),
    created_at   DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at   DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_player_season UNIQUE (player_id, season_year)
  );
  PRINT ''Created player_stats table'';
END
ELSE PRINT ''player_stats table already exists — skipping'';';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @RosterDb + N'];
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = ''player_documents'')
BEGIN
  CREATE TABLE dbo.player_documents (
    id             UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    player_id      UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.players(id) ON DELETE CASCADE,
    doc_type       NVARCHAR(50)      NOT NULL,
    file_name      NVARCHAR(255)     NOT NULL,
    azure_blob_url NVARCHAR(500)     NOT NULL,
    uploaded_by    UNIQUEIDENTIFIER  NOT NULL,
    uploaded_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    expires_at     DATETIME2
  );
  PRINT ''Created player_documents table'';
END
ELSE PRINT ''player_documents table already exists — skipping'';';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @RosterDb + N'];
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = ''graduation_log'')
BEGIN
  CREATE TABLE dbo.graduation_log (
    id                  UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    transaction_id      UNIQUEIDENTIFIER  NOT NULL,
    player_id           UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.players(id),
    graduation_year     SMALLINT          NOT NULL,
    graduation_semester NVARCHAR(10)      NOT NULL
                          CHECK (graduation_semester IN (''spring'',''fall'',''summer'')),
    triggered_by        UNIQUEIDENTIFIER  NOT NULL,
    status              NVARCHAR(20)      NOT NULL DEFAULT ''success''
                          CHECK (status IN (''success'',''failed'',''rolled_back'')),
    notes               NVARCHAR(MAX),
    performed_at        DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT ''Created graduation_log table'';
END
ELSE PRINT ''graduation_log table already exists — skipping'';';
EXEC sp_executesql @sql;

-- Roster indexes
SET @sql = N'USE [' + @RosterDb + N'];
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_players_user_id'')
  CREATE INDEX idx_players_user_id      ON dbo.players(user_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_players_status'')
  CREATE INDEX idx_players_status       ON dbo.players(status);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_players_position'')
  CREATE INDEX idx_players_position     ON dbo.players(position);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_players_recruiting'')
  CREATE INDEX idx_players_recruiting   ON dbo.players(recruiting_class);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_player_stats_player'')
  CREATE INDEX idx_player_stats_player  ON dbo.player_stats(player_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_grad_log_transaction'')
  CREATE INDEX idx_grad_log_transaction ON dbo.graduation_log(transaction_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_grad_log_player'')
  CREATE INDEX idx_grad_log_player      ON dbo.graduation_log(player_id);
PRINT ''Roster indexes ready'';';
EXEC sp_executesql @sql;

PRINT 'Step 4 complete: Roster schema applied.';

-- ─── 5. Apply Alumni schema ──────────────────────────────────
-- alumni table (includes 002 twitter_url column)
SET @sql = N'USE [' + @AlumniDb + N'];
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = ''alumni'')
BEGIN
  CREATE TABLE dbo.alumni (
    id                  UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    user_id             UNIQUEIDENTIFIER  NOT NULL UNIQUE,
    source_player_id    UNIQUEIDENTIFIER  NOT NULL,
    first_name          NVARCHAR(100)     NOT NULL,
    last_name           NVARCHAR(100)     NOT NULL,
    graduation_year     SMALLINT          NOT NULL,
    graduation_semester NVARCHAR(10)      NOT NULL
                          CHECK (graduation_semester IN (''spring'',''fall'',''summer'')),
    position            NVARCHAR(10)      NOT NULL,
    recruiting_class    SMALLINT          NOT NULL,
    status              NVARCHAR(20)      NOT NULL DEFAULT ''active''
                          CHECK (status IN (''active'',''lostContact'',''deceased'',''doNotContact'')),
    personal_email      NVARCHAR(255),
    phone               NVARCHAR(20),
    linkedin_url        NVARCHAR(500),
    twitter_url         NVARCHAR(100),
    current_employer    NVARCHAR(200),
    current_job_title   NVARCHAR(150),
    current_city        NVARCHAR(100),
    current_state       NVARCHAR(50),
    current_country     NVARCHAR(100)     DEFAULT ''USA'',
    is_donor            BIT               NOT NULL DEFAULT 0,
    last_donation_date  DATE,
    total_donations     DECIMAL(10,2)     DEFAULT 0,
    engagement_score    TINYINT           DEFAULT 50,
    notes               NVARCHAR(MAX),
    created_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT ''Created alumni table'';
END
ELSE PRINT ''alumni table already exists — skipping'';';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @AlumniDb + N'];
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = ''outreach_campaigns'')
BEGIN
  CREATE TABLE dbo.outreach_campaigns (
    id               UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    name             NVARCHAR(200)     NOT NULL,
    description      NVARCHAR(MAX),
    target_audience  NVARCHAR(20)      NOT NULL DEFAULT ''all''
                       CHECK (target_audience IN (''all'',''byClass'',''byPosition'',''byStatus'',''custom'')),
    audience_filters NVARCHAR(MAX),
    status           NVARCHAR(20)      NOT NULL DEFAULT ''draft''
                       CHECK (status IN (''draft'',''scheduled'',''active'',''completed'',''cancelled'')),
    scheduled_at     DATETIME2,
    completed_at     DATETIME2,
    created_by       UNIQUEIDENTIFIER  NOT NULL,
    created_at       DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at       DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT ''Created outreach_campaigns table'';
END
ELSE PRINT ''outreach_campaigns table already exists — skipping'';';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @AlumniDb + N'];
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = ''outreach_messages'')
BEGIN
  CREATE TABLE dbo.outreach_messages (
    id          UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    campaign_id UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.outreach_campaigns(id),
    alumni_id   UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.alumni(id),
    channel     NVARCHAR(10)      NOT NULL
                  CHECK (channel IN (''email'',''sms'',''push'')),
    status      NVARCHAR(20)      NOT NULL DEFAULT ''pending''
                  CHECK (status IN (''pending'',''sent'',''responded'',''bounced'',''unsubscribed'')),
    content     NVARCHAR(MAX),
    sent_at     DATETIME2,
    opened_at   DATETIME2,
    responded_at DATETIME2,
    created_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT ''Created outreach_messages table'';
END
ELSE PRINT ''outreach_messages table already exists — skipping'';';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @AlumniDb + N'];
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = ''interaction_log'')
BEGIN
  CREATE TABLE dbo.interaction_log (
    id           UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    alumni_id    UNIQUEIDENTIFIER  NOT NULL REFERENCES dbo.alumni(id) ON DELETE CASCADE,
    logged_by    UNIQUEIDENTIFIER  NOT NULL,
    channel      NVARCHAR(30)      NOT NULL,
    summary      NVARCHAR(MAX)     NOT NULL,
    outcome      NVARCHAR(50),
    follow_up_at DATETIME2,
    logged_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
  );
  PRINT ''Created interaction_log table'';
END
ELSE PRINT ''interaction_log table already exists — skipping'';';
EXEC sp_executesql @sql;

-- Alumni indexes
SET @sql = N'USE [' + @AlumniDb + N'];
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_alumni_user_id'')
  CREATE INDEX idx_alumni_user_id      ON dbo.alumni(user_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_alumni_grad_year'')
  CREATE INDEX idx_alumni_grad_year    ON dbo.alumni(graduation_year);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_alumni_status'')
  CREATE INDEX idx_alumni_status       ON dbo.alumni(status);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_alumni_is_donor'')
  CREATE INDEX idx_alumni_is_donor     ON dbo.alumni(is_donor);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_campaigns_status'')
  CREATE INDEX idx_campaigns_status    ON dbo.outreach_campaigns(status);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_messages_campaign'')
  CREATE INDEX idx_messages_campaign   ON dbo.outreach_messages(campaign_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_messages_alumni'')
  CREATE INDEX idx_messages_alumni     ON dbo.outreach_messages(alumni_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = ''idx_interactions_alumni'')
  CREATE INDEX idx_interactions_alumni ON dbo.interaction_log(alumni_id);
PRINT ''Alumni indexes ready'';';
EXEC sp_executesql @sql;

PRINT 'Step 5 complete: Alumni schema applied.';

-- ─── 6. Apply Roster stored procedures ──────────────────────
-- Each SP is set into @sql then executed in the target DB.
-- GO is not used inside sp_executesql — single batch per SP.

SET @sql = N'USE [' + @RosterDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_GetPlayers
  @Search          NVARCHAR(255) = NULL,
  @Status          NVARCHAR(20)  = NULL,
  @Position        NVARCHAR(10)  = NULL,
  @AcademicYear    NVARCHAR(20)  = NULL,
  @RecruitingClass SMALLINT      = NULL,
  @Page            INT           = 1,
  @PageSize        INT           = 50,
  @TotalCount      INT           OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @Offset     INT          = (@Page - 1) * @PageSize;
  DECLARE @SearchWild NVARCHAR(257)= ''%'' + ISNULL(@Search, '''') + ''%'';
  DECLARE @ExactNum   NVARCHAR(10) = ISNULL(@Search, '''');

  SELECT @TotalCount = COUNT(*)
  FROM dbo.players p
  WHERE (@Status          IS NULL OR p.status         = @Status)
    AND (@Position        IS NULL OR p.position       = @Position)
    AND (@AcademicYear    IS NULL OR p.academic_year  = @AcademicYear)
    AND (@RecruitingClass IS NULL OR p.recruiting_class = @RecruitingClass)
    AND (@Search IS NULL OR p.first_name LIKE @SearchWild OR p.last_name LIKE @SearchWild
         OR CAST(p.jersey_number AS NVARCHAR) = @ExactNum);

  SELECT
    p.id, p.user_id AS userId, p.jersey_number AS jerseyNumber,
    p.first_name AS firstName, p.last_name AS lastName,
    p.position, p.academic_year AS academicYear, p.status,
    p.height_inches AS heightInches, p.weight_lbs AS weightLbs,
    p.home_town AS homeTown, p.home_state AS homeState,
    p.high_school AS highSchool, p.recruiting_class AS recruitingClass,
    p.gpa, p.major, p.phone, p.email, p.instagram, p.twitter, p.snapchat,
    p.emergency_contact_name AS emergencyContactName,
    p.emergency_contact_phone AS emergencyContactPhone,
    p.notes, p.graduated_at AS graduatedAt,
    p.created_at AS createdAt, p.updated_at AS updatedAt
  FROM dbo.players p
  WHERE (@Status          IS NULL OR p.status         = @Status)
    AND (@Position        IS NULL OR p.position       = @Position)
    AND (@AcademicYear    IS NULL OR p.academic_year  = @AcademicYear)
    AND (@RecruitingClass IS NULL OR p.recruiting_class = @RecruitingClass)
    AND (@Search IS NULL OR p.first_name LIKE @SearchWild OR p.last_name LIKE @SearchWild
         OR CAST(p.jersey_number AS NVARCHAR) = @ExactNum)
  ORDER BY p.last_name, p.first_name
  OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @RosterDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_GetPlayerById
  @PlayerId  UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  IF NOT EXISTS (SELECT 1 FROM dbo.players WHERE id = @PlayerId)
  BEGIN
    SET @ErrorCode = ''PLAYER_NOT_FOUND'';
    RETURN;
  END
  SELECT
    p.id, p.user_id AS userId, p.jersey_number AS jerseyNumber,
    p.first_name AS firstName, p.last_name AS lastName,
    p.position, p.academic_year AS academicYear, p.status,
    p.height_inches AS heightInches, p.weight_lbs AS weightLbs,
    p.home_town AS homeTown, p.home_state AS homeState,
    p.high_school AS highSchool, p.recruiting_class AS recruitingClass,
    p.gpa, p.major, p.phone, p.email, p.instagram, p.twitter, p.snapchat,
    p.emergency_contact_name AS emergencyContactName,
    p.emergency_contact_phone AS emergencyContactPhone,
    p.notes, p.graduated_at AS graduatedAt,
    p.created_at AS createdAt, p.updated_at AS updatedAt
  FROM dbo.players p WHERE p.id = @PlayerId;
  SELECT ps.season_year AS seasonYear, ps.games_played AS gamesPlayed,
         ps.stats_json AS statsJson, ps.updated_at AS updatedAt
  FROM dbo.player_stats ps
  WHERE ps.player_id = @PlayerId
  ORDER BY ps.season_year DESC;
END;';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @RosterDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_CreatePlayer
  @UserId                UNIQUEIDENTIFIER,
  @JerseyNumber          TINYINT          = NULL,
  @FirstName             NVARCHAR(100),
  @LastName              NVARCHAR(100),
  @Position              NVARCHAR(10),
  @AcademicYear          NVARCHAR(20),
  @RecruitingClass       SMALLINT,
  @HeightInches          TINYINT          = NULL,
  @WeightLbs             SMALLINT         = NULL,
  @HomeTown              NVARCHAR(100)    = NULL,
  @HomeState             NVARCHAR(50)     = NULL,
  @HighSchool            NVARCHAR(150)    = NULL,
  @Gpa                   DECIMAL(3,2)     = NULL,
  @Major                 NVARCHAR(100)    = NULL,
  @Phone                 NVARCHAR(20)     = NULL,
  @Email                 NVARCHAR(255)    = NULL,
  @Instagram             NVARCHAR(100)    = NULL,
  @Twitter               NVARCHAR(100)    = NULL,
  @Snapchat              NVARCHAR(100)    = NULL,
  @EmergencyContactName  NVARCHAR(150)    = NULL,
  @EmergencyContactPhone NVARCHAR(20)     = NULL,
  @Notes                 NVARCHAR(MAX)    = NULL,
  @CreatedBy             UNIQUEIDENTIFIER,
  @NewPlayerId           UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode             NVARCHAR(50)     OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  IF @RecruitingClass < 2000 OR @RecruitingClass > 2100
  BEGIN SET @ErrorCode = ''INVALID_RECRUITING_CLASS''; RETURN; END
  IF EXISTS (SELECT 1 FROM dbo.players WHERE user_id = @UserId)
  BEGIN SET @ErrorCode = ''PLAYER_ALREADY_EXISTS_FOR_USER''; RETURN; END
  IF @JerseyNumber IS NOT NULL AND EXISTS (
    SELECT 1 FROM dbo.players WHERE jersey_number = @JerseyNumber AND status = ''active'')
  BEGIN SET @ErrorCode = ''JERSEY_NUMBER_IN_USE''; RETURN; END
  SET @NewPlayerId = NEWID();
  INSERT INTO dbo.players (
    id, user_id, jersey_number, first_name, last_name, position, academic_year,
    recruiting_class, height_inches, weight_lbs, home_town, home_state, high_school,
    gpa, major, phone, email, instagram, twitter, snapchat,
    emergency_contact_name, emergency_contact_phone, notes)
  VALUES (
    @NewPlayerId, @UserId, @JerseyNumber, @FirstName, @LastName, @Position, @AcademicYear,
    @RecruitingClass, @HeightInches, @WeightLbs, @HomeTown, @HomeState, @HighSchool,
    @Gpa, @Major, @Phone, @Email, @Instagram, @Twitter, @Snapchat,
    @EmergencyContactName, @EmergencyContactPhone, @Notes);
END;';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @RosterDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_UpdatePlayer
  @PlayerId              UNIQUEIDENTIFIER,
  @JerseyNumber          TINYINT          = NULL,
  @Position              NVARCHAR(10)     = NULL,
  @AcademicYear          NVARCHAR(20)     = NULL,
  @Status                NVARCHAR(20)     = NULL,
  @HeightInches          TINYINT          = NULL,
  @WeightLbs             SMALLINT         = NULL,
  @Gpa                   DECIMAL(3,2)     = NULL,
  @Major                 NVARCHAR(100)    = NULL,
  @Phone                 NVARCHAR(20)     = NULL,
  @Email                 NVARCHAR(255)    = NULL,
  @Instagram             NVARCHAR(100)    = NULL,
  @Twitter               NVARCHAR(100)    = NULL,
  @Snapchat              NVARCHAR(100)    = NULL,
  @EmergencyContactName  NVARCHAR(150)    = NULL,
  @EmergencyContactPhone NVARCHAR(20)     = NULL,
  @Notes                 NVARCHAR(MAX)    = NULL,
  @UpdatedBy             UNIQUEIDENTIFIER,
  @ErrorCode             NVARCHAR(50)     OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  IF NOT EXISTS (SELECT 1 FROM dbo.players WHERE id = @PlayerId)
  BEGIN SET @ErrorCode = ''PLAYER_NOT_FOUND''; RETURN; END
  IF @Status = ''graduated''
  BEGIN SET @ErrorCode = ''USE_SP_GRADUATE_PLAYER''; RETURN; END
  IF @Status IS NOT NULL AND @Status NOT IN (''active'',''injured'',''suspended'',''transferred'',''walkOn'')
  BEGIN SET @ErrorCode = ''INVALID_STATUS''; RETURN; END
  IF @JerseyNumber IS NOT NULL AND EXISTS (
    SELECT 1 FROM dbo.players
    WHERE jersey_number = @JerseyNumber AND status = ''active'' AND id <> @PlayerId)
  BEGIN SET @ErrorCode = ''JERSEY_NUMBER_IN_USE''; RETURN; END
  UPDATE dbo.players SET
    jersey_number           = COALESCE(@JerseyNumber,          jersey_number),
    position                = COALESCE(@Position,              position),
    academic_year           = COALESCE(@AcademicYear,          academic_year),
    status                  = COALESCE(@Status,                status),
    height_inches           = COALESCE(@HeightInches,          height_inches),
    weight_lbs              = COALESCE(@WeightLbs,             weight_lbs),
    gpa                     = COALESCE(@Gpa,                   gpa),
    major                   = COALESCE(@Major,                 major),
    phone                   = COALESCE(@Phone,                 phone),
    email                   = COALESCE(@Email,                 email),
    instagram               = COALESCE(@Instagram,             instagram),
    twitter                 = COALESCE(@Twitter,               twitter),
    snapchat                = COALESCE(@Snapchat,              snapchat),
    emergency_contact_name  = COALESCE(@EmergencyContactName,  emergency_contact_name),
    emergency_contact_phone = COALESCE(@EmergencyContactPhone, emergency_contact_phone),
    notes                   = COALESCE(@Notes,                 notes),
    updated_at              = SYSUTCDATETIME()
  WHERE id = @PlayerId;
END;';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @RosterDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_UpsertPlayerStats
  @PlayerId    UNIQUEIDENTIFIER,
  @SeasonYear  SMALLINT,
  @GamesPlayed TINYINT       = NULL,
  @StatsJson   NVARCHAR(MAX) = NULL,
  @ErrorCode   NVARCHAR(50)  OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  IF NOT EXISTS (SELECT 1 FROM dbo.players WHERE id = @PlayerId)
  BEGIN SET @ErrorCode = ''PLAYER_NOT_FOUND''; RETURN; END
  IF EXISTS (SELECT 1 FROM dbo.player_stats WHERE player_id = @PlayerId AND season_year = @SeasonYear)
  BEGIN
    UPDATE dbo.player_stats SET
      games_played = COALESCE(@GamesPlayed, games_played),
      stats_json   = COALESCE(@StatsJson,   stats_json),
      updated_at   = SYSUTCDATETIME()
    WHERE player_id = @PlayerId AND season_year = @SeasonYear;
  END
  ELSE
  BEGIN
    INSERT INTO dbo.player_stats (player_id, season_year, games_played, stats_json)
    VALUES (@PlayerId, @SeasonYear, @GamesPlayed, @StatsJson);
  END
END;';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @RosterDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_TransferToAlumni
  @PlayerIds         NVARCHAR(MAX),
  @TransferReason    NVARCHAR(50),
  @TransferYear      SMALLINT,
  @TransferSemester  NVARCHAR(10),
  @Notes             NVARCHAR(MAX)    = NULL,
  @TriggeredBy       NVARCHAR(100),
  @TransactionId     UNIQUEIDENTIFIER OUTPUT,
  @SuccessCount      INT              OUTPUT,
  @FailureJson       NVARCHAR(MAX)    OUTPUT,
  @PlayersJson       NVARCHAR(MAX)    OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  SET @TransactionId = NEWID();
  SET @SuccessCount  = 0;
  SET @FailureJson   = ''[]'';
  SET @PlayersJson   = ''[]'';

  DECLARE @failures    TABLE (player_id NVARCHAR(100), reason NVARCHAR(500));
  DECLARE @transferred TABLE (
    player_id UNIQUEIDENTIFIER, user_id UNIQUEIDENTIFIER,
    first_name NVARCHAR(100), last_name NVARCHAR(100),
    position NVARCHAR(10), recruiting_class SMALLINT,
    phone NVARCHAR(20), email NVARCHAR(255));
  DECLARE @playerIds2 TABLE (player_id UNIQUEIDENTIFIER);
  DECLARE @currentId  UNIQUEIDENTIFIER;

  INSERT INTO @playerIds2 (player_id)
  SELECT TRY_CAST([value] AS UNIQUEIDENTIFIER)
  FROM OPENJSON(@PlayerIds)
  WHERE TRY_CAST([value] AS UNIQUEIDENTIFIER) IS NOT NULL;

  DECLARE player_cursor CURSOR FOR SELECT player_id FROM @playerIds2;
  OPEN player_cursor;
  FETCH NEXT FROM player_cursor INTO @currentId;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      BEGIN TRANSACTION;
        DECLARE @fn NVARCHAR(100), @ln NVARCHAR(100), @pos NVARCHAR(10);
        DECLARE @rc SMALLINT, @uid UNIQUEIDENTIFIER, @st NVARCHAR(20);
        DECLARE @ph NVARCHAR(20), @em NVARCHAR(255);
        SELECT @fn = first_name, @ln = last_name, @pos = position,
               @rc = recruiting_class, @uid = user_id, @st = status,
               @ph = phone, @em = email
        FROM dbo.players WHERE id = @currentId;
        IF @uid IS NULL
        BEGIN
          ROLLBACK TRANSACTION;
          INSERT INTO @failures VALUES (CAST(@currentId AS NVARCHAR(100)), ''Player not found'');
          FETCH NEXT FROM player_cursor INTO @currentId;
          CONTINUE;
        END
        IF @st = ''graduated''
        BEGIN
          ROLLBACK TRANSACTION;
          INSERT INTO @failures VALUES (CAST(@currentId AS NVARCHAR(100)), ''Player already graduated'');
          FETCH NEXT FROM player_cursor INTO @currentId;
          CONTINUE;
        END
        UPDATE dbo.players SET
          status       = ''graduated'',
          graduated_at = SYSUTCDATETIME(),
          notes        = ISNULL(notes + CHAR(10), '''') + ''Transfer reason: '' + @TransferReason,
          updated_at   = SYSUTCDATETIME()
        WHERE id = @currentId;
        INSERT INTO @transferred (player_id, user_id, first_name, last_name, position, recruiting_class, phone, email)
        VALUES (@currentId, @uid, @fn, @ln, @pos, @rc, @ph, @em);
        SET @SuccessCount = @SuccessCount + 1;
      COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
      IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
      INSERT INTO @failures VALUES (CAST(@currentId AS NVARCHAR(100)), ERROR_MESSAGE());
    END CATCH;
    FETCH NEXT FROM player_cursor INTO @currentId;
  END
  CLOSE player_cursor;
  DEALLOCATE player_cursor;

  SELECT @FailureJson = ISNULL(
    (SELECT player_id AS playerId, reason FROM @failures FOR JSON PATH), ''[]'');
  SELECT @PlayersJson = ISNULL(
    (SELECT CAST(player_id AS NVARCHAR(50)) AS playerId, CAST(user_id AS NVARCHAR(50)) AS userId,
            first_name AS firstName, last_name AS lastName, position,
            recruiting_class AS recruitingClass, phone, email
     FROM @transferred FOR JSON PATH), ''[]'');
END;';
EXEC sp_executesql @sql;

PRINT 'Step 6 complete: Roster stored procedures applied.';

-- ─── 7. Apply Alumni stored procedures ──────────────────────

SET @sql = N'USE [' + @AlumniDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_CreateAlumniFromPlayer
  @UserId             UNIQUEIDENTIFIER,
  @SourcePlayerId     UNIQUEIDENTIFIER,
  @FirstName          NVARCHAR(100),
  @LastName           NVARCHAR(100),
  @GraduationYear     SMALLINT,
  @GraduationSemester NVARCHAR(10),
  @Position           NVARCHAR(10),
  @RecruitingClass    SMALLINT,
  @Phone              NVARCHAR(20)     = NULL,
  @PersonalEmail      NVARCHAR(255)    = NULL,
  @NewAlumniId        UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode          NVARCHAR(50)     OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  IF EXISTS (SELECT 1 FROM dbo.alumni WHERE source_player_id = @SourcePlayerId)
  BEGIN
    SELECT @NewAlumniId = id FROM dbo.alumni WHERE source_player_id = @SourcePlayerId;
    SET @ErrorCode = ''ALUMNI_ALREADY_EXISTS'';
    RETURN;
  END
  SET @NewAlumniId = NEWID();
  INSERT INTO dbo.alumni
    (id, user_id, source_player_id, first_name, last_name,
     graduation_year, graduation_semester, position, recruiting_class,
     phone, personal_email, status)
  VALUES
    (@NewAlumniId, @UserId, @SourcePlayerId, @FirstName, @LastName,
     @GraduationYear, @GraduationSemester, @Position, @RecruitingClass,
     @Phone, @PersonalEmail, ''active'');
END;';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @AlumniDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_GetAlumni
  @Search     NVARCHAR(255) = NULL,
  @Status     NVARCHAR(20)  = NULL,
  @IsDonor    BIT           = NULL,
  @GradYear   SMALLINT      = NULL,
  @Position   NVARCHAR(10)  = NULL,
  @Page       INT           = 1,
  @PageSize   INT           = 50,
  @TotalCount INT           OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @Offset     INT           = (@Page - 1) * @PageSize;
  DECLARE @SearchWild NVARCHAR(257) = ''%'' + ISNULL(@Search, '''') + ''%'';
  SELECT @TotalCount = COUNT(*)
  FROM dbo.alumni a
  WHERE (@Status   IS NULL OR a.status         = @Status)
    AND (@IsDonor  IS NULL OR a.is_donor        = @IsDonor)
    AND (@GradYear IS NULL OR a.graduation_year = @GradYear)
    AND (@Position IS NULL OR a.position        = @Position)
    AND (@Search   IS NULL OR a.first_name LIKE @SearchWild OR a.last_name LIKE @SearchWild
         OR a.current_employer LIKE @SearchWild OR a.personal_email LIKE @SearchWild);
  SELECT
    a.id, a.user_id AS userId, a.source_player_id AS sourcePlayerId,
    a.first_name AS firstName, a.last_name AS lastName,
    a.graduation_year AS graduationYear, a.graduation_semester AS graduationSemester,
    a.position, a.recruiting_class AS recruitingClass, a.status,
    a.personal_email AS personalEmail, a.phone,
    a.linkedin_url AS linkedInUrl, a.twitter_url AS twitterUrl,
    a.current_employer AS currentEmployer, a.current_job_title AS currentJobTitle,
    a.current_city AS currentCity, a.current_state AS currentState,
    a.is_donor AS isDonor, a.last_donation_date AS lastDonationDate,
    a.total_donations AS totalDonations, a.engagement_score AS engagementScore,
    a.notes, a.created_at AS createdAt, a.updated_at AS updatedAt
  FROM dbo.alumni a
  WHERE (@Status   IS NULL OR a.status         = @Status)
    AND (@IsDonor  IS NULL OR a.is_donor        = @IsDonor)
    AND (@GradYear IS NULL OR a.graduation_year = @GradYear)
    AND (@Position IS NULL OR a.position        = @Position)
    AND (@Search   IS NULL OR a.first_name LIKE @SearchWild OR a.last_name LIKE @SearchWild
         OR a.current_employer LIKE @SearchWild OR a.personal_email LIKE @SearchWild)
  ORDER BY a.last_name, a.first_name
  OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @AlumniDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_GetAlumniById
  @AlumniId  UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  IF NOT EXISTS (SELECT 1 FROM dbo.alumni WHERE id = @AlumniId)
  BEGIN SET @ErrorCode = ''ALUMNI_NOT_FOUND''; RETURN; END
  SELECT
    a.id, a.user_id AS userId, a.source_player_id AS sourcePlayerId,
    a.first_name AS firstName, a.last_name AS lastName,
    a.graduation_year AS graduationYear, a.graduation_semester AS graduationSemester,
    a.position, a.recruiting_class AS recruitingClass, a.status,
    a.personal_email AS personalEmail, a.phone,
    a.linkedin_url AS linkedInUrl, a.twitter_url AS twitterUrl,
    a.current_employer AS currentEmployer, a.current_job_title AS currentJobTitle,
    a.current_city AS currentCity, a.current_state AS currentState,
    a.is_donor AS isDonor, a.last_donation_date AS lastDonationDate,
    a.total_donations AS totalDonations, a.engagement_score AS engagementScore,
    a.notes, a.created_at AS createdAt, a.updated_at AS updatedAt
  FROM dbo.alumni a WHERE a.id = @AlumniId;
  SELECT il.id, il.channel, il.summary, il.outcome,
         il.follow_up_at AS followUpAt, il.logged_at AS loggedAt, il.logged_by AS loggedBy
  FROM dbo.interaction_log il
  WHERE il.alumni_id = @AlumniId
  ORDER BY il.logged_at DESC;
END;';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @AlumniDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_UpdateAlumni
  @AlumniId        UNIQUEIDENTIFIER,
  @Status          NVARCHAR(20)   = NULL,
  @PersonalEmail   NVARCHAR(255)  = NULL,
  @Phone           NVARCHAR(20)   = NULL,
  @LinkedInUrl     NVARCHAR(500)  = NULL,
  @TwitterUrl      NVARCHAR(100)  = NULL,
  @CurrentEmployer NVARCHAR(200)  = NULL,
  @CurrentJobTitle NVARCHAR(150)  = NULL,
  @CurrentCity     NVARCHAR(100)  = NULL,
  @CurrentState    NVARCHAR(50)   = NULL,
  @IsDonor         BIT            = NULL,
  @LastDonationDate DATE          = NULL,
  @TotalDonations  DECIMAL(10,2)  = NULL,
  @Notes           NVARCHAR(MAX)  = NULL,
  @UpdatedBy       UNIQUEIDENTIFIER,
  @ErrorCode       NVARCHAR(50)   OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  IF NOT EXISTS (SELECT 1 FROM dbo.alumni WHERE id = @AlumniId)
  BEGIN SET @ErrorCode = ''ALUMNI_NOT_FOUND''; RETURN; END
  IF @Status IS NOT NULL AND @Status NOT IN (''active'',''lostContact'',''deceased'',''doNotContact'')
  BEGIN SET @ErrorCode = ''INVALID_STATUS''; RETURN; END
  UPDATE dbo.alumni SET
    status            = COALESCE(@Status,           status),
    personal_email    = COALESCE(@PersonalEmail,    personal_email),
    phone             = COALESCE(@Phone,            phone),
    linkedin_url      = COALESCE(@LinkedInUrl,      linkedin_url),
    twitter_url       = COALESCE(@TwitterUrl,       twitter_url),
    current_employer  = COALESCE(@CurrentEmployer,  current_employer),
    current_job_title = COALESCE(@CurrentJobTitle,  current_job_title),
    current_city      = COALESCE(@CurrentCity,      current_city),
    current_state     = COALESCE(@CurrentState,     current_state),
    is_donor          = COALESCE(@IsDonor,          is_donor),
    last_donation_date= COALESCE(@LastDonationDate, last_donation_date),
    total_donations   = COALESCE(@TotalDonations,   total_donations),
    notes             = COALESCE(@Notes,            notes),
    updated_at        = SYSUTCDATETIME()
  WHERE id = @AlumniId;
  UPDATE dbo.alumni SET engagement_score = CAST(
    30
    + CASE WHEN personal_email    IS NOT NULL THEN 10 ELSE 0 END
    + CASE WHEN phone             IS NOT NULL THEN 8  ELSE 0 END
    + CASE WHEN linkedin_url      IS NOT NULL THEN 7  ELSE 0 END
    + CASE WHEN current_employer  IS NOT NULL THEN 10 ELSE 0 END
    + CASE WHEN current_job_title IS NOT NULL THEN 10 ELSE 0 END
    + CASE WHEN is_donor = 1 THEN 25 ELSE 0 END
  AS TINYINT)
  WHERE id = @AlumniId;
END;';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @AlumniDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_LogInteraction
  @AlumniId   UNIQUEIDENTIFIER,
  @LoggedBy   UNIQUEIDENTIFIER,
  @Channel    NVARCHAR(30),
  @Summary    NVARCHAR(MAX),
  @Outcome    NVARCHAR(50)  = NULL,
  @FollowUpAt DATETIME2     = NULL,
  @ErrorCode  NVARCHAR(50)  OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  IF NOT EXISTS (SELECT 1 FROM dbo.alumni WHERE id = @AlumniId)
  BEGIN SET @ErrorCode = ''ALUMNI_NOT_FOUND''; RETURN; END
  IF LEN(LTRIM(RTRIM(@Summary))) = 0
  BEGIN SET @ErrorCode = ''SUMMARY_REQUIRED''; RETURN; END
  INSERT INTO dbo.interaction_log (alumni_id, logged_by, channel, summary, outcome, follow_up_at)
  VALUES (@AlumniId, @LoggedBy, @Channel, @Summary, @Outcome, @FollowUpAt);
  UPDATE dbo.alumni SET
    engagement_score = CAST(CASE WHEN engagement_score + 2 > 100 THEN 100 ELSE engagement_score + 2 END AS TINYINT),
    updated_at = SYSUTCDATETIME()
  WHERE id = @AlumniId;
END;';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @AlumniDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_CreateCampaign
  @Name            NVARCHAR(200),
  @Description     NVARCHAR(MAX)  = NULL,
  @TargetAudience  NVARCHAR(20),
  @AudienceFilters NVARCHAR(MAX)  = NULL,
  @ScheduledAt     DATETIME2      = NULL,
  @CreatedBy       UNIQUEIDENTIFIER,
  @NewCampaignId   UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode       NVARCHAR(50)   OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;
  IF LEN(LTRIM(RTRIM(@Name))) = 0
  BEGIN SET @ErrorCode = ''NAME_REQUIRED''; RETURN; END
  IF @TargetAudience NOT IN (''all'',''byClass'',''byPosition'',''byStatus'',''custom'')
  BEGIN SET @ErrorCode = ''INVALID_TARGET_AUDIENCE''; RETURN; END
  IF @TargetAudience = ''custom'' AND (@AudienceFilters IS NULL OR LEN(@AudienceFilters) < 2)
  BEGIN SET @ErrorCode = ''CUSTOM_AUDIENCE_REQUIRES_FILTERS''; RETURN; END
  IF @ScheduledAt IS NOT NULL AND @ScheduledAt < SYSUTCDATETIME()
  BEGIN SET @ErrorCode = ''SCHEDULED_DATE_IN_PAST''; RETURN; END
  SET @NewCampaignId = NEWID();
  INSERT INTO dbo.outreach_campaigns (id, name, description, target_audience, audience_filters, scheduled_at, created_by)
  VALUES (@NewCampaignId, @Name, @Description, @TargetAudience, @AudienceFilters, @ScheduledAt, @CreatedBy);
END;';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @AlumniDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_GetCampaigns
AS
BEGIN
  SET NOCOUNT ON;
  SELECT
    c.id, c.name, c.description, c.target_audience AS targetAudience,
    c.status, c.scheduled_at AS scheduledAt, c.completed_at AS completedAt,
    c.created_by AS createdBy, c.created_at AS createdAt,
    COUNT(m.id) AS totalMessages,
    SUM(CASE WHEN m.status = ''sent''      THEN 1 ELSE 0 END) AS sentCount,
    SUM(CASE WHEN m.status = ''responded'' THEN 1 ELSE 0 END) AS respondedCount,
    SUM(CASE WHEN m.status = ''bounced''   THEN 1 ELSE 0 END) AS bouncedCount,
    CASE WHEN SUM(CASE WHEN m.status = ''sent'' THEN 1 ELSE 0 END) > 0
      THEN CAST(SUM(CASE WHEN m.status = ''responded'' THEN 1 ELSE 0 END) * 100.0 /
               SUM(CASE WHEN m.status = ''sent''      THEN 1 ELSE 0 END) AS DECIMAL(5,2))
      ELSE 0 END AS responseRatePct
  FROM dbo.outreach_campaigns c
  LEFT JOIN dbo.outreach_messages m ON m.campaign_id = c.id
  GROUP BY c.id, c.name, c.description, c.target_audience, c.status,
           c.scheduled_at, c.completed_at, c.created_by, c.created_at
  ORDER BY c.created_at DESC;
END;';
EXEC sp_executesql @sql;

SET @sql = N'USE [' + @AlumniDb + N'];
CREATE OR ALTER PROCEDURE dbo.sp_GetAlumniStats
AS
BEGIN
  SET NOCOUNT ON;
  SELECT
    COUNT(*) AS totalAlumni,
    SUM(CASE WHEN status = ''active''       THEN 1 ELSE 0 END) AS active,
    SUM(CASE WHEN status = ''lostContact''  THEN 1 ELSE 0 END) AS lostContact,
    SUM(CASE WHEN status = ''doNotContact'' THEN 1 ELSE 0 END) AS doNotContact,
    SUM(CASE WHEN is_donor = 1             THEN 1 ELSE 0 END) AS donors,
    ISNULL(SUM(total_donations), 0) AS totalDonations,
    ISNULL(CAST(AVG(CAST(engagement_score AS FLOAT)) AS DECIMAL(5,1)), 0) AS avgEngagement,
    MIN(graduation_year) AS earliestClass,
    MAX(graduation_year) AS latestClass,
    (SELECT graduation_year AS gradYear, COUNT(*) AS cnt
     FROM dbo.alumni
     GROUP BY graduation_year
     ORDER BY graduation_year DESC
     FOR JSON PATH) AS classCounts
  FROM dbo.alumni;
END;';
EXEC sp_executesql @sql;

PRINT 'Step 7 complete: Alumni stored procedures applied.';

-- ─── 8. Register client in CfbGlobal.dbo.teams ──────────────
DECLARE @ClientCode2   NVARCHAR(10)  = 'HSFC';
DECLARE @ClientName2   NVARCHAR(100) = 'Hillsborough High School Football';
DECLARE @ClientAbbr2   NVARCHAR(10)  = 'HSFC';
DECLARE @Sport2        NVARCHAR(50)  = 'football';
DECLARE @Level2        NVARCHAR(20)  = 'high_school';
DECLARE @DbServer2     NVARCHAR(200) = 'localhost\SQLEXPRESS';
DECLARE @RosterDb2     NVARCHAR(110) = @ClientCode2 + '_Roster';
DECLARE @AlumniDb2     NVARCHAR(110) = @ClientCode2 + '_Alumni';
DECLARE @NewTeamId2    UNIQUEIDENTIFIER;

IF NOT EXISTS (SELECT 1 FROM CfbGlobal.dbo.teams WHERE abbr = @ClientAbbr2)
BEGIN
  SET @NewTeamId2 = NEWID();
  INSERT INTO CfbGlobal.dbo.teams
    (id, name, abbr, sport, level, roster_db, alumni_db, db_server)
  VALUES
    (@NewTeamId2, @ClientName2, @ClientAbbr2, @Sport2, @Level2,
     @RosterDb2, @AlumniDb2, @DbServer2);
  PRINT 'Step 8 complete: Registered ' + @ClientAbbr2 + ' in teams table.';
END
ELSE
BEGIN
  SELECT @NewTeamId2 = id FROM CfbGlobal.dbo.teams WHERE abbr = @ClientAbbr2;
  PRINT 'Step 8: ' + @ClientAbbr2 + ' already registered — skipping insert.';
END

-- ─── 9. Success summary ──────────────────────────────────────
PRINT '';
PRINT '============================================================';
PRINT 'ONBOARDING COMPLETE';
PRINT '============================================================';
PRINT 'Client     : ' + @ClientName2 + ' (' + @ClientAbbr2 + ')';
PRINT 'Roster DB  : ' + @RosterDb2;
PRINT 'Alumni DB  : ' + @AlumniDb2;
PRINT 'Team ID    : ' + CAST(@NewTeamId2 AS NVARCHAR(50));
PRINT '';
PRINT 'NEXT STEPS:';
PRINT '1. Use the Team ID above to create the first admin user:';
PRINT '   INSERT INTO CfbGlobal.dbo.users (id, email, global_role, team_id, ...)';
PRINT '   VALUES (NEWID(), ''admin@client.com'', ''app_admin'', ''' + CAST(@NewTeamId2 AS NVARCHAR(50)) + ''', ...)';
PRINT '2. Send the admin an invite link via the /admin/invite API.';
PRINT '3. The admin logs in — their JWT will route to ' + @RosterDb2 + ' / ' + @AlumniDb2 + '.';
PRINT '============================================================';
GO
