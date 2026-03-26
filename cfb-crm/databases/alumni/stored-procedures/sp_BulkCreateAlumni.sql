-- ============================================================
-- sp_BulkCreateAlumni
-- Accepts a JSON array of alumni and inserts them all.
-- Run on: CfbAlumni database
-- ============================================================

CREATE PROCEDURE dbo.sp_BulkCreateAlumni
  @AlumniJson   NVARCHAR(MAX),  -- JSON array of alumni objects
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
    row_num              INT,
    first_name           NVARCHAR(100),
    last_name            NVARCHAR(100),
    graduation_year      SMALLINT,
    graduation_semester  NVARCHAR(10),
    position             NVARCHAR(10),
    recruiting_class     SMALLINT,
    personal_email       NVARCHAR(255),
    phone                NVARCHAR(20),
    linkedin_url         NVARCHAR(500),
    current_employer     NVARCHAR(200),
    current_job_title    NVARCHAR(150),
    current_city         NVARCHAR(100),
    current_state        NVARCHAR(50),
    is_donor             BIT,
    notes                NVARCHAR(MAX)
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
    TRY_CAST(JSON_VALUE(value, '$.graduationYear')    AS SMALLINT),
    ISNULL(JSON_VALUE(value, '$.graduationSemester'), 'spring'),
    JSON_VALUE(value, '$.position'),
    TRY_CAST(JSON_VALUE(value, '$.recruitingClass')   AS SMALLINT),
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

  DECLARE @rowNum    INT;
  DECLARE @firstName NVARCHAR(100);
  DECLARE @lastName  NVARCHAR(100);
  DECLARE @gradYear  SMALLINT;
  DECLARE @semester  NVARCHAR(10);
  DECLARE @position  NVARCHAR(10);
  DECLARE @recClass  SMALLINT;
  DECLARE @email     NVARCHAR(255);
  DECLARE @phone     NVARCHAR(20);
  DECLARE @linkedin  NVARCHAR(500);
  DECLARE @employer  NVARCHAR(200);
  DECLARE @jobTitle  NVARCHAR(150);
  DECLARE @city      NVARCHAR(100);
  DECLARE @state     NVARCHAR(50);
  DECLARE @isDonor   BIT;
  DECLARE @notes     NVARCHAR(MAX);

  DECLARE alumni_cursor CURSOR FOR
    SELECT row_num, first_name, last_name, graduation_year, graduation_semester,
           position, recruiting_class, personal_email, phone, linkedin_url,
           current_employer, current_job_title, current_city, current_state,
           is_donor, notes
    FROM @alumni;

  OPEN alumni_cursor;
  FETCH NEXT FROM alumni_cursor INTO
    @rowNum, @firstName, @lastName, @gradYear, @semester,
    @position, @recClass, @email, @phone, @linkedin,
    @employer, @jobTitle, @city, @state, @isDonor, @notes;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    BEGIN TRY
      -- Validate required fields
      IF @firstName IS NULL OR LEN(LTRIM(RTRIM(@firstName))) = 0
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'First name is required');
        SET @SkippedCount += 1;
        FETCH NEXT FROM alumni_cursor INTO @rowNum, @firstName, @lastName, @gradYear, @semester, @position, @recClass, @email, @phone, @linkedin, @employer, @jobTitle, @city, @state, @isDonor, @notes;
        CONTINUE;
      END

      IF @lastName IS NULL OR LEN(LTRIM(RTRIM(@lastName))) = 0
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'Last name is required');
        SET @SkippedCount += 1;
        FETCH NEXT FROM alumni_cursor INTO @rowNum, @firstName, @lastName, @gradYear, @semester, @position, @recClass, @email, @phone, @linkedin, @employer, @jobTitle, @city, @state, @isDonor, @notes;
        CONTINUE;
      END

      IF @gradYear IS NULL OR @gradYear < 1950 OR @gradYear > 2100
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'Invalid graduation year');
        SET @SkippedCount += 1;
        FETCH NEXT FROM alumni_cursor INTO @rowNum, @firstName, @lastName, @gradYear, @semester, @position, @recClass, @email, @phone, @linkedin, @employer, @jobTitle, @city, @state, @isDonor, @notes;
        CONTINUE;
      END

      IF @position NOT IN ('QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH')
      BEGIN
        INSERT INTO @errors VALUES (@rowNum, 'Invalid position: ' + ISNULL(@position, 'NULL'));
        SET @SkippedCount += 1;
        FETCH NEXT FROM alumni_cursor INTO @rowNum, @firstName, @lastName, @gradYear, @semester, @position, @recClass, @email, @phone, @linkedin, @employer, @jobTitle, @city, @state, @isDonor, @notes;
        CONTINUE;
      END

      INSERT INTO dbo.alumni (
        user_id, source_player_id, first_name, last_name,
        graduation_year, graduation_semester, position, recruiting_class,
        personal_email, phone, linkedin_url,
        current_employer, current_job_title, current_city, current_state,
        is_donor, status, notes
      )
      VALUES (
        NEWID(), NEWID(), @firstName, @lastName,
        @gradYear, @semester, @position, ISNULL(@recClass, @gradYear - 4),
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

    FETCH NEXT FROM alumni_cursor INTO
      @rowNum, @firstName, @lastName, @gradYear, @semester,
      @position, @recClass, @email, @phone, @linkedin,
      @employer, @jobTitle, @city, @state, @isDonor, @notes;
  END

  CLOSE alumni_cursor;
  DEALLOCATE alumni_cursor;

  SELECT @ErrorJson = ISNULL(
    (SELECT row_num AS rowNum, reason FROM @errors FOR JSON PATH),
    '[]'
  );
END;

