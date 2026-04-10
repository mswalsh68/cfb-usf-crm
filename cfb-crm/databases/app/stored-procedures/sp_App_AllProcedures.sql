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
-- vwPlayers
-- All current players (status_id = 1).
-- Used by sp_GetPlayers and future communication procs.
-- RLS on dbo.users applies transparently when queried.
-- ============================================================
CREATE OR ALTER VIEW dbo.vwPlayers AS
SELECT
  u.id,
  u.sport_id,
  u.jersey_number,
  u.first_name,
  u.last_name,
  u.position,
  u.academic_year,
  u.recruiting_class,
  u.height_inches,
  u.weight_lbs,
  u.home_town,
  u.home_state,
  u.high_school,
  u.major,
  u.phone,
  u.personal_email,
  u.instagram,
  u.twitter,
  u.snapchat,
  u.emergency_contact_name,
  u.emergency_contact_phone,
  u.parent1_name,
  u.parent1_phone,
  u.parent1_email,
  u.parent2_name,
  u.parent2_phone,
  u.parent2_email,
  u.notes,
  u.created_at,
  u.updated_at
FROM dbo.users u
WHERE u.status_id = 1;
GO

-- ============================================================
-- vwAlumni
-- All alumni (status_id = 2).
-- Used by sp_GetAlumni and future communication procs.
-- RLS on dbo.users applies transparently when queried.
-- ============================================================
CREATE OR ALTER VIEW dbo.vwAlumni AS
SELECT
  u.id,
  u.sport_id,
  u.first_name,
  u.last_name,
  u.position,
  u.recruiting_class,
  u.graduation_year,
  u.graduation_semester,
  u.graduated_at,
  u.phone,
  u.personal_email,
  u.linkedin_url,
  u.twitter_url,
  u.current_employer,
  u.current_job_title,
  u.current_city,
  u.current_state,
  u.is_donor,
  u.last_donation_date,
  u.total_donations,
  u.engagement_score,
  u.communication_consent,
  u.years_on_roster,
  u.notes,
  u.created_at,
  u.updated_at
FROM dbo.users u
WHERE u.status_id = 2;
GO

-- ============================================================
-- sp_GetPlayers
-- Returns current players from dbo.vwPlayers.
-- Status filtering is handled by the view (status_id = 1).
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
  FROM dbo.vwPlayers p
  WHERE (@Position        IS NULL OR p.position         = @Position)
    AND (@AcademicYear    IS NULL OR p.academic_year    = @AcademicYear)
    AND (@RecruitingClass IS NULL OR p.recruiting_class = @RecruitingClass)
    AND (@SportId         IS NULL OR p.sport_id         = @SportId)
    AND (@Search IS NULL
         OR p.first_name LIKE @SearchWild
         OR p.last_name  LIKE @SearchWild
         OR CAST(p.jersey_number AS NVARCHAR) = @ExactNum);

  SELECT
    p.id,
    p.sport_id              AS sportId,
    p.jersey_number         AS jerseyNumber,
    p.first_name            AS firstName,
    p.last_name             AS lastName,
    p.position,
    p.academic_year         AS academicYear,
    p.height_inches         AS heightInches,
    p.weight_lbs            AS weightLbs,
    p.home_town             AS homeTown,
    p.home_state            AS homeState,
    p.high_school           AS highSchool,
    p.recruiting_class      AS recruitingClass,
    p.major,
    p.phone,
    p.personal_email        AS email,
    p.instagram,
    p.twitter,
    p.snapchat,
    p.emergency_contact_name  AS emergencyContactName,
    p.emergency_contact_phone AS emergencyContactPhone,
    p.notes,
    p.created_at            AS createdAt,
    p.updated_at            AS updatedAt
  FROM dbo.vwPlayers p
  WHERE (@Position        IS NULL OR p.position         = @Position)
    AND (@AcademicYear    IS NULL OR p.academic_year    = @AcademicYear)
    AND (@RecruitingClass IS NULL OR p.recruiting_class = @RecruitingClass)
    AND (@SportId         IS NULL OR p.sport_id         = @SportId)
    AND (@Search IS NULL
         OR p.first_name LIKE @SearchWild
         OR p.last_name  LIKE @SearchWild
         OR CAST(p.jersey_number AS NVARCHAR) = @ExactNum)
  ORDER BY p.last_name, p.first_name
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

  IF NOT EXISTS (SELECT 1 FROM dbo.vwPlayers WHERE id = @UserId)
  BEGIN
    SET @ErrorCode = 'PLAYER_NOT_FOUND';
    RETURN;
  END

  SELECT
    p.id,
    p.sport_id              AS sportId,
    p.jersey_number         AS jerseyNumber,
    p.first_name            AS firstName,
    p.last_name             AS lastName,
    p.position,
    p.academic_year         AS academicYear,
    p.height_inches         AS heightInches,
    p.weight_lbs            AS weightLbs,
    p.home_town             AS homeTown,
    p.home_state            AS homeState,
    p.high_school           AS highSchool,
    p.recruiting_class      AS recruitingClass,
    p.major,
    p.phone,
    p.personal_email        AS email,
    p.instagram,
    p.twitter,
    p.snapchat,
    p.emergency_contact_name  AS emergencyContactName,
    p.emergency_contact_phone AS emergencyContactPhone,
    p.parent1_name            AS parent1Name,
    p.parent1_phone           AS parent1Phone,
    p.parent1_email           AS parent1Email,
    p.parent2_name            AS parent2Name,
    p.parent2_phone           AS parent2Phone,
    p.parent2_email           AS parent2Email,
    p.notes,
    p.created_at            AS createdAt,
    p.updated_at            AS updatedAt
  FROM dbo.vwPlayers p
  WHERE p.id = @UserId;

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
  @Major                 NVARCHAR(100)    = NULL,
  @Phone                 NVARCHAR(20)     = NULL,
  @Instagram             NVARCHAR(100)    = NULL,
  @Twitter               NVARCHAR(100)    = NULL,
  @Snapchat              NVARCHAR(100)    = NULL,
  @EmergencyContactName  NVARCHAR(150)    = NULL,
  @EmergencyContactPhone NVARCHAR(20)     = NULL,
  @Parent1Name           NVARCHAR(150)    = NULL,
  @Parent1Phone          NVARCHAR(20)     = NULL,
  @Parent1Email          NVARCHAR(255)    = NULL,
  @Parent2Name           NVARCHAR(150)    = NULL,
  @Parent2Phone          NVARCHAR(20)     = NULL,
  @Parent2Email          NVARCHAR(255)    = NULL,
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
      major                   = COALESCE(@Major,                  major),
      phone                   = COALESCE(@Phone,                  phone),
      personal_email          = COALESCE(@Email,                  personal_email),
      instagram               = COALESCE(@Instagram,              instagram),
      twitter                 = COALESCE(@Twitter,                twitter),
      snapchat                = COALESCE(@Snapchat,               snapchat),
      emergency_contact_name  = COALESCE(@EmergencyContactName,  emergency_contact_name),
      emergency_contact_phone = COALESCE(@EmergencyContactPhone, emergency_contact_phone),
      parent1_name            = COALESCE(@Parent1Name,            parent1_name),
      parent1_phone           = COALESCE(@Parent1Phone,           parent1_phone),
      parent1_email           = COALESCE(@Parent1Email,           parent1_email),
      parent2_name            = COALESCE(@Parent2Name,            parent2_name),
      parent2_phone           = COALESCE(@Parent2Phone,           parent2_phone),
      parent2_email           = COALESCE(@Parent2Email,           parent2_email),
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
      major, phone, personal_email, instagram, twitter, snapchat,
      emergency_contact_name, emergency_contact_phone,
      parent1_name, parent1_phone, parent1_email,
      parent2_name, parent2_phone, parent2_email,
      notes
    )
    VALUES (
      @NewUserId, @Email, @FirstName, @LastName, 1, @SportId,
      @JerseyNumber, @Position, @AcademicYear, @RecruitingClass,
      @HeightInches, @WeightLbs, @HomeTown, @HomeState, @HighSchool,
      @Major, @Phone, @Email, @Instagram, @Twitter, @Snapchat,
      @EmergencyContactName, @EmergencyContactPhone,
      @Parent1Name, @Parent1Phone, @Parent1Email,
      @Parent2Name, @Parent2Phone, @Parent2Email,
      @Notes
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
  @Major                 NVARCHAR(100)    = NULL,
  @Phone                 NVARCHAR(20)     = NULL,
  @Email                 NVARCHAR(255)    = NULL,
  @Instagram             NVARCHAR(100)    = NULL,
  @Twitter               NVARCHAR(100)    = NULL,
  @Snapchat              NVARCHAR(100)    = NULL,
  @EmergencyContactName  NVARCHAR(150)    = NULL,
  @EmergencyContactPhone NVARCHAR(20)     = NULL,
  @Parent1Name           NVARCHAR(150)    = NULL,
  @Parent1Phone          NVARCHAR(20)     = NULL,
  @Parent1Email          NVARCHAR(255)    = NULL,
  @Parent2Name           NVARCHAR(150)    = NULL,
  @Parent2Phone          NVARCHAR(20)     = NULL,
  @Parent2Email          NVARCHAR(255)    = NULL,
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
    major                   = COALESCE(@Major,                 major),
    phone                   = COALESCE(@Phone,                 phone),
    personal_email          = COALESCE(@Email,                 personal_email),
    instagram               = COALESCE(@Instagram,             instagram),
    twitter                 = COALESCE(@Twitter,               twitter),
    snapchat                = COALESCE(@Snapchat,              snapchat),
    emergency_contact_name  = COALESCE(@EmergencyContactName,  emergency_contact_name),
    emergency_contact_phone = COALESCE(@EmergencyContactPhone, emergency_contact_phone),
    parent1_name            = COALESCE(@Parent1Name,           parent1_name),
    parent1_phone           = COALESCE(@Parent1Phone,          parent1_phone),
    parent1_email           = COALESCE(@Parent1Email,          parent1_email),
    parent2_name            = COALESCE(@Parent2Name,           parent2_name),
    parent2_phone           = COALESCE(@Parent2Phone,          parent2_phone),
    parent2_email           = COALESCE(@Parent2Email,          parent2_email),
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
-- Returns alumni from dbo.vwAlumni.
-- Status filtering is handled by the view (status_id = 2).
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
  FROM dbo.vwAlumni a
  WHERE (@IsDonor  IS NULL OR a.is_donor        = @IsDonor)
    AND (@GradYear IS NULL OR a.graduation_year = @GradYear)
    AND (@Position IS NULL OR a.position        = @Position)
    AND (@SportId  IS NULL OR a.sport_id        = @SportId)
    AND (@Search IS NULL
         OR a.first_name       LIKE @SearchWild
         OR a.last_name        LIKE @SearchWild
         OR a.current_employer LIKE @SearchWild
         OR a.current_city     LIKE @SearchWild
         OR a.personal_email   LIKE @SearchWild);

  SELECT
    a.id,
    a.sport_id              AS sportId,
    a.first_name            AS firstName,
    a.last_name             AS lastName,
    a.graduation_year       AS graduationYear,
    a.graduation_semester   AS graduationSemester,
    a.position,
    a.recruiting_class      AS recruitingClass,
    a.personal_email        AS personalEmail,
    a.phone,
    a.linkedin_url          AS linkedInUrl,
    a.twitter_url           AS twitterUrl,
    a.current_employer      AS currentEmployer,
    a.current_job_title     AS currentJobTitle,
    a.current_city          AS currentCity,
    a.current_state         AS currentState,
    a.is_donor              AS isDonor,
    a.last_donation_date    AS lastDonationDate,
    a.total_donations       AS totalDonations,
    a.engagement_score      AS engagementScore,
    a.notes,
    a.created_at            AS createdAt,
    a.updated_at            AS updatedAt
  FROM dbo.vwAlumni a
  WHERE (@IsDonor  IS NULL OR a.is_donor        = @IsDonor)
    AND (@GradYear IS NULL OR a.graduation_year = @GradYear)
    AND (@Position IS NULL OR a.position        = @Position)
    AND (@SportId  IS NULL OR a.sport_id        = @SportId)
    AND (@Search IS NULL
         OR a.first_name       LIKE @SearchWild
         OR a.last_name        LIKE @SearchWild
         OR a.current_employer LIKE @SearchWild
         OR a.current_city     LIKE @SearchWild
         OR a.personal_email   LIKE @SearchWild)
  ORDER BY a.last_name, a.first_name
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

  IF NOT EXISTS (SELECT 1 FROM dbo.vwAlumni WHERE id = @UserId)
  BEGIN
    SET @ErrorCode = 'ALUMNI_NOT_FOUND';
    RETURN;
  END

  SELECT
    a.id,
    a.sport_id              AS sportId,
    a.first_name            AS firstName,
    a.last_name             AS lastName,
    a.graduation_year       AS graduationYear,
    a.graduation_semester   AS graduationSemester,
    a.position,
    a.recruiting_class      AS recruitingClass,
    a.personal_email        AS personalEmail,
    a.phone,
    a.linkedin_url          AS linkedInUrl,
    a.twitter_url           AS twitterUrl,
    a.current_employer      AS currentEmployer,
    a.current_job_title     AS currentJobTitle,
    a.current_city          AS currentCity,
    a.current_state         AS currentState,
    a.is_donor              AS isDonor,
    a.last_donation_date    AS lastDonationDate,
    a.total_donations       AS totalDonations,
    a.engagement_score      AS engagementScore,
    a.communication_consent AS communicationConsent,
    a.years_on_roster       AS yearsOnRoster,
    a.notes,
    a.created_at            AS createdAt,
    a.updated_at            AS updatedAt
  FROM dbo.vwAlumni a
  WHERE a.id = @UserId;

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
  @TargetAudience  NVARCHAR(30),
  @AudienceFilters NVARCHAR(MAX)    = NULL,
  @ScheduledAt     DATETIME2        = NULL,
  @CreatedBy       UNIQUEIDENTIFIER,
  @SportId         UNIQUEIDENTIFIER = NULL,
  @SubjectLine     NVARCHAR(500)    = NULL,
  @BodyHtml        NVARCHAR(MAX)    = NULL,
  @FromName        NVARCHAR(200)    = NULL,
  @ReplyToEmail    NVARCHAR(255)    = NULL,
  @PhysicalAddress NVARCHAR(500)    = NULL,
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
  IF @TargetAudience NOT IN ('all','players_only','alumni_only','byClass','byPosition','byGradYear','custom')
    BEGIN SET @ErrorCode = 'INVALID_TARGET_AUDIENCE'; RETURN; END
  IF @TargetAudience = 'custom' AND (@AudienceFilters IS NULL OR LEN(@AudienceFilters) < 2)
    BEGIN SET @ErrorCode = 'CUSTOM_AUDIENCE_REQUIRES_FILTERS'; RETURN; END
  IF @ScheduledAt IS NOT NULL AND @ScheduledAt < SYSUTCDATETIME()
    BEGIN SET @ErrorCode = 'SCHEDULED_DATE_IN_PAST'; RETURN; END

  SET @NewCampaignId = NEWID();

  INSERT INTO dbo.outreach_campaigns (
    id, sport_id, name, description, target_audience, audience_filters,
    scheduled_at, subject_line, body_html, from_name, reply_to_email,
    physical_address, created_by
  )
  VALUES (
    @NewCampaignId, @SportId, @Name, @Description, @TargetAudience, @AudienceFilters,
    @ScheduledAt, @SubjectLine, @BodyHtml, @FromName, @ReplyToEmail,
    @PhysicalAddress, @CreatedBy
  );
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
      FROM dbo.vwAlumni
      WHERE (@SportId IS NULL OR sport_id = @SportId)
      GROUP BY graduation_year
      ORDER BY graduation_year DESC
      FOR JSON PATH
    ) AS classCounts
  FROM dbo.vwAlumni
  WHERE (@SportId IS NULL OR sport_id = @SportId);
END;
GO

-- ============================================================
-- sp_ResolveAudienceForCampaign
-- Resolves recipients for a campaign, using vwPlayers and
-- vwAlumni views as the authoritative audience source.
-- Audience types: all, players_only, alumni_only, byClass,
--   byPosition, byGradYear, custom
-- Returns opt-out status so callers can suppress unsubscribes.
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

  DECLARE @Audience    NVARCHAR(30);
  DECLARE @FiltersJson NVARCHAR(MAX);

  SELECT @Audience = target_audience, @FiltersJson = audience_filters
  FROM dbo.outreach_campaigns
  WHERE id = @CampaignId;

  IF @Audience IS NULL BEGIN SET @ErrorCode = 'CAMPAIGN_NOT_FOUND'; RETURN; END

  DECLARE @FilterGradYear  SMALLINT     = TRY_CAST(JSON_VALUE(@FiltersJson, '$.gradYear')  AS SMALLINT);
  DECLARE @FilterPosition  NVARCHAR(10) = JSON_VALUE(@FiltersJson, '$.position');
  DECLARE @FilterGradYears NVARCHAR(MAX)= JSON_QUERY(@FiltersJson,  '$.gradYears');
  DECLARE @FilterPositions NVARCHAR(MAX)= JSON_QUERY(@FiltersJson,  '$.positions');

  SELECT
    u.id              AS userId,
    u.first_name      AS firstName,
    u.last_name       AS lastName,
    u.personal_email  AS personalEmail,
    u.phone,
    u.status_id       AS statusId,
    CASE WHEN eu.id IS NOT NULL THEN 1 ELSE 0 END AS isUnsubscribed
  FROM dbo.users u
  LEFT JOIN dbo.email_unsubscribes eu ON eu.user_id = u.id AND eu.channel = 'email'
  WHERE u.status_id IN (1, 2)
    AND u.personal_email IS NOT NULL
    AND (
      -- all: both players and alumni
      @Audience = 'all'

      -- players only
      OR (@Audience = 'players_only'
          AND u.status_id = 1)

      -- alumni only
      OR (@Audience = 'alumni_only'
          AND u.status_id = 2)

      -- by graduation year (alumni)
      OR (@Audience = 'byGradYear'
          AND u.status_id = 2
          AND (
            @FilterGradYear IS NOT NULL AND u.graduation_year = @FilterGradYear
            OR @FilterGradYears IS NOT NULL AND EXISTS (
              SELECT 1 FROM OPENJSON(@FilterGradYears)
              WHERE CAST([value] AS SMALLINT) = u.graduation_year
            )
          ))

      -- by recruiting class (players)
      OR (@Audience = 'byClass'
          AND u.status_id = 1
          AND u.recruiting_class = @FilterGradYear)

      -- by position (players and alumni)
      OR (@Audience = 'byPosition'
          AND (
            @FilterPosition IS NOT NULL AND u.position = @FilterPosition
            OR @FilterPositions IS NOT NULL AND EXISTS (
              SELECT 1 FROM OPENJSON(@FilterPositions)
              WHERE CAST([value] AS NVARCHAR(10)) = u.position
            )
          ))

      -- custom: AND-chain any provided filters
      OR (@Audience = 'custom'
          AND (@FilterGradYear  IS NULL OR u.graduation_year = @FilterGradYear)
          AND (@FilterPosition  IS NULL OR u.position        = @FilterPosition))
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
    provided_user_id         UNIQUEIDENTIFIER,
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
    major                    NVARCHAR(100),
    phone                    NVARCHAR(20),
    emergency_contact_name   NVARCHAR(150),
    emergency_contact_phone  NVARCHAR(20),
    parent1_name             NVARCHAR(150),
    parent1_phone            NVARCHAR(20),
    parent1_email            NVARCHAR(255),
    parent2_name             NVARCHAR(150),
    parent2_phone            NVARCHAR(20),
    parent2_email            NVARCHAR(255),
    notes                    NVARCHAR(MAX)
  );

  INSERT INTO @rows (
    row_num, provided_user_id, email, first_name, last_name,
    jersey_number, position, academic_year, recruiting_class,
    height_inches, weight_lbs, home_town, home_state, high_school,
    major, phone, emergency_contact_name, emergency_contact_phone,
    parent1_name, parent1_phone, parent1_email,
    parent2_name, parent2_phone, parent2_email,
    notes
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    TRY_CAST(JSON_VALUE(value, '$.userId')         AS UNIQUEIDENTIFIER),
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
    JSON_VALUE(value, '$.major'),
    JSON_VALUE(value, '$.phone'),
    JSON_VALUE(value, '$.emergencyContactName'),
    JSON_VALUE(value, '$.emergencyContactPhone'),
    JSON_VALUE(value, '$.parent1Name'),
    JSON_VALUE(value, '$.parent1Phone'),
    JSON_VALUE(value, '$.parent1Email'),
    JSON_VALUE(value, '$.parent2Name'),
    JSON_VALUE(value, '$.parent2Phone'),
    JSON_VALUE(value, '$.parent2Email'),
    JSON_VALUE(value, '$.notes')
  FROM OPENJSON(@PlayersJson);

  DECLARE @rowNum          INT;
  DECLARE @providedUserId  UNIQUEIDENTIFIER;
  DECLARE @email           NVARCHAR(255);
  DECLARE @fn              NVARCHAR(100);
  DECLARE @ln              NVARCHAR(100);
  DECLARE @jersey          TINYINT;
  DECLARE @pos             NVARCHAR(10);
  DECLARE @acYear          NVARCHAR(20);
  DECLARE @recClass        SMALLINT;
  DECLARE @heightIn        TINYINT;
  DECLARE @wt              SMALLINT;
  DECLARE @town            NVARCHAR(100);
  DECLARE @state           NVARCHAR(50);
  DECLARE @hs              NVARCHAR(150);
  DECLARE @major           NVARCHAR(100);
  DECLARE @phone           NVARCHAR(20);
  DECLARE @ecName          NVARCHAR(150);
  DECLARE @ecPhone         NVARCHAR(20);
  DECLARE @parent1Name     NVARCHAR(150);
  DECLARE @parent1Phone    NVARCHAR(20);
  DECLARE @parent1Email    NVARCHAR(255);
  DECLARE @parent2Name     NVARCHAR(150);
  DECLARE @parent2Phone    NVARCHAR(20);
  DECLARE @parent2Email    NVARCHAR(255);
  DECLARE @notes           NVARCHAR(MAX);

  DECLARE cur CURSOR FOR
    SELECT row_num, provided_user_id, email, first_name, last_name,
           jersey_number, position, academic_year, recruiting_class,
           height_inches, weight_lbs, home_town, home_state, high_school,
           major, phone, emergency_contact_name, emergency_contact_phone,
           parent1_name, parent1_phone, parent1_email,
           parent2_name, parent2_phone, parent2_email,
           notes
    FROM @rows;

  OPEN cur;
  FETCH NEXT FROM cur INTO
    @rowNum, @providedUserId, @email, @fn, @ln, @jersey, @pos, @acYear, @recClass,
    @heightIn, @wt, @town, @state, @hs,
    @major, @phone, @ecName, @ecPhone,
    @parent1Name, @parent1Phone, @parent1Email,
    @parent2Name, @parent2Phone, @parent2Email,
    @notes;

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

      -- Get or create global user.
      -- If email is NULL: skip GlobalDB and use the provided userId or generate one.
      DECLARE @newUserId UNIQUEIDENTIFIER;
      DECLARE @globalErr NVARCHAR(50);

      IF @email IS NOT NULL AND LEN(LTRIM(RTRIM(@email))) > 0
      BEGIN
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
      END
      ELSE
      BEGIN
        -- No email supplied — use provided userId or generate a new one.
        -- User can log in once email is added later via update.
        SET @newUserId = ISNULL(@providedUserId, NEWID());
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
          high_school             = COALESCE(@hs,            high_school),
          major                   = COALESCE(@major,         major),
          phone                   = COALESCE(@phone,         phone),
          emergency_contact_name  = COALESCE(@ecName,        emergency_contact_name),
          emergency_contact_phone = COALESCE(@ecPhone,       emergency_contact_phone),
          parent1_name            = COALESCE(@parent1Name,   parent1_name),
          parent1_phone           = COALESCE(@parent1Phone,  parent1_phone),
          parent1_email           = COALESCE(@parent1Email,  parent1_email),
          parent2_name            = COALESCE(@parent2Name,   parent2_name),
          parent2_phone           = COALESCE(@parent2Phone,  parent2_phone),
          parent2_email           = COALESCE(@parent2Email,  parent2_email),
          notes                   = COALESCE(@notes,         notes),
          updated_at              = SYSUTCDATETIME()
        WHERE id = @newUserId;
      END
      ELSE
      BEGIN
        INSERT INTO dbo.users (
          id, email, first_name, last_name, status_id, sport_id,
          jersey_number, position, academic_year, recruiting_class,
          height_inches, weight_lbs, home_town, home_state, high_school,
          major, phone, emergency_contact_name, emergency_contact_phone,
          parent1_name, parent1_phone, parent1_email,
          parent2_name, parent2_phone, parent2_email,
          notes
        )
        VALUES (
          @newUserId,
          ISNULL(@email, 'provisional-' + LOWER(CAST(@newUserId AS NVARCHAR(36))) + '@import.local'),
          @fn, @ln, 1, @SportId,
          @jersey, @pos, @acYear, @recClass,
          @heightIn, @wt, @town, @state, @hs,
          @major, @phone, @ecName, @ecPhone,
          @parent1Name, @parent1Phone, @parent1Email,
          @parent2Name, @parent2Phone, @parent2Email,
          @notes
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
      @rowNum, @providedUserId, @email, @fn, @ln, @jersey, @pos, @acYear, @recClass,
      @heightIn, @wt, @town, @state, @hs,
      @major, @phone, @ecName, @ecPhone,
      @parent1Name, @parent1Phone, @parent1Email,
      @parent2Name, @parent2Phone, @parent2Email,
      @notes;
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
    provided_user_id    UNIQUEIDENTIFIER,
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
    row_num, provided_user_id, email, first_name, last_name,
    graduation_year, graduation_semester,
    phone, linkedin_url,
    current_employer, current_job_title, current_city, current_state,
    is_donor, notes
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    TRY_CAST(JSON_VALUE(value, '$.userId')           AS UNIQUEIDENTIFIER),
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

  DECLARE @rowNum          INT;
  DECLARE @providedUserId  UNIQUEIDENTIFIER;
  DECLARE @email           NVARCHAR(255);
  DECLARE @fn              NVARCHAR(100);
  DECLARE @ln              NVARCHAR(100);
  DECLARE @gradYear        SMALLINT;
  DECLARE @semester        NVARCHAR(10);
  DECLARE @phone           NVARCHAR(20);
  DECLARE @linkedin        NVARCHAR(500);
  DECLARE @employer        NVARCHAR(200);
  DECLARE @jobTitle        NVARCHAR(150);
  DECLARE @city            NVARCHAR(100);
  DECLARE @state           NVARCHAR(50);
  DECLARE @isDonor         BIT;
  DECLARE @notes           NVARCHAR(MAX);

  DECLARE cur CURSOR FOR
    SELECT row_num, provided_user_id, email, first_name, last_name,
           graduation_year, graduation_semester,
           phone, linkedin_url,
           current_employer, current_job_title, current_city, current_state,
           is_donor, notes
    FROM @rows;

  OPEN cur;
  FETCH NEXT FROM cur INTO
    @rowNum, @providedUserId, @email, @fn, @ln, @gradYear, @semester,
    @phone, @linkedin, @employer, @jobTitle, @city, @state, @isDonor, @notes;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      IF @fn IS NULL OR LEN(LTRIM(RTRIM(@fn))) = 0 BEGIN INSERT INTO @errors VALUES (@rowNum, 'First name required'); SET @SkippedCount += 1; GOTO NextAlumRow; END
      IF @ln IS NULL OR LEN(LTRIM(RTRIM(@ln))) = 0 BEGIN INSERT INTO @errors VALUES (@rowNum, 'Last name required');  SET @SkippedCount += 1; GOTO NextAlumRow; END
      IF @gradYear IS NULL OR @gradYear < 1950 OR @gradYear > 2100 BEGIN INSERT INTO @errors VALUES (@rowNum, 'Invalid graduation year'); SET @SkippedCount += 1; GOTO NextAlumRow; END

      DECLARE @newUserId UNIQUEIDENTIFIER;
      DECLARE @globalErr NVARCHAR(50);

      IF @email IS NOT NULL AND LEN(LTRIM(RTRIM(@email))) > 0
      BEGIN
        EXEC [GLOBAL_DB].LegacyLinkGlobal.dbo.sp_GetOrCreateUser
          @Email = @email, @FirstName = @fn, @LastName = @ln, @TeamId = @GlobalTeamId,
          @UserId = @newUserId OUTPUT, @ErrorCode = @globalErr OUTPUT;

        IF @newUserId IS NULL BEGIN INSERT INTO @errors VALUES (@rowNum, 'Global user creation failed: ' + ISNULL(@globalErr, 'unknown')); SET @SkippedCount += 1; GOTO NextAlumRow; END
      END
      ELSE
      BEGIN
        SET @newUserId = ISNULL(@providedUserId, NEWID());
      END

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
      @rowNum, @providedUserId, @email, @fn, @ln, @gradYear, @semester,
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

-- ============================================================
-- sp_GetSports
-- Returns all active sports in this AppDB.
-- Used by the web/mobile sport-selector dropdowns.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetSports
AS
BEGIN
  SET NOCOUNT ON;
  SELECT id, name, abbr, is_active AS isActive
  FROM   dbo.sports
  WHERE  is_active = 1
  ORDER  BY name;
END;
GO

-- ============================================================
-- sp_DispatchEmailCampaign
-- Queues outreach_messages for all eligible (non-unsubscribed)
-- recipients and marks the campaign as active.
-- Send-limit enforcement: caller passes remaining headroom
-- (read from GlobalDB team_config before calling this SP).
-- Returns queued messages for the API to hand to email provider.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_DispatchEmailCampaign
  @CampaignId       UNIQUEIDENTIFIER,
  @DailyRemaining   INT,
  @MonthlyRemaining INT,
  @QueuedCount      INT OUTPUT,
  @ErrorCode        NVARCHAR(50) OUTPUT,
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
  SET @ErrorCode   = NULL;
  SET @QueuedCount = 0;

  -- Validate campaign
  DECLARE @CampaignStatus NVARCHAR(20);
  DECLARE @Audience       NVARCHAR(30);
  DECLARE @FiltersJson    NVARCHAR(MAX);
  DECLARE @BodyHtml       NVARCHAR(MAX);
  DECLARE @SubjectLine    NVARCHAR(500);

  SELECT
    @CampaignStatus = status,
    @Audience       = target_audience,
    @FiltersJson    = audience_filters,
    @BodyHtml       = body_html,
    @SubjectLine    = subject_line
  FROM dbo.outreach_campaigns
  WHERE id = @CampaignId;

  IF @CampaignStatus IS NULL BEGIN SET @ErrorCode = 'CAMPAIGN_NOT_FOUND'; RETURN; END
  IF @CampaignStatus NOT IN ('draft', 'scheduled') BEGIN SET @ErrorCode = 'INVALID_CAMPAIGN_STATUS'; RETURN; END

  -- Build recipient list: resolve audience inline using same logic as sp_ResolveAudienceForCampaign
  DECLARE @FilterGradYear  SMALLINT     = TRY_CAST(JSON_VALUE(@FiltersJson, '$.gradYear')  AS SMALLINT);
  DECLARE @FilterPosition  NVARCHAR(10) = JSON_VALUE(@FiltersJson, '$.position');
  DECLARE @FilterGradYears NVARCHAR(MAX)= JSON_QUERY(@FiltersJson, '$.gradYears');
  DECLARE @FilterPositions NVARCHAR(MAX)= JSON_QUERY(@FiltersJson, '$.positions');

  -- Collect eligible recipients into temp table
  SELECT
    u.id              AS userId,
    u.personal_email  AS emailAddress,
    u.first_name      AS firstName,
    NEWID()           AS unsubToken
  INTO #recipients
  FROM dbo.users u
  LEFT JOIN dbo.email_unsubscribes eu ON eu.user_id = u.id AND eu.channel = 'email'
  WHERE u.status_id IN (1, 2)
    AND u.personal_email IS NOT NULL
    AND eu.id IS NULL   -- exclude unsubscribed
    AND NOT EXISTS (
      SELECT 1 FROM dbo.outreach_messages om
      WHERE om.campaign_id = @CampaignId AND om.user_id = u.id
    )
    AND (
      @Audience = 'all'
      OR (@Audience = 'players_only' AND u.status_id = 1)
      OR (@Audience = 'alumni_only'  AND u.status_id = 2)
      OR (@Audience = 'byGradYear'   AND u.status_id = 2 AND (
            (@FilterGradYear IS NOT NULL AND u.graduation_year = @FilterGradYear)
            OR (@FilterGradYears IS NOT NULL AND EXISTS (
              SELECT 1 FROM OPENJSON(@FilterGradYears) WHERE CAST([value] AS SMALLINT) = u.graduation_year
            ))
          ))
      OR (@Audience = 'byClass'    AND u.status_id = 1 AND u.recruiting_class = @FilterGradYear)
      OR (@Audience = 'byPosition' AND (
            (@FilterPosition IS NOT NULL AND u.position = @FilterPosition)
            OR (@FilterPositions IS NOT NULL AND EXISTS (
              SELECT 1 FROM OPENJSON(@FilterPositions) WHERE CAST([value] AS NVARCHAR(10)) = u.position
            ))
          ))
      OR (@Audience = 'custom'
          AND (@FilterGradYear IS NULL OR u.graduation_year = @FilterGradYear)
          AND (@FilterPosition IS NULL OR u.position        = @FilterPosition))
    );

  SET @QueuedCount = (SELECT COUNT(*) FROM #recipients);

  IF @QueuedCount = 0 BEGIN SET @ErrorCode = 'NO_ELIGIBLE_RECIPIENTS'; DROP TABLE #recipients; RETURN; END
  IF @QueuedCount > @DailyRemaining   BEGIN SET @ErrorCode = 'DAILY_LIMIT_EXCEEDED';   DROP TABLE #recipients; RETURN; END
  IF @QueuedCount > @MonthlyRemaining BEGIN SET @ErrorCode = 'MONTHLY_LIMIT_EXCEEDED'; DROP TABLE #recipients; RETURN; END

  -- Insert queued messages
  INSERT INTO dbo.outreach_messages (campaign_id, user_id, channel, status, email_address, unsubscribe_token)
  SELECT
    @CampaignId,
    r.userId,
    'email',
    'queued',
    r.emailAddress,
    r.unsubToken
  FROM #recipients r;

  -- Mark campaign active
  UPDATE dbo.outreach_campaigns
  SET status = 'active', started_at = SYSUTCDATETIME(), updated_at = SYSUTCDATETIME()
  WHERE id = @CampaignId;

  -- Return queued messages for API to dispatch to email provider
  SELECT
    om.id                AS messageId,
    om.user_id           AS userId,
    r.firstName,
    om.email_address     AS emailAddress,
    om.unsubscribe_token AS unsubscribeToken
  FROM dbo.outreach_messages om
  JOIN #recipients r ON r.userId = om.user_id
  WHERE om.campaign_id = @CampaignId AND om.status = 'queued';

  DROP TABLE #recipients;
END;
GO

-- ============================================================
-- sp_MarkEmailSent
-- Called by API after provider confirms delivery.
-- Accepts JSON array of message IDs for bulk marking.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_MarkEmailSent
  @MessageIdsJson NVARCHAR(MAX),
  @ErrorCode      NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  UPDATE om
  SET    om.status  = 'sent',
         om.sent_at = SYSUTCDATETIME()
  FROM   dbo.outreach_messages om
  JOIN   OPENJSON(@MessageIdsJson) j ON CAST(j.[value] AS UNIQUEIDENTIFIER) = om.id
  WHERE  om.status = 'queued';

  -- Mark campaign completed if all messages sent
  UPDATE oc
  SET    oc.status       = 'completed',
         oc.completed_at = SYSUTCDATETIME(),
         oc.updated_at   = SYSUTCDATETIME()
  FROM   dbo.outreach_campaigns oc
  WHERE  oc.status = 'active'
    AND NOT EXISTS (
      SELECT 1 FROM dbo.outreach_messages om2
      WHERE om2.campaign_id = oc.id AND om2.status = 'queued'
    );
END;
GO

-- ============================================================
-- sp_MarkEmailOpened
-- Called via tracking-pixel webhook. Uses unsubscribe_token
-- as the identifier (safe to expose in img src URL hash).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_MarkEmailOpened
  @MessageId UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.outreach_messages WHERE id = @MessageId)
  BEGIN
    SET @ErrorCode = 'MESSAGE_NOT_FOUND';
    RETURN;
  END

  UPDATE dbo.outreach_messages
  SET opened_at = ISNULL(opened_at, SYSUTCDATETIME()),
      status    = CASE WHEN status = 'sent' THEN 'responded' ELSE status END
  WHERE id = @MessageId;
END;
GO

-- ============================================================
-- sp_ProcessUnsubscribe
-- Called when recipient clicks the unsubscribe link.
-- Token is from outreach_messages.unsubscribe_token.
-- No auth required — public endpoint.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ProcessUnsubscribe
  @Token     UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  DECLARE @UserId UNIQUEIDENTIFIER;
  SELECT @UserId = user_id
  FROM   dbo.outreach_messages
  WHERE  unsubscribe_token = @Token;

  IF @UserId IS NULL
  BEGIN
    SET @ErrorCode = 'INVALID_TOKEN';
    RETURN;
  END

  -- Idempotent upsert
  IF NOT EXISTS (
    SELECT 1 FROM dbo.email_unsubscribes
    WHERE user_id = @UserId AND channel = 'email'
  )
  BEGIN
    INSERT INTO dbo.email_unsubscribes (user_id, token, channel)
    VALUES (@UserId, NEWID(), 'email');
  END

  -- Return team info so the web page can display branded confirmation
  SELECT u.first_name AS firstName
  FROM   dbo.users u
  WHERE  u.id = @UserId;
END;
GO

-- ============================================================
-- sp_GetCampaignDetail
-- Returns a single campaign with aggregated send stats.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetCampaignDetail
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

  IF NOT EXISTS (SELECT 1 FROM dbo.outreach_campaigns WHERE id = @CampaignId)
  BEGIN
    SET @ErrorCode = 'CAMPAIGN_NOT_FOUND';
    RETURN;
  END

  SELECT
    oc.id,
    oc.name,
    oc.description,
    oc.target_audience  AS targetAudience,
    oc.audience_filters AS audienceFilters,
    oc.status,
    oc.campaign_type    AS campaignType,
    oc.subject_line     AS subjectLine,
    oc.scheduled_at     AS scheduledAt,
    oc.started_at       AS startedAt,
    oc.completed_at     AS completedAt,
    oc.created_at       AS createdAt,
    -- Stats
    SUM(CASE WHEN om.status IN ('queued','sent','responded') THEN 1 ELSE 0 END) AS totalQueued,
    SUM(CASE WHEN om.status IN ('sent','responded')          THEN 1 ELSE 0 END) AS totalSent,
    SUM(CASE WHEN om.opened_at IS NOT NULL                   THEN 1 ELSE 0 END) AS totalOpened,
    (
      SELECT COUNT(*) FROM dbo.email_unsubscribes eu2
      JOIN dbo.outreach_messages om2 ON om2.user_id = eu2.user_id
      WHERE om2.campaign_id = oc.id
    ) AS unsubscribeCount,
    CASE
      WHEN SUM(CASE WHEN om.status IN ('sent','responded') THEN 1 ELSE 0 END) = 0 THEN 0
      ELSE CAST(
        100.0 * SUM(CASE WHEN om.opened_at IS NOT NULL THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN om.status IN ('sent','responded') THEN 1 ELSE 0 END), 0)
      AS DECIMAL(5,1))
    END AS openRatePct
  FROM dbo.outreach_campaigns oc
  LEFT JOIN dbo.outreach_messages om ON om.campaign_id = oc.id
  WHERE oc.id = @CampaignId
  GROUP BY
    oc.id, oc.name, oc.description, oc.target_audience, oc.audience_filters,
    oc.status, oc.campaign_type, oc.subject_line, oc.scheduled_at,
    oc.started_at, oc.completed_at, oc.created_at;
END;
GO

-- ============================================================
-- sp_CancelCampaign
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CancelCampaign
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

  DECLARE @CurStatus NVARCHAR(20);
  SELECT @CurStatus = status FROM dbo.outreach_campaigns WHERE id = @CampaignId;

  IF @CurStatus IS NULL BEGIN SET @ErrorCode = 'CAMPAIGN_NOT_FOUND'; RETURN; END
  IF @CurStatus NOT IN ('draft','scheduled') BEGIN SET @ErrorCode = 'CANNOT_CANCEL'; RETURN; END

  UPDATE dbo.outreach_campaigns
  SET status = 'cancelled', updated_at = SYSUTCDATETIME()
  WHERE id = @CampaignId;
END;
GO

-- ============================================================
-- sp_CreatePost
-- Creates a feed post. If @AlsoEmail = 1, also creates a
-- draft outreach_campaign so the API can dispatch it.
-- Single source of truth for post + email pairing.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreatePost
  @CreatedBy    UNIQUEIDENTIFIER,
  @BodyHtml     NVARCHAR(MAX),
  @Audience     NVARCHAR(30),
  @Title        NVARCHAR(300)    = NULL,
  @AudienceJson NVARCHAR(MAX)    = NULL,
  @SportId      UNIQUEIDENTIFIER = NULL,
  @IsPinned     BIT              = 0,
  @AlsoEmail    BIT              = 0,
  @EmailSubject NVARCHAR(500)    = NULL,
  @NewPostId    UNIQUEIDENTIFIER OUTPUT,
  @CampaignId   UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode    NVARCHAR(50)     OUTPUT,
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
  SET @ErrorCode  = NULL;
  SET @NewPostId  = NULL;
  SET @CampaignId = NULL;

  IF @Audience NOT IN ('all','players_only','alumni_only','by_position','by_grad_year','custom')
  BEGIN
    SET @ErrorCode = 'INVALID_AUDIENCE';
    RETURN;
  END

  IF @AlsoEmail = 1 AND @EmailSubject IS NULL
  BEGIN
    SET @ErrorCode = 'EMAIL_SUBJECT_REQUIRED';
    RETURN;
  END

  SET @NewPostId = NEWID();

  INSERT INTO dbo.feed_posts (
    id, created_by, title, body_html, audience, audience_json,
    sport_id, is_pinned, published_at
  )
  VALUES (
    @NewPostId, @CreatedBy, @Title, @BodyHtml, @Audience, @AudienceJson,
    @SportId, ISNULL(@IsPinned, 0), SYSUTCDATETIME()
  );

  -- Map post audience → campaign audience value
  -- feed uses 'by_position'/'by_grad_year'; campaigns use 'byPosition'/'byGradYear'
  DECLARE @CampaignAudience NVARCHAR(30) = CASE @Audience
    WHEN 'by_position' THEN 'byPosition'
    WHEN 'by_grad_year' THEN 'byGradYear'
    ELSE @Audience
  END;

  IF @AlsoEmail = 1
  BEGIN
    SET @CampaignId = NEWID();
    INSERT INTO dbo.outreach_campaigns (
      id, name, description, target_audience, audience_filters,
      status, campaign_type, subject_line, body_html, sport_id, created_by
    )
    VALUES (
      @CampaignId,
      ISNULL(@Title, LEFT(@BodyHtml, 100)),
      N'Auto-created from feed post',
      @CampaignAudience,
      @AudienceJson,
      'draft',
      'post_notification',
      @EmailSubject,
      @BodyHtml,
      @SportId,
      @CreatedBy
    );

    -- Link campaign back to post
    UPDATE dbo.feed_posts SET campaign_id = @CampaignId WHERE id = @NewPostId;
  END
END;
GO

-- ============================================================
-- sp_GetFeed
-- Returns feed posts visible to the requesting user.
-- Audience wall is enforced at the DB layer — viewer status_id
-- is resolved from dbo.users, never trusted from the caller.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetFeed
  @ViewerUserId UNIQUEIDENTIFIER,
  @SportId      UNIQUEIDENTIFIER = NULL,
  @Page         INT              = 1,
  @PageSize     INT              = 20,
  @TotalCount   INT              OUTPUT,
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
  SET @TotalCount = 0;

  -- Resolve viewer status from DB — never trust a caller-supplied value
  DECLARE @ViewerStatusId INT;
  SELECT @ViewerStatusId = status_id FROM dbo.users WHERE id = @ViewerUserId;
  -- NULL status means staff/admin (no users row in AppDB) — sees all posts
  -- statusId = 0 is treated as admin for visibility purposes

  DECLARE @Offset INT = (@Page - 1) * @PageSize;
  IF @Offset < 0 SET @Offset = 0;

  -- Audience visibility predicate (reused for count and data)
  -- A post is visible when its audience matches the viewer's status
  ;WITH visible_posts AS (
    SELECT fp.*
    FROM dbo.feed_posts fp
    WHERE
      (fp.sport_id IS NULL OR fp.sport_id = @SportId OR @SportId IS NULL)
      AND (
        -- Staff (no record in users OR viewer is a global_admin) see everything
        @ViewerStatusId IS NULL

        -- Audience: all → everyone
        OR fp.audience = 'all'

        -- players_only → only current players
        OR (fp.audience = 'players_only' AND @ViewerStatusId = 1)

        -- alumni_only → only alumni
        OR (fp.audience = 'alumni_only'  AND @ViewerStatusId = 2)

        -- by_position → viewers whose position matches
        OR (fp.audience = 'by_position' AND EXISTS (
              SELECT 1 FROM dbo.users u2
              WHERE u2.id = @ViewerUserId
                AND fp.audience_json IS NOT NULL
                AND EXISTS (
                  SELECT 1 FROM OPENJSON(fp.audience_json, '$.positions')
                  WHERE CAST([value] AS NVARCHAR(10)) = u2.position
                )
            ))

        -- by_grad_year → alumni whose grad year matches
        OR (fp.audience = 'by_grad_year' AND @ViewerStatusId = 2 AND EXISTS (
              SELECT 1 FROM dbo.users u2
              WHERE u2.id = @ViewerUserId
                AND fp.audience_json IS NOT NULL
                AND EXISTS (
                  SELECT 1 FROM OPENJSON(fp.audience_json, '$.gradYears')
                  WHERE CAST([value] AS SMALLINT) = u2.graduation_year
                )
            ))

        -- custom: AND-chain position + grad year
        OR (fp.audience = 'custom' AND fp.audience_json IS NOT NULL AND (
              (JSON_VALUE(fp.audience_json, '$.position') IS NULL
               OR JSON_VALUE(fp.audience_json, '$.position') = (
                    SELECT u2.position FROM dbo.users u2 WHERE u2.id = @ViewerUserId))
              AND
              (JSON_VALUE(fp.audience_json, '$.gradYear') IS NULL
               OR CAST(JSON_VALUE(fp.audience_json, '$.gradYear') AS SMALLINT) = (
                    SELECT u2.graduation_year FROM dbo.users u2 WHERE u2.id = @ViewerUserId))
           ))
      )
  )
  SELECT @TotalCount = COUNT(*) FROM visible_posts;

  ;WITH visible_posts AS (
    SELECT fp.*
    FROM dbo.feed_posts fp
    WHERE
      (fp.sport_id IS NULL OR fp.sport_id = @SportId OR @SportId IS NULL)
      AND (
        @ViewerStatusId IS NULL
        OR fp.audience = 'all'
        OR (fp.audience = 'players_only' AND @ViewerStatusId = 1)
        OR (fp.audience = 'alumni_only'  AND @ViewerStatusId = 2)
        OR (fp.audience = 'by_position' AND EXISTS (
              SELECT 1 FROM dbo.users u2
              WHERE u2.id = @ViewerUserId
                AND fp.audience_json IS NOT NULL
                AND EXISTS (
                  SELECT 1 FROM OPENJSON(fp.audience_json, '$.positions')
                  WHERE CAST([value] AS NVARCHAR(10)) = u2.position
                )
            ))
        OR (fp.audience = 'by_grad_year' AND @ViewerStatusId = 2 AND EXISTS (
              SELECT 1 FROM dbo.users u2
              WHERE u2.id = @ViewerUserId
                AND fp.audience_json IS NOT NULL
                AND EXISTS (
                  SELECT 1 FROM OPENJSON(fp.audience_json, '$.gradYears')
                  WHERE CAST([value] AS SMALLINT) = u2.graduation_year
                )
            ))
        OR (fp.audience = 'custom' AND fp.audience_json IS NOT NULL AND (
              (JSON_VALUE(fp.audience_json, '$.position') IS NULL
               OR JSON_VALUE(fp.audience_json, '$.position') = (
                    SELECT u2.position FROM dbo.users u2 WHERE u2.id = @ViewerUserId))
              AND
              (JSON_VALUE(fp.audience_json, '$.gradYear') IS NULL
               OR CAST(JSON_VALUE(fp.audience_json, '$.gradYear') AS SMALLINT) = (
                    SELECT u2.graduation_year FROM dbo.users u2 WHERE u2.id = @ViewerUserId))
           ))
      )
  )
  SELECT
    vp.id,
    vp.title,
    vp.body_html       AS bodyHtml,
    vp.audience,
    vp.audience_json   AS audienceJson,
    vp.sport_id        AS sportId,
    vp.is_pinned       AS isPinned,
    vp.is_welcome_post AS isWelcomePost,
    vp.campaign_id     AS campaignId,
    vp.created_by      AS createdBy,
    vp.published_at    AS publishedAt,
    vp.created_at      AS createdAt,
    CASE WHEN fpr.id IS NOT NULL THEN 1 ELSE 0 END AS isRead
  FROM visible_posts vp
  LEFT JOIN dbo.feed_post_reads fpr
    ON fpr.post_id = vp.id AND fpr.user_id = @ViewerUserId
  ORDER BY
    vp.is_pinned DESC,
    vp.published_at DESC
  OFFSET @Offset ROWS
  FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- ============================================================
-- sp_GetFeedPost
-- Returns a single post if the viewer is authorized to see it.
-- Same audience predicate as sp_GetFeed.
-- Empty result = unauthorized (API maps to 404, no info leak).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetFeedPost
  @PostId       UNIQUEIDENTIFIER,
  @ViewerUserId UNIQUEIDENTIFIER,
  @ErrorCode    NVARCHAR(50) OUTPUT,
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

  DECLARE @ViewerStatusId INT;
  SELECT @ViewerStatusId = status_id FROM dbo.users WHERE id = @ViewerUserId;

  SELECT
    fp.id,
    fp.title,
    fp.body_html       AS bodyHtml,
    fp.audience,
    fp.audience_json   AS audienceJson,
    fp.sport_id        AS sportId,
    fp.is_pinned       AS isPinned,
    fp.is_welcome_post AS isWelcomePost,
    fp.campaign_id     AS campaignId,
    fp.created_by      AS createdBy,
    fp.published_at    AS publishedAt,
    fp.created_at      AS createdAt,
    CASE WHEN fpr.id IS NOT NULL THEN 1 ELSE 0 END AS isRead
  FROM dbo.feed_posts fp
  LEFT JOIN dbo.feed_post_reads fpr
    ON fpr.post_id = fp.id AND fpr.user_id = @ViewerUserId
  WHERE fp.id = @PostId
    AND (
      @ViewerStatusId IS NULL
      OR fp.audience = 'all'
      OR (fp.audience = 'players_only' AND @ViewerStatusId = 1)
      OR (fp.audience = 'alumni_only'  AND @ViewerStatusId = 2)
      OR (fp.audience = 'by_position' AND EXISTS (
            SELECT 1 FROM dbo.users u2
            WHERE u2.id = @ViewerUserId
              AND fp.audience_json IS NOT NULL
              AND EXISTS (
                SELECT 1 FROM OPENJSON(fp.audience_json, '$.positions')
                WHERE CAST([value] AS NVARCHAR(10)) = u2.position
              )
          ))
      OR (fp.audience = 'by_grad_year' AND @ViewerStatusId = 2 AND EXISTS (
            SELECT 1 FROM dbo.users u2
            WHERE u2.id = @ViewerUserId
              AND fp.audience_json IS NOT NULL
              AND EXISTS (
                SELECT 1 FROM OPENJSON(fp.audience_json, '$.gradYears')
                WHERE CAST([value] AS SMALLINT) = u2.graduation_year
              )
          ))
      OR (fp.audience = 'custom' AND fp.audience_json IS NOT NULL AND (
            (JSON_VALUE(fp.audience_json, '$.position') IS NULL
             OR JSON_VALUE(fp.audience_json, '$.position') = (
                  SELECT u2.position FROM dbo.users u2 WHERE u2.id = @ViewerUserId))
            AND
            (JSON_VALUE(fp.audience_json, '$.gradYear') IS NULL
             OR CAST(JSON_VALUE(fp.audience_json, '$.gradYear') AS SMALLINT) = (
                  SELECT u2.graduation_year FROM dbo.users u2 WHERE u2.id = @ViewerUserId))
         ))
    );
END;
GO

-- ============================================================
-- sp_MarkPostRead
-- Idempotent: UNIQUE constraint on (post_id, user_id) handles
-- concurrent calls. No error if already read.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_MarkPostRead
  @PostId UNIQUEIDENTIFIER,
  @UserId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;

  IF NOT EXISTS (SELECT 1 FROM dbo.feed_posts WHERE id = @PostId)
    RETURN;

  IF NOT EXISTS (
    SELECT 1 FROM dbo.feed_post_reads
    WHERE post_id = @PostId AND user_id = @UserId
  )
  BEGIN
    INSERT INTO dbo.feed_post_reads (post_id, user_id)
    VALUES (@PostId, @UserId);
  END
END;
GO

-- ============================================================
-- sp_GetPostReadStats
-- Admin-only. Returns read-through rate for a post.
-- totalEligible = count of users who match the post's audience.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetPostReadStats
  @PostId    UNIQUEIDENTIFIER,
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

  DECLARE @Audience    NVARCHAR(30);
  DECLARE @AudienceJson NVARCHAR(MAX);
  DECLARE @SportId     UNIQUEIDENTIFIER;

  SELECT @Audience = audience, @AudienceJson = audience_json, @SportId = sport_id
  FROM   dbo.feed_posts
  WHERE  id = @PostId;

  IF @Audience IS NULL BEGIN SET @ErrorCode = 'POST_NOT_FOUND'; RETURN; END

  DECLARE @FilterGradYear  SMALLINT     = TRY_CAST(JSON_VALUE(@AudienceJson, '$.gradYear')  AS SMALLINT);
  DECLARE @FilterPosition  NVARCHAR(10) = JSON_VALUE(@AudienceJson, '$.position');
  DECLARE @FilterGradYears NVARCHAR(MAX)= JSON_QUERY(@AudienceJson, '$.gradYears');
  DECLARE @FilterPositions NVARCHAR(MAX)= JSON_QUERY(@AudienceJson, '$.positions');

  DECLARE @TotalEligible INT;
  SELECT @TotalEligible = COUNT(*)
  FROM dbo.users u
  WHERE u.status_id IN (1, 2)
    AND (@SportId IS NULL OR u.sport_id = @SportId)
    AND (
      @Audience = 'all'
      OR (@Audience = 'players_only' AND u.status_id = 1)
      OR (@Audience = 'alumni_only'  AND u.status_id = 2)
      OR (@Audience = 'by_grad_year' AND u.status_id = 2 AND (
            (@FilterGradYear IS NOT NULL AND u.graduation_year = @FilterGradYear)
            OR (@FilterGradYears IS NOT NULL AND EXISTS (
              SELECT 1 FROM OPENJSON(@FilterGradYears) WHERE CAST([value] AS SMALLINT) = u.graduation_year
            ))
          ))
      OR (@Audience = 'by_position' AND (
            (@FilterPosition IS NOT NULL AND u.position = @FilterPosition)
            OR (@FilterPositions IS NOT NULL AND EXISTS (
              SELECT 1 FROM OPENJSON(@FilterPositions) WHERE CAST([value] AS NVARCHAR(10)) = u.position
            ))
          ))
      OR (@Audience = 'custom'
          AND (@FilterGradYear IS NULL OR u.graduation_year = @FilterGradYear)
          AND (@FilterPosition IS NULL OR u.position        = @FilterPosition))
    );

  DECLARE @TotalRead INT;
  SELECT @TotalRead = COUNT(*) FROM dbo.feed_post_reads WHERE post_id = @PostId;

  SELECT
    @TotalEligible AS totalEligible,
    @TotalRead     AS totalRead,
    CASE WHEN @TotalEligible = 0 THEN 0
         ELSE CAST(100.0 * @TotalRead / @TotalEligible AS DECIMAL(5,1))
    END AS readThroughRatePct;
END;
GO
