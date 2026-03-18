-- ============================================================
-- sp_GraduatePlayer
-- Distributed transaction: Roster DB → Alumni DB → Global DB
--
-- Prerequisites:
--   1. Linked server named [ALUMNI_DB] pointing to the Alumni SQL Server
--   2. Linked server named [GLOBAL_DB] pointing to the Global SQL Server
--   3. MSDTC (Distributed Transaction Coordinator) enabled on both servers
--
-- Usage:
--   EXEC dbo.sp_GraduatePlayer
--     @PlayerIds       = '["guid-1","guid-2"]',   -- JSON array of player GUIDs
--     @GraduationYear  = 2024,
--     @Semester        = 'spring',
--     @TriggeredBy     = 'coach-user-guid',
--     @Notes           = 'Spring 2024 graduating class',
--     @TransactionId   = 'batch-guid' OUTPUT,
--     @SuccessCount    = 0 OUTPUT,
--     @FailureJson     = '' OUTPUT
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.sp_GraduatePlayer
  @PlayerIds       NVARCHAR(MAX),    -- JSON array: ["guid","guid",...]
  @GraduationYear  SMALLINT,
  @Semester        NVARCHAR(10),     -- 'spring' | 'fall' | 'summer'
  @TriggeredBy     NVARCHAR(100),    -- user_id of triggering coach/admin
  @Notes           NVARCHAR(MAX)     = NULL,
  @TransactionId   UNIQUEIDENTIFIER  OUTPUT,
  @SuccessCount    INT               OUTPUT,
  @FailureJson     NVARCHAR(MAX)     OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;  -- auto-rollback entire transaction on any error

  -- ─── Setup ────────────────────────────────────────────────
  SET @TransactionId = NEWID();
  SET @SuccessCount  = 0;
  SET @FailureJson   = '[]';

  DECLARE @failures TABLE (player_id NVARCHAR(100), reason NVARCHAR(500));
  DECLARE @playerIdTable TABLE (player_id UNIQUEIDENTIFIER);
  DECLARE @currentPlayerId UNIQUEIDENTIFIER;

  -- Parse the JSON array of player IDs
  INSERT INTO @playerIdTable (player_id)
  SELECT CAST([value] AS UNIQUEIDENTIFIER)
  FROM OPENJSON(@PlayerIds);

  -- Validate inputs
  IF @GraduationYear < 1900 OR @GraduationYear > 2100
  BEGIN
    RAISERROR('Invalid graduation year.', 16, 1);
    RETURN;
  END

  IF @Semester NOT IN ('spring', 'fall', 'summer')
  BEGIN
    RAISERROR('Invalid semester. Must be spring, fall, or summer.', 16, 1);
    RETURN;
  END

  -- ─── Process each player ──────────────────────────────────
  DECLARE player_cursor CURSOR FOR
    SELECT player_id FROM @playerIdTable;

  OPEN player_cursor;
  FETCH NEXT FROM player_cursor INTO @currentPlayerId;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      BEGIN DISTRIBUTED TRANSACTION;

        -- ── 1. Fetch player from Roster DB ──────────────────
        DECLARE @firstName     NVARCHAR(100);
        DECLARE @lastName      NVARCHAR(100);
        DECLARE @position      NVARCHAR(10);
        DECLARE @recruitClass  SMALLINT;
        DECLARE @userId        UNIQUEIDENTIFIER;
        DECLARE @playerStatus  NVARCHAR(20);

        SELECT
          @firstName    = first_name,
          @lastName     = last_name,
          @position     = position,
          @recruitClass = recruiting_class,
          @userId       = user_id,
          @playerStatus = status
        FROM dbo.players
        WHERE id = @currentPlayerId;

        IF @userId IS NULL
        BEGIN
          ROLLBACK TRANSACTION;
          INSERT INTO @failures VALUES (CAST(@currentPlayerId AS NVARCHAR(100)), 'Player not found in Roster DB');
          FETCH NEXT FROM player_cursor INTO @currentPlayerId;
          CONTINUE;
        END

        IF @playerStatus = 'graduated'
        BEGIN
          ROLLBACK TRANSACTION;
          INSERT INTO @failures VALUES (CAST(@currentPlayerId AS NVARCHAR(100)), 'Player already graduated');
          FETCH NEXT FROM player_cursor INTO @currentPlayerId;
          CONTINUE;
        END

        -- ── 2. Update player status in Roster DB ────────────
        UPDATE dbo.players
        SET
          status       = 'graduated',
          graduated_at = SYSUTCDATETIME(),
          updated_at   = SYSUTCDATETIME()
        WHERE id = @currentPlayerId;

        -- ── 3. Write graduation log in Roster DB ────────────
        INSERT INTO dbo.graduation_log
          (transaction_id, player_id, graduation_year, graduation_semester,
           triggered_by, status, notes)
        VALUES
          (@TransactionId, @currentPlayerId, @GraduationYear, @Semester,
           CAST(@TriggeredBy AS UNIQUEIDENTIFIER), 'success', @Notes);

        -- ── 4. Insert alumni record in Alumni DB ─────────────
        --    Uses linked server [ALUMNI_DB]. Assumes alumni DB name is CfbAlumni.
        EXEC [ALUMNI_DB].CfbAlumni.dbo.sp_CreateAlumniFromPlayer
          @UserId             = @userId,
          @SourcePlayerId     = @currentPlayerId,
          @FirstName          = @firstName,
          @LastName           = @lastName,
          @GraduationYear     = @GraduationYear,
          @GraduationSemester = @Semester,
          @Position           = @position,
          @RecruitingClass    = @recruitClass;

        -- ── 5. Update permissions in Global DB ───────────────
        --    Remove roster access, grant alumni access
        EXEC [GLOBAL_DB].CfbGlobal.dbo.sp_TransferPlayerToAlumni
          @UserId      = @userId,
          @GrantedBy   = @TriggeredBy;

        COMMIT TRANSACTION;
        SET @SuccessCount = @SuccessCount + 1;

    END TRY
    BEGIN CATCH
      IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

      DECLARE @errMsg NVARCHAR(500) = ERROR_MESSAGE();
      INSERT INTO @failures VALUES (CAST(@currentPlayerId AS NVARCHAR(100)), @errMsg);

      -- Log failure in graduation_log (outside the rolled-back transaction)
      INSERT INTO dbo.graduation_log
        (transaction_id, player_id, graduation_year, graduation_semester,
         triggered_by, status, notes)
      VALUES
        (@TransactionId, @currentPlayerId, @GraduationYear, @Semester,
         CAST(@TriggeredBy AS UNIQUEIDENTIFIER), 'failed', @errMsg);

    END CATCH;

    FETCH NEXT FROM player_cursor INTO @currentPlayerId;
  END

  CLOSE player_cursor;
  DEALLOCATE player_cursor;

  -- ─── Build failure JSON output ────────────────────────────
  SELECT @FailureJson = (
    SELECT player_id, reason
    FROM @failures
    FOR JSON PATH
  );

  IF @FailureJson IS NULL SET @FailureJson = '[]';

END;
GO

-- ============================================================
-- sp_CreateAlumniFromPlayer  (runs ON Alumni DB server)
-- Called via linked server from sp_GraduatePlayer
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateAlumniFromPlayer
  @UserId             UNIQUEIDENTIFIER,
  @SourcePlayerId     UNIQUEIDENTIFIER,
  @FirstName          NVARCHAR(100),
  @LastName           NVARCHAR(100),
  @GraduationYear     SMALLINT,
  @GraduationSemester NVARCHAR(10),
  @Position           NVARCHAR(10),
  @RecruitingClass    SMALLINT
AS
BEGIN
  SET NOCOUNT ON;

  -- Idempotent: skip if alumni already exists for this player
  IF EXISTS (SELECT 1 FROM dbo.alumni WHERE source_player_id = @SourcePlayerId)
  BEGIN
    RAISERROR('Alumni record already exists for this player.', 16, 1);
    RETURN;
  END

  INSERT INTO dbo.alumni
    (user_id, source_player_id, first_name, last_name,
     graduation_year, graduation_semester, position, recruiting_class, status)
  VALUES
    (@UserId, @SourcePlayerId, @FirstName, @LastName,
     @GraduationYear, @GraduationSemester, @Position, @RecruitingClass, 'active');
END;
GO

-- ============================================================
-- sp_TransferPlayerToAlumni  (runs ON Global DB server)
-- Swaps app_permissions: removes roster, adds alumni
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_TransferPlayerToAlumni
  @UserId    UNIQUEIDENTIFIER,
  @GrantedBy NVARCHAR(100)
AS
BEGIN
  SET NOCOUNT ON;

  -- Revoke roster access
  UPDATE dbo.app_permissions
  SET revoked_at = SYSUTCDATETIME()
  WHERE user_id = @UserId
    AND app_name = 'roster'
    AND revoked_at IS NULL;

  -- Grant alumni access (readonly by default — alumni can view their own profile)
  IF NOT EXISTS (
    SELECT 1 FROM dbo.app_permissions
    WHERE user_id = @UserId AND app_name = 'alumni' AND revoked_at IS NULL
  )
  BEGIN
    INSERT INTO dbo.app_permissions (user_id, app_name, role, granted_by)
    VALUES (@UserId, 'alumni', 'readonly', CAST(@GrantedBy AS UNIQUEIDENTIFIER));
  END

  -- Audit log
  INSERT INTO dbo.audit_log (actor_id, actor_email, action, target_type, target_id, payload)
  VALUES (
    CAST(@GrantedBy AS UNIQUEIDENTIFIER),
    NULL,
    'player_graduated_to_alumni',
    'user',
    CAST(@UserId AS NVARCHAR(100)),
    JSON_OBJECT('rosterAccessRevoked': 'true', 'alumniAccessGranted': 'true')
  );
END;
GO
