-- ============================================================
-- ROSTER DB — ALL STORED PROCEDURES
-- Run this file on: CfbRoster database
-- Run after: 001_initial_schema.sql
-- sp_GraduatePlayer requires linked servers [ALUMNI_DB] and [GLOBAL_DB]
-- ============================================================

-- ============================================================
-- sp_GetPlayers
-- Paginated, filterable player list.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetPlayers
  @Search     NVARCHAR(255) = NULL,
  @Status     NVARCHAR(20)  = NULL,
  @Position   NVARCHAR(10)  = NULL,
  @AcademicYear NVARCHAR(20) = NULL,
  @RecruitingClass SMALLINT  = NULL,
  @Page       INT           = 1,
  @PageSize   INT           = 50,
  @TotalCount INT           OUTPUT
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @Offset     INT          = (@Page - 1) * @PageSize;
  DECLARE @SearchWild NVARCHAR(257) = '%' + ISNULL(@Search, '') + '%';
  DECLARE @ExactNum   NVARCHAR(10)  = ISNULL(@Search, '');

  SELECT @TotalCount = COUNT(*)
  FROM dbo.players p
  WHERE (@Status       IS NULL OR p.status        = @Status)
    AND (@Position     IS NULL OR p.position      = @Position)
    AND (@AcademicYear IS NULL OR p.academic_year = @AcademicYear)
    AND (@RecruitingClass IS NULL OR p.recruiting_class = @RecruitingClass)
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
  FROM dbo.players p
  WHERE (@Status       IS NULL OR p.status        = @Status)
    AND (@Position     IS NULL OR p.position      = @Position)
    AND (@AcademicYear IS NULL OR p.academic_year = @AcademicYear)
    AND (@RecruitingClass IS NULL OR p.recruiting_class = @RecruitingClass)
    AND (@Search IS NULL OR p.first_name LIKE @SearchWild OR p.last_name LIKE @SearchWild
         OR CAST(p.jersey_number AS NVARCHAR) = @ExactNum)
  ORDER BY p.last_name, p.first_name
  OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- ============================================================
-- sp_GetPlayerById
-- Returns a single player with their season stats.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetPlayerById
  @PlayerId  UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.players WHERE id = @PlayerId)
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
    p.emergency_contact_name AS emergencyContactName,
    p.emergency_contact_phone AS emergencyContactPhone,
    p.notes, p.graduated_at AS graduatedAt,
    p.created_at AS createdAt, p.updated_at AS updatedAt
  FROM dbo.players p
  WHERE p.id = @PlayerId;

  -- Return stats separately
  SELECT
    ps.season_year  AS seasonYear,
    ps.games_played AS gamesPlayed,
    ps.stats_json   AS statsJson,
    ps.updated_at   AS updatedAt
  FROM dbo.player_stats ps
  WHERE ps.player_id = @PlayerId
  ORDER BY ps.season_year DESC;
END;
GO

-- ============================================================
-- sp_CreatePlayer
-- Creates a new player record with full validation.
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
  -- Output
  @NewPlayerId           UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode             NVARCHAR(50)     OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  -- Validate academic year
  IF @AcademicYear NOT IN ('freshman','sophomore','junior','senior','graduate')
  BEGIN
    SET @ErrorCode = 'INVALID_ACADEMIC_YEAR';
    RETURN;
  END

  -- Validate recruiting class year
  IF @RecruitingClass < 2000 OR @RecruitingClass > 2100
  BEGIN
    SET @ErrorCode = 'INVALID_RECRUITING_CLASS';
    RETURN;
  END

  -- Duplicate user check
  IF EXISTS (SELECT 1 FROM dbo.players WHERE user_id = @UserId)
  BEGIN
    SET @ErrorCode = 'PLAYER_ALREADY_EXISTS_FOR_USER';
    RETURN;
  END

  -- Duplicate jersey check (only within active players)
  IF @JerseyNumber IS NOT NULL AND EXISTS (
    SELECT 1 FROM dbo.players
    WHERE jersey_number = @JerseyNumber AND status = 'active'
  )
  BEGIN
    SET @ErrorCode = 'JERSEY_NUMBER_IN_USE';
    RETURN;
  END

  SET @NewPlayerId = NEWID();

  INSERT INTO dbo.players (
    id, user_id, jersey_number, first_name, last_name, position, academic_year,
    recruiting_class, height_inches, weight_lbs, home_town, home_state, high_school,
    gpa, major, phone, email, instagram, twitter, snapchat, emergency_contact_name, emergency_contact_phone, notes
  )
  VALUES (
    @NewPlayerId, @UserId, @JerseyNumber, @FirstName, @LastName, @Position, @AcademicYear,
    @RecruitingClass, @HeightInches, @WeightLbs, @HomeTown, @HomeState, @HighSchool,
    @Gpa, @Major, @Phone, @Email, @Instagram, @Twitter, @Snapchat, @EmergencyContactName, @EmergencyContactPhone, @Notes
  );
END;
GO

-- ============================================================
-- sp_UpdatePlayer
-- Updates only the fields that are passed (NULL = no change).
-- Status changes to 'graduated' are blocked — use sp_GraduatePlayer.
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

  IF NOT EXISTS (SELECT 1 FROM dbo.players WHERE id = @PlayerId)
  BEGIN
    SET @ErrorCode = 'PLAYER_NOT_FOUND';
    RETURN;
  END

  -- Block direct graduation via status update — must use sp_GraduatePlayer
  IF @Status = 'graduated'
  BEGIN
    SET @ErrorCode = 'USE_SP_GRADUATE_PLAYER';
    RETURN;
  END

  -- Validate status if provided
  IF @Status IS NOT NULL AND @Status NOT IN ('active','injured','suspended','transferred','walkOn')
  BEGIN
    SET @ErrorCode = 'INVALID_STATUS';
    RETURN;
  END

  -- Jersey conflict check if changing jersey
  IF @JerseyNumber IS NOT NULL AND EXISTS (
    SELECT 1 FROM dbo.players
    WHERE jersey_number = @JerseyNumber AND status = 'active' AND id <> @PlayerId
  )
  BEGIN
    SET @ErrorCode = 'JERSEY_NUMBER_IN_USE';
    RETURN;
  END

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
END;
GO

-- ============================================================
-- sp_UpsertPlayerStats
-- Inserts or updates season stats for a player.
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

  IF NOT EXISTS (SELECT 1 FROM dbo.players WHERE id = @PlayerId)
  BEGIN
    SET @ErrorCode = 'PLAYER_NOT_FOUND';
    RETURN;
  END

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
END;
GO

-- ============================================================
-- sp_GraduatePlayer
-- Full distributed transaction: Roster → Alumni → Global DB.
-- Processes a batch of player IDs; rolls back per-player on failure.
-- Prerequisites:
--   Linked server [ALUMNI_DB] → CfbAlumni database
--   Linked server [GLOBAL_DB] → CfbGlobal database
--   MSDTC enabled on all servers
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GraduatePlayer
  @PlayerIds         NVARCHAR(MAX),   -- JSON array: ["guid","guid",...]
  @GraduationYear    SMALLINT,
  @Semester          NVARCHAR(10),    -- 'spring' | 'fall' | 'summer'
  @TriggeredBy       NVARCHAR(100),   -- user_id (GUID string)
  @Notes             NVARCHAR(MAX)    = NULL,
  @TransactionId     UNIQUEIDENTIFIER OUTPUT,
  @SuccessCount      INT              OUTPUT,
  @FailureJson       NVARCHAR(MAX)    OUTPUT
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

  -- Input validation
  IF @GraduationYear < 2000 OR @GraduationYear > 2100
  BEGIN
    SET @FailureJson = JSON_OBJECT('error': 'Invalid graduation year');
    RETURN;
  END

  IF @Semester NOT IN ('spring','fall','summer')
  BEGIN
    SET @FailureJson = JSON_OBJECT('error': 'Invalid semester');
    RETURN;
  END

  -- Parse the JSON array of player GUIDs
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
      BEGIN DISTRIBUTED TRANSACTION;

        -- ── 1. Fetch and validate player ────────────────────
        DECLARE @firstName    NVARCHAR(100);
        DECLARE @lastName     NVARCHAR(100);
        DECLARE @position     NVARCHAR(10);
        DECLARE @recruitClass SMALLINT;
        DECLARE @userId       UNIQUEIDENTIFIER;
        DECLARE @curStatus    NVARCHAR(20);

        SELECT
          @firstName    = first_name,
          @lastName     = last_name,
          @position     = position,
          @recruitClass = recruiting_class,
          @userId       = user_id,
          @curStatus    = status
        FROM dbo.players
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

        -- ── 2. Mark graduated in Roster DB ──────────────────
        UPDATE dbo.players
        SET status       = 'graduated',
            graduated_at = SYSUTCDATETIME(),
            updated_at   = SYSUTCDATETIME()
        WHERE id = @currentId;

        -- ── 3. Graduation log in Roster DB ──────────────────
        INSERT INTO dbo.graduation_log
          (transaction_id, player_id, graduation_year, graduation_semester,
           triggered_by, status, notes)
        VALUES
          (@TransactionId, @currentId, @GraduationYear, @Semester,
           TRY_CAST(@TriggeredBy AS UNIQUEIDENTIFIER), 'success', @Notes);

        -- ── 4. Insert alumni record via linked server ────────
        EXEC [ALUMNI_DB].CfbAlumni.dbo.sp_CreateAlumniFromPlayer
          @UserId             = @userId,
          @SourcePlayerId     = @currentId,
          @FirstName          = @firstName,
          @LastName           = @lastName,
          @GraduationYear     = @GraduationYear,
          @GraduationSemester = @Semester,
          @Position           = @position,
          @RecruitingClass    = @recruitClass;

        -- ── 5. Swap permissions via linked server ────────────
        EXEC [GLOBAL_DB].CfbGlobal.dbo.sp_TransferPlayerToAlumni
          @UserId    = @userId,
          @GrantedBy = @TriggeredBy;

        COMMIT TRANSACTION;
        SET @SuccessCount = @SuccessCount + 1;

    END TRY
    BEGIN CATCH
      IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

      DECLARE @errMsg NVARCHAR(500) = ERROR_MESSAGE();
      INSERT INTO @failures VALUES (CAST(@currentId AS NVARCHAR(100)), @errMsg);

      -- Log failure outside the rolled-back transaction
      INSERT INTO dbo.graduation_log
        (transaction_id, player_id, graduation_year, graduation_semester,
         triggered_by, status, notes)
      VALUES
        (@TransactionId, @currentId, @GraduationYear, @Semester,
         TRY_CAST(@TriggeredBy AS UNIQUEIDENTIFIER), 'failed', @errMsg);

    END CATCH;

    FETCH NEXT FROM player_cursor INTO @currentId;
  END

  CLOSE player_cursor;
  DEALLOCATE player_cursor;

  SELECT @FailureJson = ISNULL(
    (SELECT player_id AS playerId, reason FROM @failures FOR JSON PATH),
    '[]'
  );
END;
GO

-- ============================================================
-- sp_TransferToAlumni
-- Marks players as graduated/transferred and returns their data
-- so the API can create alumni records.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_TransferToAlumni
  @PlayerIds         NVARCHAR(MAX),   -- JSON array: ["guid","guid",...]
  @TransferReason    NVARCHAR(50),
  @TransferYear      SMALLINT,
  @TransferSemester  NVARCHAR(10),
  @Notes             NVARCHAR(MAX)    = NULL,
  @TriggeredBy       NVARCHAR(100),
  -- Outputs
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
  SET @FailureJson   = '[]';
  SET @PlayersJson   = '[]';

  DECLARE @failures      TABLE (player_id NVARCHAR(100), reason NVARCHAR(500));
  DECLARE @transferred   TABLE (
    player_id        UNIQUEIDENTIFIER,
    user_id          UNIQUEIDENTIFIER,
    first_name       NVARCHAR(100),
    last_name        NVARCHAR(100),
    position         NVARCHAR(10),
    recruiting_class SMALLINT,
    phone            NVARCHAR(20),
    email            NVARCHAR(255)
  );
  DECLARE @playerIds2 TABLE (player_id UNIQUEIDENTIFIER);
  DECLARE @currentId  UNIQUEIDENTIFIER;

  -- Parse the JSON array of player GUIDs
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
        FROM dbo.players
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

        -- Mark player as graduated/transferred
        UPDATE dbo.players
        SET status       = 'graduated',
            graduated_at = SYSUTCDATETIME(),
            notes        = ISNULL(notes + CHAR(10), '') + 'Transfer reason: ' + @TransferReason,
            updated_at   = SYSUTCDATETIME()
        WHERE id = @currentId;

        -- Collect for PlayersJson
        INSERT INTO @transferred
          (player_id, user_id, first_name, last_name, position, recruiting_class, phone, email)
        VALUES
          (@currentId, @userId, @firstName, @lastName, @position, @recruitClass, @phone, @email);

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

  -- Build output JSON
  SELECT @FailureJson = ISNULL(
    (SELECT player_id AS playerId, reason FROM @failures FOR JSON PATH), '[]');

  SELECT @PlayersJson = ISNULL(
    (SELECT
       CAST(player_id AS NVARCHAR(50))  AS playerId,
       CAST(user_id   AS NVARCHAR(50))  AS userId,
       first_name       AS firstName,
       last_name        AS lastName,
       position,
       recruiting_class AS recruitingClass,
       phone,
       email
     FROM @transferred
     FOR JSON PATH), '[]');
END;
GO
