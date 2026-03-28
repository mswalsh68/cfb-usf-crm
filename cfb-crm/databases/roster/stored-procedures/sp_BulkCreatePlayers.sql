-- ============================================================
-- sp_BulkCreatePlayers
-- Accepts a JSON array of players and inserts them all.
-- Skips duplicates (same user_id or same jersey number on active players).
-- Run on: CfbRoster database
-- ============================================================

CREATE PROCEDURE dbo.sp_BulkCreatePlayers
  @PlayersJson  NVARCHAR(MAX),  -- JSON array of player objects
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

  -- Parse JSON array
  INSERT INTO @players (
    row_num, first_name, last_name, jersey_number, position, academic_year,
    recruiting_class, height_inches, weight_lbs, home_town, home_state,
    high_school, gpa, major, phone, emergency_contact_name, emergency_contact_phone, notes
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    JSON_VALUE(value, '$.firstName'),
    JSON_VALUE(value, '$.lastName'),
    TRY_CAST(JSON_VALUE(value, '$.jerseyNumber')     AS TINYINT),
    JSON_VALUE(value, '$.position'),
    JSON_VALUE(value, '$.academicYear'),
    TRY_CAST(JSON_VALUE(value, '$.recruitingClass')  AS SMALLINT),
    TRY_CAST(JSON_VALUE(value, '$.heightInches')     AS TINYINT),
    TRY_CAST(JSON_VALUE(value, '$.weightLbs')        AS SMALLINT),
    JSON_VALUE(value, '$.homeTown'),
    JSON_VALUE(value, '$.homeState'),
    JSON_VALUE(value, '$.highSchool'),
    TRY_CAST(JSON_VALUE(value, '$.gpa')              AS DECIMAL(3,2)),
    JSON_VALUE(value, '$.major'),
    JSON_VALUE(value, '$.phone'),
    JSON_VALUE(value, '$.emergencyContactName'),
    JSON_VALUE(value, '$.emergencyContactPhone'),
    JSON_VALUE(value, '$.notes')
  FROM OPENJSON(@PlayersJson);

  -- Process each player
  DECLARE @rowNum     INT;
  DECLARE @firstName  NVARCHAR(100);
  DECLARE @lastName   NVARCHAR(100);
  DECLARE @jersey     TINYINT;
  DECLARE @position   NVARCHAR(10);
  DECLARE @acYear     NVARCHAR(20);
  DECLARE @recClass   SMALLINT;
  DECLARE @heightIn   TINYINT;
  DECLARE @weightLbs  SMALLINT;
  DECLARE @town       NVARCHAR(100);
  DECLARE @state      NVARCHAR(50);
  DECLARE @hs         NVARCHAR(150);
  DECLARE @gpa        DECIMAL(3,2);
  DECLARE @major      NVARCHAR(100);
  DECLARE @phone      NVARCHAR(20);
  DECLARE @ecName     NVARCHAR(150);
  DECLARE @ecPhone    NVARCHAR(20);
  DECLARE @notes      NVARCHAR(MAX);

  DECLARE player_cursor CURSOR FOR
    SELECT row_num, first_name, last_name, jersey_number, position, academic_year,
           recruiting_class, height_inches, weight_lbs, home_town, home_state,
           high_school, gpa, major, phone, emergency_contact_name, emergency_contact_phone, notes
    FROM @players;

  OPEN player_cursor;
  FETCH NEXT FROM player_cursor INTO
    @rowNum, @firstName, @lastName, @jersey, @position, @acYear,
    @recClass, @heightIn, @weightLbs, @town, @state,
    @hs, @gpa, @major, @phone, @ecName, @ecPhone, @notes;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      -- Validate required fields
      IF @firstName IS NULL OR LEN(LTRIM(RTRIM(@firstName))) = 0
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'First name is required');
        SET @SkippedCount += 1;
        FETCH NEXT FROM player_cursor INTO @rowNum, @firstName, @lastName, @jersey, @position, @acYear, @recClass, @heightIn, @weightLbs, @town, @state, @hs, @gpa, @major, @phone, @ecName, @ecPhone, @notes;
        CONTINUE;
      END

      IF @lastName IS NULL OR LEN(LTRIM(RTRIM(@lastName))) = 0
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'Last name is required');
        SET @SkippedCount += 1;
        FETCH NEXT FROM player_cursor INTO @rowNum, @firstName, @lastName, @jersey, @position, @acYear, @recClass, @heightIn, @weightLbs, @town, @state, @hs, @gpa, @major, @phone, @ecName, @ecPhone, @notes;
        CONTINUE;
      END

      IF @position NOT IN ('QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH')
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'Invalid position: ' + ISNULL(@position, 'NULL'));
        SET @SkippedCount += 1;
        FETCH NEXT FROM player_cursor INTO @rowNum, @firstName, @lastName, @jersey, @position, @acYear, @recClass, @heightIn, @weightLbs, @town, @state, @hs, @gpa, @major, @phone, @ecName, @ecPhone, @notes;
        CONTINUE;
      END

      IF @recClass IS NULL OR @recClass < 2000 OR @recClass > 2100
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'Invalid recruiting class year');
        SET @SkippedCount += 1;
        FETCH NEXT FROM player_cursor INTO @rowNum, @firstName, @lastName, @jersey, @position, @acYear, @recClass, @heightIn, @weightLbs, @town, @state, @hs, @gpa, @major, @phone, @ecName, @ecPhone, @notes;
        CONTINUE;
      END

      -- Check jersey conflict
      IF @jersey IS NOT NULL AND EXISTS (
        SELECT 1 FROM roster.players WHERE jersey_number = @jersey AND status = 'active'
      )
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'Jersey #' + CAST(@jersey AS NVARCHAR) + ' already in use');
        SET @SkippedCount += 1;
        FETCH NEXT FROM player_cursor INTO @rowNum, @firstName, @lastName, @jersey, @position, @acYear, @recClass, @heightIn, @weightLbs, @town, @state, @hs, @gpa, @major, @phone, @ecName, @ecPhone, @notes;
        CONTINUE;
      END

      -- Insert player (no user_id for bulk uploads — admin links accounts later)
      INSERT INTO roster.players (
        user_id, first_name, last_name, jersey_number, position, academic_year,
        recruiting_class, height_inches, weight_lbs, home_town, home_state,
        high_school, gpa, major, phone, emergency_contact_name, emergency_contact_phone, notes
      )
      VALUES (
        NEWID(), @firstName, @lastName, @jersey, @position, @acYear,
        @recClass, @heightIn, @weightLbs, @town, @state,
        @hs, @gpa, @major, @phone, @ecName, @ecPhone, @notes
      );

      SET @SuccessCount += 1;

    END TRY
    BEGIN CATCH
      INSERT INTO @errors VALUES (@rowNum, ERROR_MESSAGE());
      SET @SkippedCount += 1;
    END CATCH;

    FETCH NEXT FROM player_cursor INTO
      @rowNum, @firstName, @lastName, @jersey, @position, @acYear,
      @recClass, @heightIn, @weightLbs, @town, @state,
      @hs, @gpa, @major, @phone, @ecName, @ecPhone, @notes;
  END

  CLOSE player_cursor;
  DEALLOCATE player_cursor;

  SELECT @ErrorJson = ISNULL(
    (SELECT row_num AS rowNum, reason FROM @errors FOR JSON PATH),
    '[]'
  );
END;

