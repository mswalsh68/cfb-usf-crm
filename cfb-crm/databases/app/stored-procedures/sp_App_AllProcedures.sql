-- ============================================================
-- APP DB — ALL STORED PROCEDURES
-- Run this file on each tenant AppDB (USFBullsApp, PlantPanthersApp, etc.)
-- All SPs live in dbo schema but reference roster.* and alumni.* tables.
-- ============================================================

-- ============================================================
-- ── ROSTER SPs ───────────────────────────────────────────────
-- ============================================================

-- ============================================================
-- sp_GetPlayers
-- ============================================================
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

  DECLARE @Offset     INT           = (@Page - 1) * @PageSize;
  DECLARE @SearchWild NVARCHAR(257) = '%' + ISNULL(@Search, '') + '%';
  DECLARE @ExactNum   NVARCHAR(10)  = ISNULL(@Search, '');

  SELECT @TotalCount = COUNT(*)
  FROM roster.players p
  WHERE (@Status          IS NULL OR p.status          = @Status)
    AND (@Position         IS NULL OR p.position        = @Position)
    AND (@AcademicYear     IS NULL OR p.academic_year   = @AcademicYear)
    AND (@RecruitingClass  IS NULL OR p.recruiting_class = @RecruitingClass)
    AND (@Search IS NULL OR p.first_name LIKE @SearchWild OR p.last_name LIKE @SearchWild
         OR CAST(p.jersey_number AS NVARCHAR) = @ExactNum);

  SELECT
    p.id,
    p.user_id               AS userId,
    p.jersey_number         AS jerseyNumber,
    p.first_name            AS firstName,
    p.last_name             AS lastName,
    p.position,
    p.academic_year         AS academicYear,
    p.status,
    p.height_inches         AS heightInches,
    p.weight_lbs            AS weightLbs,
    p.home_town             AS homeTown,
    p.home_state            AS homeState,
    p.high_school           AS highSchool,
    p.recruiting_class      AS recruitingClass,
    p.gpa,
    p.major,
    p.phone,
    p.email,
    p.instagram,
    p.twitter,
    p.snapchat,
    p.emergency_contact_name  AS emergencyContactName,
    p.emergency_contact_phone AS emergencyContactPhone,
    p.notes,
    p.graduated_at          AS graduatedAt,
    p.created_at            AS createdAt,
    p.updated_at            AS updatedAt
  FROM roster.players p
  WHERE (@Status          IS NULL OR p.status          = @Status)
    AND (@Position         IS NULL OR p.position        = @Position)
    AND (@AcademicYear     IS NULL OR p.academic_year   = @AcademicYear)
    AND (@RecruitingClass  IS NULL OR p.recruiting_class = @RecruitingClass)
    AND (@Search IS NULL OR p.first_name LIKE @SearchWild OR p.last_name LIKE @SearchWild
         OR CAST(p.jersey_number AS NVARCHAR) = @ExactNum)
  ORDER BY p.last_name, p.first_name
  OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- ============================================================
-- sp_GetPlayerById
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetPlayerById
  @PlayerId  UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM roster.players WHERE id = @PlayerId)
  BEGIN
    SET @ErrorCode = 'PLAYER_NOT_FOUND';
    RETURN;
  END

  SELECT
    p.id, p.user_id AS userId, p.jersey_number AS jerseyNumber,
    p.first_name AS firstName, p.last_name AS lastName,
    p.position, p.academic_year AS academicYear, p.status,
    p.height_inches AS heightInches, p.weight_lbs AS weightLbs,
    p.home_town AS homeTown, p.home_state AS homeState,
    p.high_school AS highSchool, p.recruiting_class AS recruitingClass,
    p.gpa, p.major, p.phone, p.email,
    p.instagram, p.twitter, p.snapchat,
    p.emergency_contact_name  AS emergencyContactName,
    p.emergency_contact_phone AS emergencyContactPhone,
    p.notes, p.graduated_at AS graduatedAt,
    p.created_at AS createdAt, p.updated_at AS updatedAt
  FROM roster.players p
  WHERE p.id = @PlayerId;

  SELECT
    ps.season_year  AS seasonYear,
    ps.games_played AS gamesPlayed,
    ps.stats_json   AS statsJson,
    ps.updated_at   AS updatedAt
  FROM roster.player_stats ps
  WHERE ps.player_id = @PlayerId
  ORDER BY ps.season_year DESC;
END;
GO

-- ============================================================
-- sp_CreatePlayer
-- ============================================================
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

  IF @AcademicYear NOT IN ('freshman','sophomore','junior','senior','graduate')
  BEGIN SET @ErrorCode = 'INVALID_ACADEMIC_YEAR'; RETURN; END

  IF @RecruitingClass < 2000 OR @RecruitingClass > 2100
  BEGIN SET @ErrorCode = 'INVALID_RECRUITING_CLASS'; RETURN; END

  IF EXISTS (SELECT 1 FROM roster.players WHERE user_id = @UserId)
  BEGIN SET @ErrorCode = 'PLAYER_ALREADY_EXISTS_FOR_USER'; RETURN; END

  IF @JerseyNumber IS NOT NULL AND EXISTS (
    SELECT 1 FROM roster.players WHERE jersey_number = @JerseyNumber AND status = 'active'
  )
  BEGIN SET @ErrorCode = 'JERSEY_NUMBER_IN_USE'; RETURN; END

  SET @NewPlayerId = NEWID();

  INSERT INTO roster.players (
    id, user_id, jersey_number, first_name, last_name, position, academic_year,
    recruiting_class, height_inches, weight_lbs, home_town, home_state, high_school,
    gpa, major, phone, email, instagram, twitter, snapchat,
    emergency_contact_name, emergency_contact_phone, notes
  )
  VALUES (
    @NewPlayerId, @UserId, @JerseyNumber, @FirstName, @LastName, @Position, @AcademicYear,
    @RecruitingClass, @HeightInches, @WeightLbs, @HomeTown, @HomeState, @HighSchool,
    @Gpa, @Major, @Phone, @Email, @Instagram, @Twitter, @Snapchat,
    @EmergencyContactName, @EmergencyContactPhone, @Notes
  );
END;
GO

-- ============================================================
-- sp_UpdatePlayer
-- ============================================================
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

  IF NOT EXISTS (SELECT 1 FROM roster.players WHERE id = @PlayerId)
  BEGIN SET @ErrorCode = 'PLAYER_NOT_FOUND'; RETURN; END

  IF @Status = 'graduated'
  BEGIN SET @ErrorCode = 'USE_SP_TRANSFER_TO_ALUMNI'; RETURN; END

  IF @Status IS NOT NULL AND @Status NOT IN ('active','injured','suspended','transferred','walkOn')
  BEGIN SET @ErrorCode = 'INVALID_STATUS'; RETURN; END

  IF @JerseyNumber IS NOT NULL AND EXISTS (
    SELECT 1 FROM roster.players
    WHERE jersey_number = @JerseyNumber AND status = 'active' AND id <> @PlayerId
  )
  BEGIN SET @ErrorCode = 'JERSEY_NUMBER_IN_USE'; RETURN; END

  UPDATE roster.players SET
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
END;
GO

-- ============================================================
-- sp_UpsertPlayerStats
-- ============================================================
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

  IF NOT EXISTS (SELECT 1 FROM roster.players WHERE id = @PlayerId)
  BEGIN SET @ErrorCode = 'PLAYER_NOT_FOUND'; RETURN; END

  IF EXISTS (SELECT 1 FROM roster.player_stats WHERE player_id = @PlayerId AND season_year = @SeasonYear)
  BEGIN
    UPDATE roster.player_stats SET
      games_played = COALESCE(@GamesPlayed, games_played),
      stats_json   = COALESCE(@StatsJson,   stats_json),
      updated_at   = SYSUTCDATETIME()
    WHERE player_id = @PlayerId AND season_year = @SeasonYear;
  END
  ELSE
  BEGIN
    INSERT INTO roster.player_stats (player_id, season_year, games_played, stats_json)
    VALUES (@PlayerId, @SeasonYear, @GamesPlayed, @StatsJson);
  END
END;
GO

-- ============================================================
-- sp_TransferToAlumni
-- Atomically marks players as graduated in roster.players and
-- creates alumni records in alumni.alumni — all within the same
-- AppDB. No cross-service HTTP calls needed.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_TransferToAlumni
  @PlayerIds        NVARCHAR(MAX),   -- JSON array: ["guid","guid",...]
  @TransferReason   NVARCHAR(50),
  @TransferYear     SMALLINT,
  @TransferSemester NVARCHAR(10),
  @Notes            NVARCHAR(MAX)    = NULL,
  @TriggeredBy      NVARCHAR(100),
  @TransactionId    UNIQUEIDENTIFIER OUTPUT,
  @SuccessCount     INT              OUTPUT,
  @FailureJson      NVARCHAR(MAX)    OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  SET @TransactionId = NEWID();
  SET @SuccessCount  = 0;
  SET @FailureJson   = '[]';

  DECLARE @failures   TABLE (player_id NVARCHAR(100), reason NVARCHAR(500));
  DECLARE @playerIds2 TABLE (player_id UNIQUEIDENTIFIER);
  DECLARE @currentId  UNIQUEIDENTIFIER;

  INSERT INTO @playerIds2 (player_id)
  SELECT TRY_CAST([value] AS UNIQUEIDENTIFIER)
  FROM OPENJSON(@PlayerIds)
  WHERE TRY_CAST([value] AS UNIQUEIDENTIFIER) IS NOT NULL;

  DECLARE player_cursor CURSOR FOR
    SELECT player_id FROM @playerIds2;

  OPEN player_cursor;
  FETCH NEXT FROM player_cursor INTO @currentId;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      BEGIN TRANSACTION;

        DECLARE @firstName    NVARCHAR(100);
        DECLARE @lastName     NVARCHAR(100);
        DECLARE @position     NVARCHAR(10);
        DECLARE @recruitClass SMALLINT;
        DECLARE @userId       UNIQUEIDENTIFIER;
        DECLARE @curStatus    NVARCHAR(20);
        DECLARE @phone        NVARCHAR(20);
        DECLARE @email        NVARCHAR(255);

        SELECT
          @firstName    = first_name,
          @lastName     = last_name,
          @position     = position,
          @recruitClass = recruiting_class,
          @userId       = user_id,
          @curStatus    = status,
          @phone        = phone,
          @email        = email
        FROM roster.players
        WHERE id = @currentId;

        IF @userId IS NULL
        BEGIN
          ROLLBACK TRANSACTION;
          INSERT INTO @failures VALUES (CAST(@currentId AS NVARCHAR(100)), 'Player not found');
          FETCH NEXT FROM player_cursor INTO @currentId;
          CONTINUE;
        END

        IF @curStatus = 'graduated'
        BEGIN
          ROLLBACK TRANSACTION;
          INSERT INTO @failures VALUES (CAST(@currentId AS NVARCHAR(100)), 'Player already graduated');
          FETCH NEXT FROM player_cursor INTO @currentId;
          CONTINUE;
        END

        -- 1. Mark player graduated
        UPDATE roster.players
        SET status       = 'graduated',
            graduated_at = SYSUTCDATETIME(),
            notes        = ISNULL(notes + CHAR(10), '') + 'Transfer reason: ' + @TransferReason,
            updated_at   = SYSUTCDATETIME()
        WHERE id = @currentId;

        -- 2. Log the transfer
        INSERT INTO dbo.graduation_log
          (transaction_id, player_id, graduation_year, graduation_semester, triggered_by, status, notes)
        VALUES
          (@TransactionId, @currentId, @TransferYear, @TransferSemester,
           TRY_CAST(@TriggeredBy AS UNIQUEIDENTIFIER), 'success', @Notes);

        -- 3. Create alumni record directly in the same DB (idempotent)
        IF NOT EXISTS (SELECT 1 FROM alumni.alumni WHERE source_player_id = @currentId)
        BEGIN
          INSERT INTO alumni.alumni
            (user_id, source_player_id, first_name, last_name,
             graduation_year, graduation_semester, position, recruiting_class,
             phone, personal_email, status)
          VALUES
            (@userId, @currentId, @firstName, @lastName,
             @TransferYear, @TransferSemester, @position, @recruitClass,
             @phone, @email, 'active');
        END

        SET @SuccessCount = @SuccessCount + 1;

      COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
      IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
      INSERT INTO @failures VALUES (CAST(@currentId AS NVARCHAR(100)), ERROR_MESSAGE());

      -- Log failure outside the rolled-back transaction
      INSERT INTO dbo.graduation_log
        (transaction_id, player_id, graduation_year, graduation_semester, triggered_by, status, notes)
      VALUES
        (@TransactionId, @currentId, @TransferYear, @TransferSemester,
         TRY_CAST(@TriggeredBy AS UNIQUEIDENTIFIER), 'failed', ERROR_MESSAGE());
    END CATCH;

    FETCH NEXT FROM player_cursor INTO @currentId;
  END

  CLOSE player_cursor;
  DEALLOCATE player_cursor;

  SELECT @FailureJson = ISNULL(
    (SELECT player_id AS playerId, reason FROM @failures FOR JSON PATH), '[]');
END;
GO

-- ============================================================
-- sp_BulkCreatePlayers
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_BulkCreatePlayers
  @PlayersJson  NVARCHAR(MAX),
  @CreatedBy    UNIQUEIDENTIFIER,
  @SuccessCount INT OUTPUT,
  @SkippedCount INT OUTPUT,
  @ErrorJson    NVARCHAR(MAX) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @SuccessCount = 0;
  SET @SkippedCount = 0;
  SET @ErrorJson    = '[]';

  DECLARE @errors TABLE (row_num INT, reason NVARCHAR(500));

  DECLARE @players TABLE (
    row_num              INT,
    first_name           NVARCHAR(100),
    last_name            NVARCHAR(100),
    jersey_number        TINYINT,
    position             NVARCHAR(10),
    academic_year        NVARCHAR(20),
    recruiting_class     SMALLINT,
    height_inches        TINYINT,
    weight_lbs           SMALLINT,
    home_town            NVARCHAR(100),
    home_state           NVARCHAR(50),
    high_school          NVARCHAR(150),
    gpa                  DECIMAL(3,2),
    major                NVARCHAR(100),
    phone                NVARCHAR(20),
    emergency_contact_name  NVARCHAR(150),
    emergency_contact_phone NVARCHAR(20),
    notes                NVARCHAR(MAX)
  );

  INSERT INTO @players (
    row_num, first_name, last_name, jersey_number, position, academic_year,
    recruiting_class, height_inches, weight_lbs, home_town, home_state,
    high_school, gpa, major, phone, emergency_contact_name, emergency_contact_phone, notes
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    JSON_VALUE(value, '$.firstName'),
    JSON_VALUE(value, '$.lastName'),
    TRY_CAST(JSON_VALUE(value, '$.jerseyNumber')    AS TINYINT),
    JSON_VALUE(value, '$.position'),
    JSON_VALUE(value, '$.academicYear'),
    TRY_CAST(JSON_VALUE(value, '$.recruitingClass') AS SMALLINT),
    TRY_CAST(JSON_VALUE(value, '$.heightInches')    AS TINYINT),
    TRY_CAST(JSON_VALUE(value, '$.weightLbs')       AS SMALLINT),
    JSON_VALUE(value, '$.homeTown'),
    JSON_VALUE(value, '$.homeState'),
    JSON_VALUE(value, '$.highSchool'),
    TRY_CAST(JSON_VALUE(value, '$.gpa')             AS DECIMAL(3,2)),
    JSON_VALUE(value, '$.major'),
    JSON_VALUE(value, '$.phone'),
    JSON_VALUE(value, '$.emergencyContactName'),
    JSON_VALUE(value, '$.emergencyContactPhone'),
    JSON_VALUE(value, '$.notes')
  FROM OPENJSON(@PlayersJson);

  DECLARE @rowNum  INT;
  DECLARE @fn      NVARCHAR(100); DECLARE @ln    NVARCHAR(100);
  DECLARE @jersey  TINYINT;       DECLARE @pos   NVARCHAR(10);
  DECLARE @acYear  NVARCHAR(20);  DECLARE @rc    SMALLINT;
  DECLARE @hi      TINYINT;       DECLARE @wt    SMALLINT;
  DECLARE @town    NVARCHAR(100); DECLARE @state NVARCHAR(50);
  DECLARE @hs      NVARCHAR(150); DECLARE @gpa   DECIMAL(3,2);
  DECLARE @major   NVARCHAR(100); DECLARE @phone NVARCHAR(20);
  DECLARE @ecName  NVARCHAR(150); DECLARE @ecPh  NVARCHAR(20);
  DECLARE @notes   NVARCHAR(MAX);

  DECLARE pc CURSOR FOR
    SELECT row_num, first_name, last_name, jersey_number, position, academic_year,
           recruiting_class, height_inches, weight_lbs, home_town, home_state,
           high_school, gpa, major, phone, emergency_contact_name, emergency_contact_phone, notes
    FROM @players;

  OPEN pc;
  FETCH NEXT FROM pc INTO @rowNum, @fn, @ln, @jersey, @pos, @acYear, @rc, @hi, @wt, @town, @state, @hs, @gpa, @major, @phone, @ecName, @ecPh, @notes;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      IF @fn IS NULL OR LEN(LTRIM(RTRIM(@fn))) = 0
      BEGIN INSERT INTO @errors VALUES (@rowNum, 'First name required'); SET @SkippedCount += 1; GOTO NextPlayer; END

      IF @ln IS NULL OR LEN(LTRIM(RTRIM(@ln))) = 0
      BEGIN INSERT INTO @errors VALUES (@rowNum, 'Last name required'); SET @SkippedCount += 1; GOTO NextPlayer; END

      IF @pos NOT IN ('QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH')
      BEGIN INSERT INTO @errors VALUES (@rowNum, 'Invalid position: ' + ISNULL(@pos, 'NULL')); SET @SkippedCount += 1; GOTO NextPlayer; END

      IF @rc IS NULL OR @rc < 2000 OR @rc > 2100
      BEGIN INSERT INTO @errors VALUES (@rowNum, 'Invalid recruiting class year'); SET @SkippedCount += 1; GOTO NextPlayer; END

      IF @jersey IS NOT NULL AND EXISTS (
        SELECT 1 FROM roster.players WHERE jersey_number = @jersey AND status = 'active'
      )
      BEGIN INSERT INTO @errors VALUES (@rowNum, 'Jersey #' + CAST(@jersey AS NVARCHAR) + ' already in use'); SET @SkippedCount += 1; GOTO NextPlayer; END

      INSERT INTO roster.players (
        user_id, first_name, last_name, jersey_number, position, academic_year,
        recruiting_class, height_inches, weight_lbs, home_town, home_state,
        high_school, gpa, major, phone, emergency_contact_name, emergency_contact_phone, notes
      )
      VALUES (
        NEWID(), @fn, @ln, @jersey, @pos, @acYear,
        @rc, @hi, @wt, @town, @state,
        @hs, @gpa, @major, @phone, @ecName, @ecPh, @notes
      );

      SET @SuccessCount += 1;

    END TRY
    BEGIN CATCH
      INSERT INTO @errors VALUES (@rowNum, ERROR_MESSAGE());
      SET @SkippedCount += 1;
    END CATCH;

    NextPlayer:
    FETCH NEXT FROM pc INTO @rowNum, @fn, @ln, @jersey, @pos, @acYear, @rc, @hi, @wt, @town, @state, @hs, @gpa, @major, @phone, @ecName, @ecPh, @notes;
  END

  CLOSE pc; DEALLOCATE pc;

  SELECT @ErrorJson = ISNULL(
    (SELECT row_num AS rowNum, reason FROM @errors FOR JSON PATH), '[]');
END;
GO

-- ============================================================
-- ── ALUMNI SPs ────────────────────────────────────────────────
-- ============================================================

-- ============================================================
-- sp_CreateAlumniFromPlayer
-- ============================================================
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

  IF EXISTS (SELECT 1 FROM alumni.alumni WHERE source_player_id = @SourcePlayerId)
  BEGIN
    SELECT @NewAlumniId = id FROM alumni.alumni WHERE source_player_id = @SourcePlayerId;
    SET @ErrorCode = 'ALUMNI_ALREADY_EXISTS';
    RETURN;
  END

  SET @NewAlumniId = NEWID();

  INSERT INTO alumni.alumni
    (id, user_id, source_player_id, first_name, last_name,
     graduation_year, graduation_semester, position, recruiting_class,
     phone, personal_email, status)
  VALUES
    (@NewAlumniId, @UserId, @SourcePlayerId, @FirstName, @LastName,
     @GraduationYear, @GraduationSemester, @Position, @RecruitingClass,
     @Phone, @PersonalEmail, 'active');
END;
GO

-- ============================================================
-- sp_GetAlumni
-- ============================================================
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
  DECLARE @SearchWild NVARCHAR(257) = '%' + ISNULL(@Search, '') + '%';

  SELECT @TotalCount = COUNT(*)
  FROM alumni.alumni a
  WHERE (@Status   IS NULL OR a.status          = @Status)
    AND (@IsDonor  IS NULL OR a.is_donor         = @IsDonor)
    AND (@GradYear IS NULL OR a.graduation_year  = @GradYear)
    AND (@Position IS NULL OR a.position         = @Position)
    AND (@Search   IS NULL OR a.first_name LIKE @SearchWild OR a.last_name LIKE @SearchWild
         OR a.current_employer LIKE @SearchWild OR a.current_city LIKE @SearchWild
         OR a.personal_email LIKE @SearchWild);

  SELECT
    a.id,
    a.user_id              AS userId,
    a.source_player_id     AS sourcePlayerId,
    a.first_name           AS firstName,
    a.last_name            AS lastName,
    a.graduation_year      AS graduationYear,
    a.graduation_semester  AS graduationSemester,
    a.position,
    a.recruiting_class     AS recruitingClass,
    a.status,
    a.personal_email       AS personalEmail,
    a.phone,
    a.linkedin_url         AS linkedInUrl,
    a.twitter_url          AS twitterUrl,
    a.current_employer     AS currentEmployer,
    a.current_job_title    AS currentJobTitle,
    a.current_city         AS currentCity,
    a.current_state        AS currentState,
    a.is_donor             AS isDonor,
    a.last_donation_date   AS lastDonationDate,
    a.total_donations      AS totalDonations,
    a.engagement_score     AS engagementScore,
    a.notes,
    a.created_at           AS createdAt,
    a.updated_at           AS updatedAt
  FROM alumni.alumni a
  WHERE (@Status   IS NULL OR a.status          = @Status)
    AND (@IsDonor  IS NULL OR a.is_donor         = @IsDonor)
    AND (@GradYear IS NULL OR a.graduation_year  = @GradYear)
    AND (@Position IS NULL OR a.position         = @Position)
    AND (@Search   IS NULL OR a.first_name LIKE @SearchWild OR a.last_name LIKE @SearchWild
         OR a.current_employer LIKE @SearchWild OR a.current_city LIKE @SearchWild
         OR a.personal_email LIKE @SearchWild)
  ORDER BY a.last_name, a.first_name
  OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- ============================================================
-- sp_GetAlumniById
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetAlumniById
  @AlumniId  UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM alumni.alumni WHERE id = @AlumniId)
  BEGIN SET @ErrorCode = 'ALUMNI_NOT_FOUND'; RETURN; END

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
  FROM alumni.alumni a
  WHERE a.id = @AlumniId;

  SELECT
    il.id, il.channel, il.summary, il.outcome,
    il.follow_up_at AS followUpAt,
    il.logged_at    AS loggedAt,
    il.logged_by    AS loggedBy
  FROM alumni.interaction_log il
  WHERE il.alumni_id = @AlumniId
  ORDER BY il.logged_at DESC;
END;
GO

-- ============================================================
-- sp_UpdateAlumni
-- ============================================================
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

  IF NOT EXISTS (SELECT 1 FROM alumni.alumni WHERE id = @AlumniId)
  BEGIN SET @ErrorCode = 'ALUMNI_NOT_FOUND'; RETURN; END

  IF @Status IS NOT NULL AND @Status NOT IN ('active','lostContact','deceased','doNotContact')
  BEGIN SET @ErrorCode = 'INVALID_STATUS'; RETURN; END

  UPDATE alumni.alumni SET
    status             = COALESCE(@Status,           status),
    personal_email     = COALESCE(@PersonalEmail,    personal_email),
    phone              = COALESCE(@Phone,            phone),
    linkedin_url       = COALESCE(@LinkedInUrl,      linkedin_url),
    twitter_url        = COALESCE(@TwitterUrl,       twitter_url),
    current_employer   = COALESCE(@CurrentEmployer,  current_employer),
    current_job_title  = COALESCE(@CurrentJobTitle,  current_job_title),
    current_city       = COALESCE(@CurrentCity,      current_city),
    current_state      = COALESCE(@CurrentState,     current_state),
    is_donor           = COALESCE(@IsDonor,          is_donor),
    last_donation_date = COALESCE(@LastDonationDate, last_donation_date),
    total_donations    = COALESCE(@TotalDonations,   total_donations),
    notes              = COALESCE(@Notes,            notes),
    updated_at         = SYSUTCDATETIME()
  WHERE id = @AlumniId;

  -- Recalculate engagement score
  UPDATE alumni.alumni SET
    engagement_score = CAST(
      30
      + CASE WHEN personal_email    IS NOT NULL THEN 10 ELSE 0 END
      + CASE WHEN phone             IS NOT NULL THEN 8  ELSE 0 END
      + CASE WHEN linkedin_url      IS NOT NULL THEN 7  ELSE 0 END
      + CASE WHEN current_employer  IS NOT NULL THEN 10 ELSE 0 END
      + CASE WHEN current_job_title IS NOT NULL THEN 10 ELSE 0 END
      + CASE WHEN is_donor = 1 THEN 25 ELSE 0 END
    AS TINYINT)
  WHERE id = @AlumniId;
END;
GO

-- ============================================================
-- sp_LogInteraction
-- ============================================================
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

  IF NOT EXISTS (SELECT 1 FROM alumni.alumni WHERE id = @AlumniId)
  BEGIN SET @ErrorCode = 'ALUMNI_NOT_FOUND'; RETURN; END

  IF LEN(LTRIM(RTRIM(@Summary))) = 0
  BEGIN SET @ErrorCode = 'SUMMARY_REQUIRED'; RETURN; END

  INSERT INTO alumni.interaction_log
    (alumni_id, logged_by, channel, summary, outcome, follow_up_at)
  VALUES
    (@AlumniId, @LoggedBy, @Channel, @Summary, @Outcome, @FollowUpAt);

  UPDATE alumni.alumni
  SET engagement_score = CAST(CASE
      WHEN engagement_score + 2 > 100 THEN 100
      ELSE engagement_score + 2
    END AS TINYINT),
    updated_at = SYSUTCDATETIME()
  WHERE id = @AlumniId;
END;
GO

-- ============================================================
-- sp_CreateCampaign
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateCampaign
  @Name            NVARCHAR(200),
  @Description     NVARCHAR(MAX)    = NULL,
  @TargetAudience  NVARCHAR(20),
  @AudienceFilters NVARCHAR(MAX)    = NULL,
  @ScheduledAt     DATETIME2        = NULL,
  @CreatedBy       UNIQUEIDENTIFIER,
  @NewCampaignId   UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode       NVARCHAR(50)     OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF LEN(LTRIM(RTRIM(@Name))) = 0
  BEGIN SET @ErrorCode = 'NAME_REQUIRED'; RETURN; END

  IF @TargetAudience NOT IN ('all','byClass','byPosition','byStatus','custom')
  BEGIN SET @ErrorCode = 'INVALID_TARGET_AUDIENCE'; RETURN; END

  IF @TargetAudience = 'custom' AND (@AudienceFilters IS NULL OR LEN(@AudienceFilters) < 2)
  BEGIN SET @ErrorCode = 'CUSTOM_AUDIENCE_REQUIRES_FILTERS'; RETURN; END

  IF @ScheduledAt IS NOT NULL AND @ScheduledAt < SYSUTCDATETIME()
  BEGIN SET @ErrorCode = 'SCHEDULED_DATE_IN_PAST'; RETURN; END

  SET @NewCampaignId = NEWID();

  INSERT INTO alumni.outreach_campaigns
    (id, name, description, target_audience, audience_filters, scheduled_at, created_by)
  VALUES
    (@NewCampaignId, @Name, @Description, @TargetAudience, @AudienceFilters, @ScheduledAt, @CreatedBy);
END;
GO

-- ============================================================
-- sp_GetCampaigns
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetCampaigns
AS
BEGIN
  SET NOCOUNT ON;

  SELECT
    c.id, c.name, c.description,
    c.target_audience  AS targetAudience,
    c.status,
    c.scheduled_at     AS scheduledAt,
    c.completed_at     AS completedAt,
    c.created_by       AS createdBy,
    c.created_at       AS createdAt,
    COUNT(m.id)                                                      AS totalMessages,
    SUM(CASE WHEN m.status = 'sent'      THEN 1 ELSE 0 END)         AS sentCount,
    SUM(CASE WHEN m.status = 'responded' THEN 1 ELSE 0 END)         AS respondedCount,
    SUM(CASE WHEN m.status = 'bounced'   THEN 1 ELSE 0 END)         AS bouncedCount,
    CASE
      WHEN SUM(CASE WHEN m.status = 'sent' THEN 1 ELSE 0 END) > 0
      THEN CAST(
        SUM(CASE WHEN m.status = 'responded' THEN 1 ELSE 0 END) * 100.0 /
        SUM(CASE WHEN m.status = 'sent'      THEN 1 ELSE 0 END)
        AS DECIMAL(5,2))
      ELSE 0
    END AS responseRatePct
  FROM alumni.outreach_campaigns c
  LEFT JOIN alumni.outreach_messages m ON m.campaign_id = c.id
  GROUP BY c.id, c.name, c.description, c.target_audience, c.status,
           c.scheduled_at, c.completed_at, c.created_by, c.created_at
  ORDER BY c.created_at DESC;
END;
GO

-- ============================================================
-- sp_GetAlumniStats
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetAlumniStats
AS
BEGIN
  SET NOCOUNT ON;

  SELECT
    COUNT(*)                                                     AS totalAlumni,
    SUM(CASE WHEN status = 'active'       THEN 1 ELSE 0 END)    AS active,
    SUM(CASE WHEN status = 'lostContact'  THEN 1 ELSE 0 END)    AS lostContact,
    SUM(CASE WHEN status = 'doNotContact' THEN 1 ELSE 0 END)    AS doNotContact,
    SUM(CASE WHEN is_donor = 1            THEN 1 ELSE 0 END)    AS donors,
    ISNULL(SUM(total_donations), 0)                             AS totalDonations,
    ISNULL(CAST(AVG(CAST(engagement_score AS FLOAT)) AS DECIMAL(5,1)), 0) AS avgEngagement,
    MIN(graduation_year)                                         AS earliestClass,
    MAX(graduation_year)                                         AS latestClass,
    (
      SELECT graduation_year AS gradYear, COUNT(*) AS cnt
      FROM alumni.alumni
      GROUP BY graduation_year
      ORDER BY graduation_year DESC
      FOR JSON PATH
    ) AS classCounts
  FROM alumni.alumni;
END;
GO

-- ============================================================
-- sp_ResolveAudienceForCampaign
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ResolveAudienceForCampaign
  @CampaignId UNIQUEIDENTIFIER,
  @ErrorCode  NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  DECLARE @Audience    NVARCHAR(20);
  DECLARE @FiltersJson NVARCHAR(MAX);

  SELECT @Audience = target_audience, @FiltersJson = audience_filters
  FROM alumni.outreach_campaigns
  WHERE id = @CampaignId;

  IF @Audience IS NULL
  BEGIN SET @ErrorCode = 'CAMPAIGN_NOT_FOUND'; RETURN; END

  DECLARE @FilterGradYear SMALLINT     = TRY_CAST(JSON_VALUE(@FiltersJson, '$.gradYear') AS SMALLINT);
  DECLARE @FilterPosition NVARCHAR(10) = JSON_VALUE(@FiltersJson, '$.position');
  DECLARE @FilterStatus   NVARCHAR(20) = JSON_VALUE(@FiltersJson, '$.status');

  SELECT a.id AS alumniId, a.first_name AS firstName, a.last_name AS lastName,
         a.personal_email AS personalEmail, a.phone
  FROM alumni.alumni a
  WHERE a.status <> 'doNotContact'
    AND (
      @Audience = 'all'
      OR (@Audience = 'byClass'    AND a.graduation_year = @FilterGradYear)
      OR (@Audience = 'byPosition' AND a.position        = @FilterPosition)
      OR (@Audience = 'byStatus'   AND a.status          = @FilterStatus)
      OR (@Audience = 'custom'
          AND (@FilterGradYear IS NULL OR a.graduation_year = @FilterGradYear)
          AND (@FilterPosition IS NULL OR a.position        = @FilterPosition)
          AND (@FilterStatus   IS NULL OR a.status          = @FilterStatus))
    );
END;
GO

-- ============================================================
-- sp_BulkCreateAlumni
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_BulkCreateAlumni
  @AlumniJson   NVARCHAR(MAX),
  @CreatedBy    UNIQUEIDENTIFIER,
  @SuccessCount INT OUTPUT,
  @SkippedCount INT OUTPUT,
  @ErrorJson    NVARCHAR(MAX) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @SuccessCount = 0;
  SET @SkippedCount = 0;
  SET @ErrorJson    = '[]';

  DECLARE @errors TABLE (row_num INT, reason NVARCHAR(500));

  DECLARE @alumni TABLE (
    row_num             INT,
    first_name          NVARCHAR(100),
    last_name           NVARCHAR(100),
    graduation_year     SMALLINT,
    graduation_semester NVARCHAR(10),
    position            NVARCHAR(10),
    recruiting_class    SMALLINT,
    personal_email      NVARCHAR(255),
    phone               NVARCHAR(20),
    linkedin_url        NVARCHAR(500),
    current_employer    NVARCHAR(200),
    current_job_title   NVARCHAR(150),
    current_city        NVARCHAR(100),
    current_state       NVARCHAR(50),
    is_donor            BIT,
    notes               NVARCHAR(MAX)
  );

  INSERT INTO @alumni (
    row_num, first_name, last_name, graduation_year, graduation_semester,
    position, recruiting_class, personal_email, phone, linkedin_url,
    current_employer, current_job_title, current_city, current_state,
    is_donor, notes
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    JSON_VALUE(value, '$.firstName'),
    JSON_VALUE(value, '$.lastName'),
    TRY_CAST(JSON_VALUE(value, '$.graduationYear')   AS SMALLINT),
    ISNULL(JSON_VALUE(value, '$.graduationSemester'), 'spring'),
    JSON_VALUE(value, '$.position'),
    TRY_CAST(JSON_VALUE(value, '$.recruitingClass')  AS SMALLINT),
    JSON_VALUE(value, '$.personalEmail'),
    JSON_VALUE(value, '$.phone'),
    JSON_VALUE(value, '$.linkedInUrl'),
    JSON_VALUE(value, '$.currentEmployer'),
    JSON_VALUE(value, '$.currentJobTitle'),
    JSON_VALUE(value, '$.currentCity'),
    JSON_VALUE(value, '$.currentState'),
    CASE WHEN LOWER(JSON_VALUE(value, '$.isDonor')) IN ('yes','true','1') THEN 1 ELSE 0 END,
    JSON_VALUE(value, '$.notes')
  FROM OPENJSON(@AlumniJson);

  DECLARE @rowNum   INT;
  DECLARE @fn       NVARCHAR(100); DECLARE @ln       NVARCHAR(100);
  DECLARE @gradYear SMALLINT;      DECLARE @sem      NVARCHAR(10);
  DECLARE @pos      NVARCHAR(10);  DECLARE @rc       SMALLINT;
  DECLARE @email    NVARCHAR(255); DECLARE @phone    NVARCHAR(20);
  DECLARE @linkedin NVARCHAR(500); DECLARE @employer NVARCHAR(200);
  DECLARE @jobTitle NVARCHAR(150); DECLARE @city     NVARCHAR(100);
  DECLARE @state    NVARCHAR(50);  DECLARE @isDonor  BIT;
  DECLARE @notes    NVARCHAR(MAX);

  DECLARE ac CURSOR FOR
    SELECT row_num, first_name, last_name, graduation_year, graduation_semester,
           position, recruiting_class, personal_email, phone, linkedin_url,
           current_employer, current_job_title, current_city, current_state,
           is_donor, notes
    FROM @alumni;

  OPEN ac;
  FETCH NEXT FROM ac INTO @rowNum, @fn, @ln, @gradYear, @sem, @pos, @rc, @email, @phone, @linkedin, @employer, @jobTitle, @city, @state, @isDonor, @notes;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      IF @fn IS NULL OR LEN(LTRIM(RTRIM(@fn))) = 0
      BEGIN INSERT INTO @errors VALUES (@rowNum, 'First name required'); SET @SkippedCount += 1; GOTO NextAlumni; END

      IF @ln IS NULL OR LEN(LTRIM(RTRIM(@ln))) = 0
      BEGIN INSERT INTO @errors VALUES (@rowNum, 'Last name required'); SET @SkippedCount += 1; GOTO NextAlumni; END

      IF @gradYear IS NULL OR @gradYear < 1950 OR @gradYear > 2100
      BEGIN INSERT INTO @errors VALUES (@rowNum, 'Invalid graduation year'); SET @SkippedCount += 1; GOTO NextAlumni; END

      IF @pos NOT IN ('QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH')
      BEGIN INSERT INTO @errors VALUES (@rowNum, 'Invalid position: ' + ISNULL(@pos, 'NULL')); SET @SkippedCount += 1; GOTO NextAlumni; END

      INSERT INTO alumni.alumni (
        user_id, source_player_id, first_name, last_name,
        graduation_year, graduation_semester, position, recruiting_class,
        personal_email, phone, linkedin_url,
        current_employer, current_job_title, current_city, current_state,
        is_donor, status, notes
      )
      VALUES (
        NEWID(), NEWID(), @fn, @ln,
        @gradYear, @sem, @pos, ISNULL(@rc, @gradYear - 4),
        @email, @phone, @linkedin,
        @employer, @jobTitle, @city, @state,
        ISNULL(@isDonor, 0), 'active', @notes
      );

      SET @SuccessCount += 1;

    END TRY
    BEGIN CATCH
      INSERT INTO @errors VALUES (@rowNum, ERROR_MESSAGE());
      SET @SkippedCount += 1;
    END CATCH;

    NextAlumni:
    FETCH NEXT FROM ac INTO @rowNum, @fn, @ln, @gradYear, @sem, @pos, @rc, @email, @phone, @linkedin, @employer, @jobTitle, @city, @state, @isDonor, @notes;
  END

  CLOSE ac; DEALLOCATE ac;

  SELECT @ErrorJson = ISNULL(
    (SELECT row_num AS rowNum, reason FROM @errors FOR JSON PATH), '[]');
END;
GO
