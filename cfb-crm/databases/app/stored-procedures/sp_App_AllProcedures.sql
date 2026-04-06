SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
-- ============================================================
-- APP DB — ALL STORED PROCEDURES
-- Run on: each tenant AppDB after 009_users_status_consolidation.sql
--
-- All players and alumni are rows in dbo.users, differentiated
-- by status_id (FK → dbo.player_status_types):
--   1 = current_player
--   2 = alumni
--   3 = removed
--
-- Create player flow:
--   1. Call [GLOBAL_DB].LegacyLinkGlobal.dbo.sp_GetOrCreateUser
--      (NOTE: add this SP to CfbGlobal — idempotent on email;
--       returns existing user ID if email already registered)
--   2. Upsert the returned user ID into AppDB dbo.users
--   3. If user already exists here, join on their existing row
--
-- Graduate = UPDATE dbo.users SET status_id = 2
-- Remove   = UPDATE dbo.users SET status_id = 3
-- ============================================================

-- ============================================================
-- sp_UpsertUser
-- Syncs a CfbGlobal user into local dbo.users.
-- Called after login / by create player flow.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpsertUser
  @UserId    UNIQUEIDENTIFIER,
  @Email     NVARCHAR(255),
  @FirstName NVARCHAR(100),
  @LastName  NVARCHAR(100)
AS
BEGIN
  SET NOCOUNT ON;

  IF EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId)
  BEGIN
    UPDATE dbo.users SET
      email      = @Email,
      first_name = @FirstName,
      last_name  = @LastName,
      updated_at = SYSUTCDATETIME()
    WHERE id = @UserId;
  END
  ELSE
  BEGIN
    INSERT INTO dbo.users (id, email, first_name, last_name)
    VALUES (@UserId, @Email, @FirstName, @LastName);
  END
END;
GO

-- ============================================================
-- sp_GetPlayers
-- Returns current players (status_id = 1).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetPlayers
  @Search          NVARCHAR(255)    = NULL,
  @Position        NVARCHAR(10)     = NULL,
  @AcademicYear    NVARCHAR(20)     = NULL,
  @RecruitingClass SMALLINT         = NULL,
  @SportId         UNIQUEIDENTIFIER = NULL,
  @Page            INT              = 1,
  @PageSize        INT              = 50,
  @TotalCount      INT              OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END

  DECLARE @Offset     INT           = (@Page - 1) * @PageSize;
  DECLARE @SearchWild NVARCHAR(257) = '%' + ISNULL(@Search, '') + '%';
  DECLARE @ExactNum   NVARCHAR(10)  = ISNULL(@Search, '');

  SELECT @TotalCount = COUNT(*)
  FROM dbo.users u
  WHERE u.status_id = 1
    AND (@Position        IS NULL OR u.position        = @Position)
    AND (@AcademicYear    IS NULL OR u.academic_year   = @AcademicYear)
    AND (@RecruitingClass IS NULL OR u.recruiting_class = @RecruitingClass)
    AND (@SportId         IS NULL OR u.sport_id        = @SportId)
    AND (@Search IS NULL
         OR u.first_name LIKE @SearchWild
         OR u.last_name  LIKE @SearchWild
         OR CAST(u.jersey_number AS NVARCHAR) = @ExactNum);

  SELECT
    u.id,
    u.sport_id              AS sportId,
    u.jersey_number         AS jerseyNumber,
    u.first_name            AS firstName,
    u.last_name             AS lastName,
    u.position,
    u.academic_year         AS academicYear,
    u.height_inches         AS heightInches,
    u.weight_lbs            AS weightLbs,
    u.home_town             AS homeTown,
    u.home_state            AS homeState,
    u.high_school           AS highSchool,
    u.recruiting_class      AS recruitingClass,
    u.gpa,
    u.major,
    u.phone,
    u.personal_email        AS email,
    u.instagram,
    u.twitter,
    u.snapchat,
    u.emergency_contact_name  AS emergencyContactName,
    u.emergency_contact_phone AS emergencyContactPhone,
    u.notes,
    u.created_at            AS createdAt,
    u.updated_at            AS updatedAt
  FROM dbo.users u
  WHERE u.status_id = 1
    AND (@Position        IS NULL OR u.position        = @Position)
    AND (@AcademicYear    IS NULL OR u.academic_year   = @AcademicYear)
    AND (@RecruitingClass IS NULL OR u.recruiting_class = @RecruitingClass)
    AND (@SportId         IS NULL OR u.sport_id        = @SportId)
    AND (@Search IS NULL
         OR u.first_name LIKE @SearchWild
         OR u.last_name  LIKE @SearchWild
         OR CAST(u.jersey_number AS NVARCHAR) = @ExactNum)
  ORDER BY u.last_name, u.first_name
  OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- ============================================================
-- sp_GetPlayerById
-- Returns a single current or historical player with stats.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetPlayerById
  @UserId    UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId AND status_id = 1)
  BEGIN
    SET @ErrorCode = 'PLAYER_NOT_FOUND';
    RETURN;
  END

  SELECT
    u.id,
    u.sport_id              AS sportId,
    u.jersey_number         AS jerseyNumber,
    u.first_name            AS firstName,
    u.last_name             AS lastName,
    u.position,
    u.academic_year         AS academicYear,
    u.height_inches         AS heightInches,
    u.weight_lbs            AS weightLbs,
    u.home_town             AS homeTown,
    u.home_state            AS homeState,
    u.high_school           AS highSchool,
    u.recruiting_class      AS recruitingClass,
    u.gpa,
    u.major,
    u.phone,
    u.personal_email        AS email,
    u.instagram,
    u.twitter,
    u.snapchat,
    u.emergency_contact_name  AS emergencyContactName,
    u.emergency_contact_phone AS emergencyContactPhone,
    u.notes,
    u.created_at            AS createdAt,
    u.updated_at            AS updatedAt
  FROM dbo.users u
  WHERE u.id = @UserId;

  SELECT
    ps.season_year  AS seasonYear,
    ps.games_played AS gamesPlayed,
    ps.stats_json   AS statsJson,
    ps.updated_at   AS updatedAt
  FROM dbo.player_stats ps
  WHERE ps.user_id = @UserId
  ORDER BY ps.season_year DESC;
END;
GO

-- ============================================================
-- sp_CreatePlayer
-- Creates a player account. Flow:
--   1. Call [GLOBAL_DB].LegacyLinkGlobal.dbo.sp_GetOrCreateUser to get
--      the canonical global user ID (creates account if needed,
--      returns existing ID if email already registered).
--   2. Upsert into AppDB dbo.users with that ID (status_id = 1).
--
-- NOTE: sp_GetOrCreateUser must exist in CfbGlobal. Signature:
--   @Email NVARCHAR(255), @FirstName NVARCHAR(100),
--   @LastName NVARCHAR(100), @TeamId UNIQUEIDENTIFIER,
--   @UserId UNIQUEIDENTIFIER OUTPUT, @ErrorCode NVARCHAR(50) OUTPUT
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreatePlayer
  @Email                 NVARCHAR(255),
  @FirstName             NVARCHAR(100),
  @LastName              NVARCHAR(100),
  @Position              NVARCHAR(10),
  @AcademicYear          NVARCHAR(20),
  @RecruitingClass       SMALLINT,
  @GlobalTeamId          UNIQUEIDENTIFIER,   -- team ID in CfbGlobal (for account creation)
  @SportId               UNIQUEIDENTIFIER = NULL,
  @JerseyNumber          TINYINT          = NULL,
  @HeightInches          TINYINT          = NULL,
  @WeightLbs             SMALLINT         = NULL,
  @HomeTown              NVARCHAR(100)    = NULL,
  @HomeState             NVARCHAR(50)     = NULL,
  @HighSchool            NVARCHAR(150)    = NULL,
  @Gpa                   DECIMAL(3,2)     = NULL,
  @Major                 NVARCHAR(100)    = NULL,
  @Phone                 NVARCHAR(20)     = NULL,
  @Instagram             NVARCHAR(100)    = NULL,
  @Twitter               NVARCHAR(100)    = NULL,
  @Snapchat              NVARCHAR(100)    = NULL,
  @EmergencyContactName  NVARCHAR(150)    = NULL,
  @EmergencyContactPhone NVARCHAR(20)     = NULL,
  @Notes                 NVARCHAR(MAX)    = NULL,
  @CreatedBy             UNIQUEIDENTIFIER,
  @NewUserId             UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode             NVARCHAR(50)     OUTPUT,
  @RequestingUserId      UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole    NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @ErrorCode = NULL;

  IF @AcademicYear NOT IN ('freshman','sophomore','junior','senior','graduate')
  BEGIN
    SET @ErrorCode = 'INVALID_ACADEMIC_YEAR';
    RETURN;
  END

  IF @RecruitingClass < 2000 OR @RecruitingClass > 2100
  BEGIN
    SET @ErrorCode = 'INVALID_RECRUITING_CLASS';
    RETURN;
  END

  IF @JerseyNumber IS NOT NULL AND EXISTS (
    SELECT 1 FROM dbo.users
    WHERE jersey_number = @JerseyNumber AND status_id = 1
      AND (@SportId IS NULL OR sport_id = @SportId)
  )
  BEGIN
    SET @ErrorCode = 'JERSEY_NUMBER_IN_USE';
    RETURN;
  END

  -- Step 1: Get or create user in CfbGlobal
  DECLARE @globalErr NVARCHAR(50);
  EXEC [GLOBAL_DB].LegacyLinkGlobal.dbo.sp_GetOrCreateUser
    @Email     = @Email,
    @FirstName = @FirstName,
    @LastName  = @LastName,
    @TeamId    = @GlobalTeamId,
    @UserId    = @NewUserId OUTPUT,
    @ErrorCode = @globalErr OUTPUT;

  IF @NewUserId IS NULL
  BEGIN
    SET @ErrorCode = ISNULL(@globalErr, 'GLOBAL_USER_CREATE_FAILED');
    RETURN;
  END

  -- Step 2: Upsert into AppDB dbo.users
  IF EXISTS (SELECT 1 FROM dbo.users WHERE id = @NewUserId)
  BEGIN
    -- User already exists (played another sport / returning user) — update their record
    UPDATE dbo.users SET
      email                   = @Email,
      first_name              = @FirstName,
      last_name               = @LastName,
      status_id               = 1,
      sport_id                = COALESCE(@SportId,                sport_id),
      jersey_number           = COALESCE(@JerseyNumber,           jersey_number),
      position                = @Position,
      academic_year           = @AcademicYear,
      recruiting_class        = @RecruitingClass,
      height_inches           = COALESCE(@HeightInches,           height_inches),
      weight_lbs              = COALESCE(@WeightLbs,              weight_lbs),
      home_town               = COALESCE(@HomeTown,               home_town),
      home_state              = COALESCE(@HomeState,              home_state),
      high_school             = COALESCE(@HighSchool,             high_school),
      gpa                     = COALESCE(@Gpa,                    gpa),
      major                   = COALESCE(@Major,                  major),
      phone                   = COALESCE(@Phone,                  phone),
      personal_email          = COALESCE(@Email,                  personal_email),
      instagram               = COALESCE(@Instagram,              instagram),
      twitter                 = COALESCE(@Twitter,                twitter),
      snapchat                = COALESCE(@Snapchat,               snapchat),
      emergency_contact_name  = COALESCE(@EmergencyContactName,  emergency_contact_name),
      emergency_contact_phone = COALESCE(@EmergencyContactPhone, emergency_contact_phone),
      notes                   = COALESCE(@Notes,                  notes),
      updated_at              = SYSUTCDATETIME()
    WHERE id = @NewUserId;
  END
  ELSE
  BEGIN
    INSERT INTO dbo.users (
      id, email, first_name, last_name, status_id, sport_id,
      jersey_number, position, academic_year, recruiting_class,
      height_inches, weight_lbs, home_town, home_state, high_school,
      gpa, major, phone, personal_email, instagram, twitter, snapchat,
      emergency_contact_name, emergency_contact_phone, notes
    )
    VALUES (
      @NewUserId, @Email, @FirstName, @LastName, 1, @SportId,
      @JerseyNumber, @Position, @AcademicYear, @RecruitingClass,
      @HeightInches, @WeightLbs, @HomeTown, @HomeState, @HighSchool,
      @Gpa, @Major, @Phone, @Email, @Instagram, @Twitter, @Snapchat,
      @EmergencyContactName, @EmergencyContactPhone, @Notes
    );
  END

  -- Register in users_sports if we have a sport
  IF @SportId IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM dbo.users_sports WHERE user_id = @NewUserId AND sport_id = @SportId)
  BEGIN
    INSERT INTO dbo.users_sports (user_id, sport_id, username)
    VALUES (@NewUserId, @SportId, @FirstName + ' ' + @LastName);
  END
END;
GO

-- ============================================================
-- sp_UpdatePlayer
-- Updates player profile. NULL = no change.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdatePlayer
  @UserId                UNIQUEIDENTIFIER,
  @JerseyNumber          TINYINT          = NULL,
  @Position              NVARCHAR(10)     = NULL,
  @AcademicYear          NVARCHAR(20)     = NULL,
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
  @ErrorCode             NVARCHAR(50)     OUTPUT,
  @RequestingUserId      UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole    NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId AND status_id = 1)
  BEGIN
    SET @ErrorCode = 'PLAYER_NOT_FOUND';
    RETURN;
  END

  IF @JerseyNumber IS NOT NULL AND EXISTS (
    SELECT 1 FROM dbo.users
    WHERE jersey_number = @JerseyNumber AND status_id = 1 AND id <> @UserId
  )
  BEGIN
    SET @ErrorCode = 'JERSEY_NUMBER_IN_USE';
    RETURN;
  END

  UPDATE dbo.users SET
    jersey_number           = COALESCE(@JerseyNumber,          jersey_number),
    position                = COALESCE(@Position,              position),
    academic_year           = COALESCE(@AcademicYear,          academic_year),
    height_inches           = COALESCE(@HeightInches,          height_inches),
    weight_lbs              = COALESCE(@WeightLbs,             weight_lbs),
    gpa                     = COALESCE(@Gpa,                   gpa),
    major                   = COALESCE(@Major,                 major),
    phone                   = COALESCE(@Phone,                 phone),
    personal_email          = COALESCE(@Email,                 personal_email),
    instagram               = COALESCE(@Instagram,             instagram),
    twitter                 = COALESCE(@Twitter,               twitter),
    snapchat                = COALESCE(@Snapchat,              snapchat),
    emergency_contact_name  = COALESCE(@EmergencyContactName,  emergency_contact_name),
    emergency_contact_phone = COALESCE(@EmergencyContactPhone, emergency_contact_phone),
    notes                   = COALESCE(@Notes,                 notes),
    updated_at              = SYSUTCDATETIME()
  WHERE id = @UserId;
END;
GO

-- ============================================================
-- sp_GraduatePlayer
-- Flips status_id to 2 (alumni) for one or more players.
-- Also swaps permissions in CfbGlobal via linked server.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GraduatePlayer
  @PlayerIds      NVARCHAR(MAX),   -- JSON array of user GUIDs
  @GraduationYear SMALLINT,
  @Semester       NVARCHAR(10),    -- 'spring' | 'fall' | 'summer'
  @TriggeredBy    NVARCHAR(100),
  @TransactionId  UNIQUEIDENTIFIER OUTPUT,
  @SuccessCount   INT              OUTPUT,
  @FailureJson    NVARCHAR(MAX)    OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  SET @TransactionId = NEWID();
  SET @SuccessCount  = 0;
  SET @FailureJson   = '[]';

  DECLARE @failures   TABLE (user_id NVARCHAR(100), reason NVARCHAR(500));
  DECLARE @userIds    TABLE (user_id UNIQUEIDENTIFIER);
  DECLARE @currentId  UNIQUEIDENTIFIER;

  IF @GraduationYear < 2000 OR @GraduationYear > 2100
  BEGIN
    SET @FailureJson = N'[{"error":"Invalid graduation year"}]';
    RETURN;
  END

  IF @Semester NOT IN ('spring','fall','summer')
  BEGIN
    SET @FailureJson = N'[{"error":"Invalid semester"}]';
    RETURN;
  END

  INSERT INTO @userIds
  SELECT TRY_CAST([value] AS UNIQUEIDENTIFIER)
  FROM OPENJSON(@PlayerIds)
  WHERE TRY_CAST([value] AS UNIQUEIDENTIFIER) IS NOT NULL;

  DECLARE cur CURSOR FOR SELECT user_id FROM @userIds;
  OPEN cur;
  FETCH NEXT FROM cur INTO @currentId;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @currentId AND status_id = 1)
        BEGIN
          ROLLBACK TRANSACTION;
          INSERT INTO @failures VALUES (CAST(@currentId AS NVARCHAR(100)),
            CASE WHEN EXISTS (SELECT 1 FROM dbo.users WHERE id = @currentId AND status_id = 2)
                 THEN 'Already an alumni'
                 ELSE 'Player not found' END);
          FETCH NEXT FROM cur INTO @currentId;
          CONTINUE;
        END

        -- Flip status to alumni
        UPDATE dbo.users SET
          status_id           = 2,
          graduation_year     = @GraduationYear,
          graduation_semester = @Semester,
          graduated_at        = SYSUTCDATETIME(),
          updated_at          = SYSUTCDATETIME()
        WHERE id = @currentId;

        -- Audit log
        INSERT INTO dbo.graduation_log
          (transaction_id, user_id, graduation_year, graduation_semester, triggered_by, status)
        VALUES
          (@TransactionId, @currentId, @GraduationYear, @Semester,
           TRY_CAST(@TriggeredBy AS UNIQUEIDENTIFIER), 'success');

        -- Swap permissions in CfbGlobal
        EXEC [GLOBAL_DB].LegacyLinkGlobal.dbo.sp_TransferPlayerToAlumni
          @UserId    = @currentId,
          @GrantedBy = @TriggeredBy;

      COMMIT TRANSACTION;
      SET @SuccessCount = @SuccessCount + 1;

    END TRY
    BEGIN CATCH
      IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

      DECLARE @errMsg NVARCHAR(500) = ERROR_MESSAGE();
      INSERT INTO @failures VALUES (CAST(@currentId AS NVARCHAR(100)), @errMsg);

      INSERT INTO dbo.graduation_log
        (transaction_id, user_id, graduation_year, graduation_semester, triggered_by, status, notes)
      VALUES
        (@TransactionId, @currentId, @GraduationYear, @Semester,
         TRY_CAST(@TriggeredBy AS UNIQUEIDENTIFIER), 'failed', @errMsg);
    END CATCH;

    FETCH NEXT FROM cur INTO @currentId;
  END

  CLOSE cur;
  DEALLOCATE cur;

  SELECT @FailureJson = ISNULL(
    (SELECT user_id AS userId, reason FROM @failures FOR JSON PATH), '[]');
END;
GO

-- ============================================================
-- sp_RemovePlayer
-- Sets status_id = 3 (removed). No reason required.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_RemovePlayer
  @UserId    UNIQUEIDENTIFIER,
  @RemovedBy UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId AND status_id IN (1, 2))
  BEGIN
    SET @ErrorCode = 'USER_NOT_FOUND';
    RETURN;
  END

  UPDATE dbo.users SET
    status_id  = 3,
    updated_at = SYSUTCDATETIME()
  WHERE id = @UserId;
END;
GO

-- ============================================================
-- sp_UpsertPlayerStats
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpsertPlayerStats
  @UserId      UNIQUEIDENTIFIER,
  @SeasonYear  SMALLINT,
  @GamesPlayed TINYINT       = NULL,
  @StatsJson   NVARCHAR(MAX) = NULL,
  @ErrorCode   NVARCHAR(50)  OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId AND status_id = 1)
  BEGIN
    SET @ErrorCode = 'PLAYER_NOT_FOUND';
    RETURN;
  END

  IF EXISTS (SELECT 1 FROM dbo.player_stats WHERE user_id = @UserId AND season_year = @SeasonYear)
  BEGIN
    UPDATE dbo.player_stats SET
      games_played = COALESCE(@GamesPlayed, games_played),
      stats_json   = COALESCE(@StatsJson,   stats_json),
      updated_at   = SYSUTCDATETIME()
    WHERE user_id = @UserId AND season_year = @SeasonYear;
  END
  ELSE
  BEGIN
    INSERT INTO dbo.player_stats (user_id, season_year, games_played, stats_json)
    VALUES (@UserId, @SeasonYear, @GamesPlayed, @StatsJson);
  END
END;
GO

-- ============================================================
-- sp_GetAlumni
-- Returns alumni (status_id = 2).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetAlumni
  @Search    NVARCHAR(255)    = NULL,
  @IsDonor   BIT              = NULL,
  @GradYear  SMALLINT         = NULL,
  @Position  NVARCHAR(10)     = NULL,
  @SportId   UNIQUEIDENTIFIER = NULL,
  @Page      INT              = 1,
  @PageSize  INT              = 50,
  @TotalCount INT             OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END

  DECLARE @Offset     INT           = (@Page - 1) * @PageSize;
  DECLARE @SearchWild NVARCHAR(257) = '%' + ISNULL(@Search, '') + '%';

  SELECT @TotalCount = COUNT(*)
  FROM dbo.users u
  WHERE u.status_id = 2
    AND (@IsDonor  IS NULL OR u.is_donor        = @IsDonor)
    AND (@GradYear IS NULL OR u.graduation_year = @GradYear)
    AND (@Position IS NULL OR u.position        = @Position)
    AND (@SportId  IS NULL OR u.sport_id        = @SportId)
    AND (@Search IS NULL
         OR u.first_name       LIKE @SearchWild
         OR u.last_name        LIKE @SearchWild
         OR u.current_employer LIKE @SearchWild
         OR u.current_city     LIKE @SearchWild
         OR u.personal_email   LIKE @SearchWild);

  SELECT
    u.id,
    u.sport_id              AS sportId,
    u.first_name            AS firstName,
    u.last_name             AS lastName,
    u.graduation_year       AS graduationYear,
    u.graduation_semester   AS graduationSemester,
    u.position,
    u.recruiting_class      AS recruitingClass,
    u.personal_email        AS personalEmail,
    u.phone,
    u.linkedin_url          AS linkedInUrl,
    u.twitter_url           AS twitterUrl,
    u.current_employer      AS currentEmployer,
    u.current_job_title     AS currentJobTitle,
    u.current_city          AS currentCity,
    u.current_state         AS currentState,
    u.is_donor              AS isDonor,
    u.last_donation_date    AS lastDonationDate,
    u.total_donations       AS totalDonations,
    u.engagement_score      AS engagementScore,
    u.notes,
    u.created_at            AS createdAt,
    u.updated_at            AS updatedAt
  FROM dbo.users u
  WHERE u.status_id = 2
    AND (@IsDonor  IS NULL OR u.is_donor        = @IsDonor)
    AND (@GradYear IS NULL OR u.graduation_year = @GradYear)
    AND (@Position IS NULL OR u.position        = @Position)
    AND (@SportId  IS NULL OR u.sport_id        = @SportId)
    AND (@Search IS NULL
         OR u.first_name       LIKE @SearchWild
         OR u.last_name        LIKE @SearchWild
         OR u.current_employer LIKE @SearchWild
         OR u.current_city     LIKE @SearchWild
         OR u.personal_email   LIKE @SearchWild)
  ORDER BY u.last_name, u.first_name
  OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- ============================================================
-- sp_GetAlumniById
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetAlumniById
  @UserId    UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId AND status_id = 2)
  BEGIN
    SET @ErrorCode = 'ALUMNI_NOT_FOUND';
    RETURN;
  END

  SELECT
    u.id,
    u.sport_id              AS sportId,
    u.first_name            AS firstName,
    u.last_name             AS lastName,
    u.graduation_year       AS graduationYear,
    u.graduation_semester   AS graduationSemester,
    u.position,
    u.recruiting_class      AS recruitingClass,
    u.personal_email        AS personalEmail,
    u.phone,
    u.linkedin_url          AS linkedInUrl,
    u.twitter_url           AS twitterUrl,
    u.current_employer      AS currentEmployer,
    u.current_job_title     AS currentJobTitle,
    u.current_city          AS currentCity,
    u.current_state         AS currentState,
    u.is_donor              AS isDonor,
    u.last_donation_date    AS lastDonationDate,
    u.total_donations       AS totalDonations,
    u.engagement_score      AS engagementScore,
    u.communication_consent AS communicationConsent,
    u.years_on_roster       AS yearsOnRoster,
    u.notes,
    u.created_at            AS createdAt,
    u.updated_at            AS updatedAt
  FROM dbo.users u
  WHERE u.id = @UserId;

  SELECT
    il.id,
    il.channel,
    il.summary,
    il.outcome,
    il.follow_up_at AS followUpAt,
    il.logged_at    AS loggedAt,
    il.logged_by    AS loggedBy
  FROM dbo.interaction_log il
  WHERE il.user_id = @UserId
  ORDER BY il.logged_at DESC;
END;
GO

-- ============================================================
-- sp_UpdateAlumni
-- Updates alumni contact/career info. NULL = no change.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateAlumni
  @UserId          UNIQUEIDENTIFIER,
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
  @ErrorCode       NVARCHAR(50)   OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId AND status_id = 2)
  BEGIN
    SET @ErrorCode = 'ALUMNI_NOT_FOUND';
    RETURN;
  END

  UPDATE dbo.users SET
    personal_email    = COALESCE(@PersonalEmail,    personal_email),
    phone             = COALESCE(@Phone,             phone),
    linkedin_url      = COALESCE(@LinkedInUrl,       linkedin_url),
    twitter_url       = COALESCE(@TwitterUrl,        twitter_url),
    current_employer  = COALESCE(@CurrentEmployer,  current_employer),
    current_job_title = COALESCE(@CurrentJobTitle,  current_job_title),
    current_city      = COALESCE(@CurrentCity,      current_city),
    current_state     = COALESCE(@CurrentState,     current_state),
    is_donor          = COALESCE(@IsDonor,          is_donor),
    last_donation_date= COALESCE(@LastDonationDate, last_donation_date),
    total_donations   = COALESCE(@TotalDonations,   total_donations),
    notes             = COALESCE(@Notes,            notes),
    updated_at        = SYSUTCDATETIME()
  WHERE id = @UserId;

  -- Recalculate engagement score
  UPDATE dbo.users SET
    engagement_score = CAST(
      30
      + CASE WHEN personal_email   IS NOT NULL THEN 10 ELSE 0 END
      + CASE WHEN phone            IS NOT NULL THEN 8  ELSE 0 END
      + CASE WHEN linkedin_url     IS NOT NULL THEN 7  ELSE 0 END
      + CASE WHEN current_employer IS NOT NULL THEN 10 ELSE 0 END
      + CASE WHEN current_job_title IS NOT NULL THEN 10 ELSE 0 END
      + CASE WHEN is_donor = 1 THEN 25 ELSE 0 END
    AS TINYINT)
  WHERE id = @UserId;
END;
GO

-- ============================================================
-- sp_LogInteraction
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_LogInteraction
  @UserId     UNIQUEIDENTIFIER,
  @LoggedBy   UNIQUEIDENTIFIER,
  @Channel    NVARCHAR(30),
  @Summary    NVARCHAR(MAX),
  @Outcome    NVARCHAR(50)  = NULL,
  @FollowUpAt DATETIME2     = NULL,
  @ErrorCode  NVARCHAR(50)  OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId AND status_id = 2)
  BEGIN
    SET @ErrorCode = 'ALUMNI_NOT_FOUND';
    RETURN;
  END

  IF LEN(LTRIM(RTRIM(@Summary))) = 0
  BEGIN
    SET @ErrorCode = 'SUMMARY_REQUIRED';
    RETURN;
  END

  INSERT INTO dbo.interaction_log (user_id, logged_by, channel, summary, outcome, follow_up_at)
  VALUES (@UserId, @LoggedBy, @Channel, @Summary, @Outcome, @FollowUpAt);

  UPDATE dbo.users SET
    engagement_score = CAST(CASE
        WHEN engagement_score + 2 > 100 THEN 100
        ELSE engagement_score + 2
      END AS TINYINT),
    updated_at = SYSUTCDATETIME()
  WHERE id = @UserId;
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
  @SportId         UNIQUEIDENTIFIER = NULL,
  @NewCampaignId   UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode       NVARCHAR(50)     OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @ErrorCode = NULL;

  IF LEN(LTRIM(RTRIM(@Name))) = 0 BEGIN SET @ErrorCode = 'NAME_REQUIRED'; RETURN; END
  IF @TargetAudience NOT IN ('all','byClass','byPosition','byStatus','custom') BEGIN SET @ErrorCode = 'INVALID_TARGET_AUDIENCE'; RETURN; END
  IF @TargetAudience = 'custom' AND (@AudienceFilters IS NULL OR LEN(@AudienceFilters) < 2) BEGIN SET @ErrorCode = 'CUSTOM_AUDIENCE_REQUIRES_FILTERS'; RETURN; END
  IF @ScheduledAt IS NOT NULL AND @ScheduledAt < SYSUTCDATETIME() BEGIN SET @ErrorCode = 'SCHEDULED_DATE_IN_PAST'; RETURN; END

  SET @NewCampaignId = NEWID();

  INSERT INTO dbo.outreach_campaigns
    (id, sport_id, name, description, target_audience, audience_filters, scheduled_at, created_by)
  VALUES
    (@NewCampaignId, @SportId, @Name, @Description, @TargetAudience, @AudienceFilters, @ScheduledAt, @CreatedBy);
END;
GO

-- ============================================================
-- sp_GetCampaigns
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetCampaigns
  @SportId            UNIQUEIDENTIFIER = NULL,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END

  SELECT
    c.id, c.sport_id AS sportId, c.name, c.description,
    c.target_audience AS targetAudience, c.status,
    c.scheduled_at AS scheduledAt, c.completed_at AS completedAt,
    c.created_by AS createdBy, c.created_at AS createdAt,
    COUNT(m.id)                                                       AS totalMessages,
    SUM(CASE WHEN m.status = 'sent'      THEN 1 ELSE 0 END)          AS sentCount,
    SUM(CASE WHEN m.status = 'responded' THEN 1 ELSE 0 END)          AS respondedCount,
    SUM(CASE WHEN m.status = 'bounced'   THEN 1 ELSE 0 END)          AS bouncedCount,
    CASE
      WHEN SUM(CASE WHEN m.status = 'sent' THEN 1 ELSE 0 END) > 0
      THEN CAST(SUM(CASE WHEN m.status = 'responded' THEN 1 ELSE 0 END) * 100.0 /
                SUM(CASE WHEN m.status = 'sent'      THEN 1 ELSE 0 END) AS DECIMAL(5,2))
      ELSE 0
    END AS responseRatePct
  FROM dbo.outreach_campaigns c
  LEFT JOIN dbo.outreach_messages m ON m.campaign_id = c.id
  WHERE (@SportId IS NULL OR c.sport_id = @SportId)
  GROUP BY c.id, c.sport_id, c.name, c.description, c.target_audience,
           c.status, c.scheduled_at, c.completed_at, c.created_by, c.created_at
  ORDER BY c.created_at DESC;
END;
GO

-- ============================================================
-- sp_GetAlumniStats
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetAlumniStats
  @SportId            UNIQUEIDENTIFIER = NULL,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END

  SELECT
    COUNT(*)                                                      AS totalAlumni,
    SUM(CASE WHEN is_donor = 1 THEN 1 ELSE 0 END)                AS donors,
    ISNULL(SUM(total_donations), 0)                              AS totalDonations,
    ISNULL(CAST(AVG(CAST(engagement_score AS FLOAT)) AS DECIMAL(5,1)), 0) AS avgEngagement,
    MIN(graduation_year)                                          AS earliestClass,
    MAX(graduation_year)                                          AS latestClass,
    (
      SELECT graduation_year AS gradYear, COUNT(*) AS cnt
      FROM dbo.users
      WHERE status_id = 2
        AND (@SportId IS NULL OR sport_id = @SportId)
      GROUP BY graduation_year
      ORDER BY graduation_year DESC
      FOR JSON PATH
    ) AS classCounts
  FROM dbo.users
  WHERE status_id = 2
    AND (@SportId IS NULL OR sport_id = @SportId);
END;
GO

-- ============================================================
-- sp_ResolveAudienceForCampaign
-- position filter now reads directly from dbo.users.position
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ResolveAudienceForCampaign
  @CampaignId UNIQUEIDENTIFIER,
  @ErrorCode  NVARCHAR(50) OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @ErrorCode = NULL;

  DECLARE @Audience    NVARCHAR(20);
  DECLARE @FiltersJson NVARCHAR(MAX);

  SELECT @Audience = target_audience, @FiltersJson = audience_filters
  FROM dbo.outreach_campaigns
  WHERE id = @CampaignId;

  IF @Audience IS NULL BEGIN SET @ErrorCode = 'CAMPAIGN_NOT_FOUND'; RETURN; END

  DECLARE @FilterGradYear SMALLINT     = TRY_CAST(JSON_VALUE(@FiltersJson, '$.gradYear')  AS SMALLINT);
  DECLARE @FilterPosition NVARCHAR(10) = JSON_VALUE(@FiltersJson, '$.position');
  DECLARE @FilterStatus   NVARCHAR(20) = JSON_VALUE(@FiltersJson, '$.status');

  SELECT
    u.id              AS userId,
    u.first_name      AS firstName,
    u.last_name       AS lastName,
    u.personal_email  AS personalEmail,
    u.phone
  FROM dbo.users u
  WHERE u.status_id = 2
    AND (
      @Audience = 'all'
      OR (@Audience = 'byClass'    AND u.graduation_year = @FilterGradYear)
      OR (@Audience = 'byPosition' AND u.position        = @FilterPosition)
      OR (@Audience = 'byStatus'   AND u.status_id       = TRY_CAST(@FilterStatus AS INT))
      OR (@Audience = 'custom'
          AND (@FilterGradYear IS NULL OR u.graduation_year = @FilterGradYear)
          AND (@FilterPosition IS NULL OR u.position        = @FilterPosition)
      )
    );
END;
GO

-- ============================================================
-- BULK OPERATIONS
-- ============================================================

-- ============================================================
-- sp_BulkCreatePlayers
-- For each row: calls CfbGlobal sp_GetOrCreateUser, then
-- upserts into AppDB dbo.users. Joins on existing global ID
-- if the person is already registered.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_BulkCreatePlayers
  @PlayersJson  NVARCHAR(MAX),
  @CreatedBy    UNIQUEIDENTIFIER,
  @GlobalTeamId UNIQUEIDENTIFIER,   -- team ID in CfbGlobal
  @SportId      UNIQUEIDENTIFIER = NULL,
  @SuccessCount INT OUTPUT,
  @SkippedCount INT OUTPUT,
  @ErrorJson    NVARCHAR(MAX) OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @SuccessCount = 0;
  SET @SkippedCount = 0;
  SET @ErrorJson    = '[]';

  DECLARE @errors TABLE (row_num INT, reason NVARCHAR(500));
  DECLARE @rows TABLE (
    row_num                  INT,
    email                    NVARCHAR(255),
    first_name               NVARCHAR(100),
    last_name                NVARCHAR(100),
    jersey_number            TINYINT,
    position                 NVARCHAR(10),
    academic_year            NVARCHAR(20),
    recruiting_class         SMALLINT,
    height_inches            TINYINT,
    weight_lbs               SMALLINT,
    home_town                NVARCHAR(100),
    home_state               NVARCHAR(50),
    high_school              NVARCHAR(150),
    gpa                      DECIMAL(3,2),
    major                    NVARCHAR(100),
    phone                    NVARCHAR(20),
    emergency_contact_name   NVARCHAR(150),
    emergency_contact_phone  NVARCHAR(20),
    notes                    NVARCHAR(MAX)
  );

  INSERT INTO @rows (
    row_num, email, first_name, last_name,
    jersey_number, position, academic_year, recruiting_class,
    height_inches, weight_lbs, home_town, home_state, high_school,
    gpa, major, phone, emergency_contact_name, emergency_contact_phone, notes
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    JSON_VALUE(value, '$.email'),
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

  DECLARE @rowNum   INT;
  DECLARE @email    NVARCHAR(255);
  DECLARE @fn       NVARCHAR(100);
  DECLARE @ln       NVARCHAR(100);
  DECLARE @jersey   TINYINT;
  DECLARE @pos      NVARCHAR(10);
  DECLARE @acYear   NVARCHAR(20);
  DECLARE @recClass SMALLINT;
  DECLARE @heightIn TINYINT;
  DECLARE @wt       SMALLINT;
  DECLARE @town     NVARCHAR(100);
  DECLARE @state    NVARCHAR(50);
  DECLARE @hs       NVARCHAR(150);
  DECLARE @gpa      DECIMAL(3,2);
  DECLARE @major    NVARCHAR(100);
  DECLARE @phone    NVARCHAR(20);
  DECLARE @ecName   NVARCHAR(150);
  DECLARE @ecPhone  NVARCHAR(20);
  DECLARE @notes    NVARCHAR(MAX);

  DECLARE cur CURSOR FOR
    SELECT row_num, email, first_name, last_name,
           jersey_number, position, academic_year, recruiting_class,
           height_inches, weight_lbs, home_town, home_state, high_school,
           gpa, major, phone, emergency_contact_name, emergency_contact_phone, notes
    FROM @rows;

  OPEN cur;
  FETCH NEXT FROM cur INTO
    @rowNum, @email, @fn, @ln, @jersey, @pos, @acYear, @recClass,
    @heightIn, @wt, @town, @state, @hs, @gpa, @major, @phone, @ecName, @ecPhone, @notes;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      IF @fn IS NULL OR LEN(LTRIM(RTRIM(@fn))) = 0
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'First name is required');
        SET @SkippedCount += 1; GOTO NextRow;
      END

      IF @ln IS NULL OR LEN(LTRIM(RTRIM(@ln))) = 0
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'Last name is required');
        SET @SkippedCount += 1; GOTO NextRow;
      END

      IF @recClass IS NULL OR @recClass < 2000 OR @recClass > 2100
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'Invalid recruiting class year');
        SET @SkippedCount += 1; GOTO NextRow;
      END

      IF @jersey IS NOT NULL AND EXISTS (
        SELECT 1 FROM dbo.users
        WHERE jersey_number = @jersey AND status_id = 1
          AND (@SportId IS NULL OR sport_id = @SportId)
      )
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'Jersey #' + CAST(@jersey AS NVARCHAR) + ' already in use');
        SET @SkippedCount += 1; GOTO NextRow;
      END

      -- Get or create in CfbGlobal
      DECLARE @newUserId UNIQUEIDENTIFIER;
      DECLARE @globalErr NVARCHAR(50);
      EXEC [GLOBAL_DB].LegacyLinkGlobal.dbo.sp_GetOrCreateUser
        @Email     = @email,
        @FirstName = @fn,
        @LastName  = @ln,
        @TeamId    = @GlobalTeamId,
        @UserId    = @newUserId OUTPUT,
        @ErrorCode = @globalErr OUTPUT;

      IF @newUserId IS NULL
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'Global user creation failed: ' + ISNULL(@globalErr, 'unknown'));
        SET @SkippedCount += 1; GOTO NextRow;
      END

      -- Upsert into AppDB
      IF EXISTS (SELECT 1 FROM dbo.users WHERE id = @newUserId)
      BEGIN
        UPDATE dbo.users SET
          status_id               = 1,
          sport_id                = COALESCE(@SportId,  sport_id),
          jersey_number           = COALESCE(@jersey,   jersey_number),
          position                = ISNULL(@pos,        position),
          academic_year           = ISNULL(@acYear,     academic_year),
          recruiting_class        = ISNULL(@recClass,   recruiting_class),
          height_inches           = COALESCE(@heightIn, height_inches),
          weight_lbs              = COALESCE(@wt,       weight_lbs),
          home_town               = COALESCE(@town,     home_town),
          home_state              = COALESCE(@state,    home_state),
          high_school             = COALESCE(@hs,       high_school),
          gpa                     = COALESCE(@gpa,      gpa),
          major                   = COALESCE(@major,    major),
          phone                   = COALESCE(@phone,    phone),
          emergency_contact_name  = COALESCE(@ecName,  emergency_contact_name),
          emergency_contact_phone = COALESCE(@ecPhone, emergency_contact_phone),
          notes                   = COALESCE(@notes,   notes),
          updated_at              = SYSUTCDATETIME()
        WHERE id = @newUserId;
      END
      ELSE
      BEGIN
        INSERT INTO dbo.users (
          id, email, first_name, last_name, status_id, sport_id,
          jersey_number, position, academic_year, recruiting_class,
          height_inches, weight_lbs, home_town, home_state, high_school,
          gpa, major, phone, emergency_contact_name, emergency_contact_phone, notes
        )
        VALUES (
          @newUserId,
          ISNULL(@email, 'provisional-' + LOWER(CAST(@newUserId AS NVARCHAR(36))) + '@import.local'),
          @fn, @ln, 1, @SportId,
          @jersey, @pos, @acYear, @recClass,
          @heightIn, @wt, @town, @state, @hs,
          @gpa, @major, @phone, @ecName, @ecPhone, @notes
        );
      END

      IF @SportId IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM dbo.users_sports WHERE user_id = @newUserId AND sport_id = @SportId)
      BEGIN
        INSERT INTO dbo.users_sports (user_id, sport_id, username) VALUES (@newUserId, @SportId, @fn + ' ' + @ln);
      END

      SET @SuccessCount += 1;

    END TRY
    BEGIN CATCH
      INSERT INTO @errors VALUES (@rowNum, ERROR_MESSAGE());
      SET @SkippedCount += 1;
    END CATCH;

    NextRow:
    FETCH NEXT FROM cur INTO
      @rowNum, @email, @fn, @ln, @jersey, @pos, @acYear, @recClass,
      @heightIn, @wt, @town, @state, @hs, @gpa, @major, @phone, @ecName, @ecPhone, @notes;
  END

  CLOSE cur;
  DEALLOCATE cur;

  SELECT @ErrorJson = ISNULL(
    (SELECT row_num AS rowNum, reason FROM @errors FOR JSON PATH), '[]');
END;
GO

-- ============================================================
-- sp_BulkCreateAlumni
-- Same global-first pattern as sp_BulkCreatePlayers.
-- Inserts directly as status_id = 2 (alumni).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_BulkCreateAlumni
  @AlumniJson   NVARCHAR(MAX),
  @CreatedBy    UNIQUEIDENTIFIER,
  @GlobalTeamId UNIQUEIDENTIFIER,
  @SportId      UNIQUEIDENTIFIER = NULL,
  @SuccessCount INT OUTPUT,
  @SkippedCount INT OUTPUT,
  @ErrorJson    NVARCHAR(MAX) OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @SuccessCount = 0;
  SET @SkippedCount = 0;
  SET @ErrorJson    = '[]';

  DECLARE @errors TABLE (row_num INT, reason NVARCHAR(500));
  DECLARE @rows TABLE (
    row_num             INT,
    email               NVARCHAR(255),
    first_name          NVARCHAR(100),
    last_name           NVARCHAR(100),
    graduation_year     SMALLINT,
    graduation_semester NVARCHAR(10),
    phone               NVARCHAR(20),
    linkedin_url        NVARCHAR(500),
    current_employer    NVARCHAR(200),
    current_job_title   NVARCHAR(150),
    current_city        NVARCHAR(100),
    current_state       NVARCHAR(50),
    is_donor            BIT,
    notes               NVARCHAR(MAX)
  );

  INSERT INTO @rows (
    row_num, email, first_name, last_name,
    graduation_year, graduation_semester,
    phone, linkedin_url,
    current_employer, current_job_title, current_city, current_state,
    is_donor, notes
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    JSON_VALUE(value, '$.email'),
    JSON_VALUE(value, '$.firstName'),
    JSON_VALUE(value, '$.lastName'),
    TRY_CAST(JSON_VALUE(value, '$.graduationYear')   AS SMALLINT),
    ISNULL(JSON_VALUE(value, '$.graduationSemester'), 'spring'),
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
  DECLARE @email    NVARCHAR(255);
  DECLARE @fn       NVARCHAR(100);
  DECLARE @ln       NVARCHAR(100);
  DECLARE @gradYear SMALLINT;
  DECLARE @semester NVARCHAR(10);
  DECLARE @phone    NVARCHAR(20);
  DECLARE @linkedin NVARCHAR(500);
  DECLARE @employer NVARCHAR(200);
  DECLARE @jobTitle NVARCHAR(150);
  DECLARE @city     NVARCHAR(100);
  DECLARE @state    NVARCHAR(50);
  DECLARE @isDonor  BIT;
  DECLARE @notes    NVARCHAR(MAX);

  DECLARE cur CURSOR FOR
    SELECT row_num, email, first_name, last_name,
           graduation_year, graduation_semester,
           phone, linkedin_url,
           current_employer, current_job_title, current_city, current_state,
           is_donor, notes
    FROM @rows;

  OPEN cur;
  FETCH NEXT FROM cur INTO
    @rowNum, @email, @fn, @ln, @gradYear, @semester,
    @phone, @linkedin, @employer, @jobTitle, @city, @state, @isDonor, @notes;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      IF @fn IS NULL OR LEN(LTRIM(RTRIM(@fn))) = 0 BEGIN INSERT INTO @errors VALUES (@rowNum, 'First name required'); SET @SkippedCount += 1; GOTO NextAlumRow; END
      IF @ln IS NULL OR LEN(LTRIM(RTRIM(@ln))) = 0 BEGIN INSERT INTO @errors VALUES (@rowNum, 'Last name required');  SET @SkippedCount += 1; GOTO NextAlumRow; END
      IF @gradYear IS NULL OR @gradYear < 1950 OR @gradYear > 2100 BEGIN INSERT INTO @errors VALUES (@rowNum, 'Invalid graduation year'); SET @SkippedCount += 1; GOTO NextAlumRow; END

      DECLARE @newUserId UNIQUEIDENTIFIER;
      DECLARE @globalErr NVARCHAR(50);
      EXEC [GLOBAL_DB].LegacyLinkGlobal.dbo.sp_GetOrCreateUser
        @Email = @email, @FirstName = @fn, @LastName = @ln, @TeamId = @GlobalTeamId,
        @UserId = @newUserId OUTPUT, @ErrorCode = @globalErr OUTPUT;

      IF @newUserId IS NULL BEGIN INSERT INTO @errors VALUES (@rowNum, 'Global user creation failed: ' + ISNULL(@globalErr, 'unknown')); SET @SkippedCount += 1; GOTO NextAlumRow; END

      IF EXISTS (SELECT 1 FROM dbo.users WHERE id = @newUserId)
      BEGIN
        UPDATE dbo.users SET
          status_id           = 2,
          sport_id            = COALESCE(@SportId, sport_id),
          graduation_year     = @gradYear,
          graduation_semester = @semester,
          phone               = COALESCE(@phone,    phone),
          personal_email      = COALESCE(@email,    personal_email),
          linkedin_url        = COALESCE(@linkedin, linkedin_url),
          current_employer    = COALESCE(@employer, current_employer),
          current_job_title   = COALESCE(@jobTitle, current_job_title),
          current_city        = COALESCE(@city,     current_city),
          current_state       = COALESCE(@state,    current_state),
          is_donor            = COALESCE(@isDonor,  is_donor),
          notes               = COALESCE(@notes,    notes),
          updated_at          = SYSUTCDATETIME()
        WHERE id = @newUserId;
      END
      ELSE
      BEGIN
        INSERT INTO dbo.users (
          id, email, first_name, last_name, status_id, sport_id,
          graduation_year, graduation_semester,
          phone, personal_email, linkedin_url,
          current_employer, current_job_title, current_city, current_state,
          is_donor, notes
        )
        VALUES (
          @newUserId,
          ISNULL(@email, 'provisional-' + LOWER(CAST(@newUserId AS NVARCHAR(36))) + '@import.local'),
          @fn, @ln, 2, @SportId,
          @gradYear, @semester,
          @phone, @email, @linkedin,
          @employer, @jobTitle, @city, @state,
          ISNULL(@isDonor, 0), @notes
        );
      END

      IF @SportId IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM dbo.users_sports WHERE user_id = @newUserId AND sport_id = @SportId)
      BEGIN
        INSERT INTO dbo.users_sports (user_id, sport_id, username) VALUES (@newUserId, @SportId, @fn + ' ' + @ln);
      END

      SET @SuccessCount += 1;

    END TRY
    BEGIN CATCH
      INSERT INTO @errors VALUES (@rowNum, ERROR_MESSAGE());
      SET @SkippedCount += 1;
    END CATCH;

    NextAlumRow:
    FETCH NEXT FROM cur INTO
      @rowNum, @email, @fn, @ln, @gradYear, @semester,
      @phone, @linkedin, @employer, @jobTitle, @city, @state, @isDonor, @notes;
  END

  CLOSE cur;
  DEALLOCATE cur;

  SELECT @ErrorJson = ISNULL(
    (SELECT row_num AS rowNum, reason FROM @errors FOR JSON PATH), '[]');
END;
GO

-- ============================================================
-- sp_CreateAlumni
-- Creates a single alumni record for a user who already exists
-- in CfbGlobal (frontend pre-creates the account via global-api).
-- Upserts into dbo.users with status_id = 2.
-- If the user is already an alumni (ALUMNI_ALREADY_EXISTS),
-- the caller treats this as idempotent success.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateAlumni
  @UserId             UNIQUEIDENTIFIER,
  @FirstName          NVARCHAR(100),
  @LastName           NVARCHAR(100),
  @GraduationYear     SMALLINT,
  @GraduationSemester NVARCHAR(10)     = 'spring',
  @Position           NVARCHAR(10)     = NULL,
  @RecruitingClass    SMALLINT         = NULL,
  @SportId            UNIQUEIDENTIFIER = NULL,
  @Phone              NVARCHAR(20)     = NULL,
  @PersonalEmail      NVARCHAR(255)    = NULL,
  @CurrentEmployer    NVARCHAR(200)    = NULL,
  @CurrentJobTitle    NVARCHAR(150)    = NULL,
  @CurrentCity        NVARCHAR(100)    = NULL,
  @CurrentState       NVARCHAR(50)     = NULL,
  @Notes              NVARCHAR(MAX)    = NULL,
  @ErrorCode          NVARCHAR(50)     OUTPUT,
  @RequestingUserId   UNIQUEIDENTIFIER = NULL,
  @RequestingUserRole NVARCHAR(50)     = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @RequestingUserId IS NOT NULL
  BEGIN
    DECLARE @_uid  NVARCHAR(100) = CAST(@RequestingUserId AS NVARCHAR(100));
    DECLARE @_role NVARCHAR(50)  = ISNULL(@RequestingUserRole, N'');
    EXEC sp_set_session_context N'user_id',   @_uid;
    EXEC sp_set_session_context N'user_role', @_role;
  END
  SET @ErrorCode = NULL;

  IF @GraduationYear < 2000 OR @GraduationYear > 2100
  BEGIN
    SET @ErrorCode = 'INVALID_GRADUATION_YEAR';
    RETURN;
  END

  IF @GraduationSemester NOT IN ('spring','fall','summer')
  BEGIN
    SET @ErrorCode = 'INVALID_SEMESTER';
    RETURN;
  END

  -- Already an alumni — idempotent
  IF EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId AND status_id = 2)
  BEGIN
    SET @ErrorCode = 'ALUMNI_ALREADY_EXISTS';
    RETURN;
  END

  -- User exists as player or removed — flip to alumni
  IF EXISTS (SELECT 1 FROM dbo.users WHERE id = @UserId)
  BEGIN
    UPDATE dbo.users SET
      status_id           = 2,
      first_name          = @FirstName,
      last_name           = @LastName,
      graduation_year     = @GraduationYear,
      graduation_semester = @GraduationSemester,
      position            = COALESCE(@Position,         position),
      recruiting_class    = COALESCE(@RecruitingClass,  recruiting_class),
      sport_id            = COALESCE(@SportId,          sport_id),
      phone               = COALESCE(@Phone,            phone),
      personal_email      = COALESCE(@PersonalEmail,    personal_email),
      current_employer    = COALESCE(@CurrentEmployer,  current_employer),
      current_job_title   = COALESCE(@CurrentJobTitle,  current_job_title),
      current_city        = COALESCE(@CurrentCity,      current_city),
      current_state       = COALESCE(@CurrentState,     current_state),
      notes               = COALESCE(@Notes,            notes),
      graduated_at        = SYSUTCDATETIME(),
      updated_at          = SYSUTCDATETIME()
    WHERE id = @UserId;
  END
  ELSE
  BEGIN
    -- New user in AppDB — insert directly as alumni
    INSERT INTO dbo.users (
      id, first_name, last_name, status_id,
      graduation_year, graduation_semester,
      position, recruiting_class, sport_id,
      phone, personal_email,
      current_employer, current_job_title, current_city, current_state,
      notes, graduated_at
    )
    VALUES (
      @UserId, @FirstName, @LastName, 2,
      @GraduationYear, @GraduationSemester,
      @Position, @RecruitingClass, @SportId,
      @Phone, @PersonalEmail,
      @CurrentEmployer, @CurrentJobTitle, @CurrentCity, @CurrentState,
      @Notes, SYSUTCDATETIME()
    );
  END

  IF @SportId IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM dbo.users_sports WHERE user_id = @UserId AND sport_id = @SportId)
  BEGIN
    INSERT INTO dbo.users_sports (user_id, sport_id, username)
    VALUES (@UserId, @SportId, @FirstName + ' ' + @LastName);
  END
END;
GO
