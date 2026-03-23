-- ============================================================
-- ALUMNI DB — ALL STORED PROCEDURES
-- Run this file on: CfbAlumni database
-- Run after: 001_initial_schema.sql
-- ============================================================

-- ============================================================
-- sp_CreateAlumniFromPlayer
-- Called by sp_GraduatePlayer via linked server.
-- Creates the alumni record when a player graduates.
-- Idempotent — safe to retry if the transaction was partially applied.
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

  -- Idempotent: already exists — return the existing ID
  IF EXISTS (SELECT 1 FROM dbo.alumni WHERE source_player_id = @SourcePlayerId)
  BEGIN
    SELECT @NewAlumniId = id FROM dbo.alumni WHERE source_player_id = @SourcePlayerId;
    SET @ErrorCode = 'ALUMNI_ALREADY_EXISTS';
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
     @Phone, @PersonalEmail, 'active');
END;
GO

-- ============================================================
-- sp_GetAlumni
-- Paginated, filterable alumni list.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetAlumni
  @Search          NVARCHAR(255) = NULL,
  @Status          NVARCHAR(20)  = NULL,
  @IsDonor         BIT           = NULL,
  @GradYear        SMALLINT      = NULL,
  @Position        NVARCHAR(10)  = NULL,
  @Page            INT           = 1,
  @PageSize        INT           = 50,
  @TotalCount      INT           OUTPUT
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @Offset     INT           = (@Page - 1) * @PageSize;
  DECLARE @SearchWild NVARCHAR(257) = '%' + ISNULL(@Search, '') + '%';

  SELECT @TotalCount = COUNT(*)
  FROM dbo.alumni a
  WHERE (@Status   IS NULL OR a.status           = @Status)
    AND (@IsDonor  IS NULL OR a.is_donor          = @IsDonor)
    AND (@GradYear IS NULL OR a.graduation_year   = @GradYear)
    AND (@Position IS NULL OR a.position          = @Position)
    AND (@Search   IS NULL OR a.first_name LIKE @SearchWild OR a.last_name LIKE @SearchWild
         OR a.current_employer LIKE @SearchWild OR a.current_city LIKE @SearchWild
         OR a.personal_email LIKE @SearchWild);

  SELECT
    a.id,
    a.user_id               AS userId,
    a.source_player_id      AS sourcePlayerId,
    a.first_name            AS firstName,
    a.last_name             AS lastName,
    a.graduation_year       AS graduationYear,
    a.graduation_semester   AS graduationSemester,
    a.position,
    a.recruiting_class      AS recruitingClass,
    a.status,
    a.personal_email        AS personalEmail,
    a.phone,
    a.linkedin_url          AS linkedInUrl,
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
  FROM dbo.alumni a
  WHERE (@Status   IS NULL OR a.status         = @Status)
    AND (@IsDonor  IS NULL OR a.is_donor        = @IsDonor)
    AND (@GradYear IS NULL OR a.graduation_year = @GradYear)
    AND (@Position IS NULL OR a.position        = @Position)
    AND (@Search   IS NULL OR a.first_name LIKE @SearchWild OR a.last_name LIKE @SearchWild
         OR a.current_employer LIKE @SearchWild OR a.current_city LIKE @SearchWild
         OR a.personal_email LIKE @SearchWild)
  ORDER BY a.last_name, a.first_name
  OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- ============================================================
-- sp_GetAlumniById
-- Returns a single alumni record plus their interaction history.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetAlumniById
  @AlumniId  UNIQUEIDENTIFIER,
  @ErrorCode NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF NOT EXISTS (SELECT 1 FROM dbo.alumni WHERE id = @AlumniId)
  BEGIN
    SET @ErrorCode = 'ALUMNI_NOT_FOUND';
    RETURN;
  END

  -- Main record
  SELECT
    a.id, a.user_id AS userId, a.source_player_id AS sourcePlayerId,
    a.first_name AS firstName, a.last_name AS lastName,
    a.graduation_year AS graduationYear, a.graduation_semester AS graduationSemester,
    a.position, a.recruiting_class AS recruitingClass, a.status,
    a.personal_email AS personalEmail, a.phone, a.linkedin_url AS linkedInUrl,
    a.current_employer AS currentEmployer, a.current_job_title AS currentJobTitle,
    a.current_city AS currentCity, a.current_state AS currentState,
    a.is_donor AS isDonor, a.last_donation_date AS lastDonationDate,
    a.total_donations AS totalDonations, a.engagement_score AS engagementScore,
    a.notes, a.created_at AS createdAt, a.updated_at AS updatedAt
  FROM dbo.alumni a
  WHERE a.id = @AlumniId;

  -- Interaction history
  SELECT
    il.id,
    il.channel,
    il.summary,
    il.outcome,
    il.follow_up_at AS followUpAt,
    il.logged_at    AS loggedAt,
    il.logged_by    AS loggedBy
  FROM dbo.interaction_log il
  WHERE il.alumni_id = @AlumniId
  ORDER BY il.logged_at DESC;
END;
GO

-- ============================================================
-- sp_UpdateAlumni
-- Updates alumni contact/career info. NULL params = no change.
-- Also recalculates engagement score based on updated fields.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateAlumni
  @AlumniId        UNIQUEIDENTIFIER,
  @Status          NVARCHAR(20)   = NULL,
  @PersonalEmail   NVARCHAR(255)  = NULL,
  @Phone           NVARCHAR(20)   = NULL,
  @LinkedInUrl     NVARCHAR(500)  = NULL,
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
  BEGIN
    SET @ErrorCode = 'ALUMNI_NOT_FOUND';
    RETURN;
  END

  IF @Status IS NOT NULL AND @Status NOT IN ('active','lostContact','deceased','doNotContact')
  BEGIN
    SET @ErrorCode = 'INVALID_STATUS';
    RETURN;
  END

  UPDATE dbo.alumni SET
    status              = COALESCE(@Status,           status),
    personal_email      = COALESCE(@PersonalEmail,    personal_email),
    phone               = COALESCE(@Phone,            phone),
    linkedin_url        = COALESCE(@LinkedInUrl,      linkedin_url),
    current_employer    = COALESCE(@CurrentEmployer,  current_employer),
    current_job_title   = COALESCE(@CurrentJobTitle,  current_job_title),
    current_city        = COALESCE(@CurrentCity,      current_city),
    current_state       = COALESCE(@CurrentState,     current_state),
    is_donor            = COALESCE(@IsDonor,          is_donor),
    last_donation_date  = COALESCE(@LastDonationDate, last_donation_date),
    total_donations     = COALESCE(@TotalDonations,   total_donations),
    notes               = COALESCE(@Notes,            notes),
    updated_at          = SYSUTCDATETIME()
  WHERE id = @AlumniId;

  -- Recalculate engagement score in SQL:
  -- Base 30 pts + contact info (up to 25) + employment (up to 20) + donor (25)
  UPDATE dbo.alumni SET
    engagement_score = CAST(
      30
      + CASE WHEN personal_email   IS NOT NULL THEN 10 ELSE 0 END
      + CASE WHEN phone            IS NOT NULL THEN 8  ELSE 0 END
      + CASE WHEN linkedin_url     IS NOT NULL THEN 7  ELSE 0 END
      + CASE WHEN current_employer IS NOT NULL THEN 10 ELSE 0 END
      + CASE WHEN current_job_title IS NOT NULL THEN 10 ELSE 0 END
      + CASE WHEN is_donor = 1 THEN 25 ELSE 0 END
    AS TINYINT)
  WHERE id = @AlumniId;
END;
GO

-- ============================================================
-- sp_LogInteraction
-- Records a staff interaction with an alumni.
-- Auto-increments engagement score slightly on each logged interaction.
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

  IF NOT EXISTS (SELECT 1 FROM dbo.alumni WHERE id = @AlumniId)
  BEGIN
    SET @ErrorCode = 'ALUMNI_NOT_FOUND';
    RETURN;
  END

  IF LEN(LTRIM(RTRIM(@Summary))) = 0
  BEGIN
    SET @ErrorCode = 'SUMMARY_REQUIRED';
    RETURN;
  END

  INSERT INTO dbo.interaction_log
    (alumni_id, logged_by, channel, summary, outcome, follow_up_at)
  VALUES
    (@AlumniId, @LoggedBy, @Channel, @Summary, @Outcome, @FollowUpAt);

  -- Bump engagement score by 2 per interaction, capped at 100
  UPDATE dbo.alumni
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
-- Creates an outreach campaign. Validates audience targeting.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateCampaign
  @Name             NVARCHAR(200),
  @Description      NVARCHAR(MAX)  = NULL,
  @TargetAudience   NVARCHAR(20),
  @AudienceFilters  NVARCHAR(MAX)  = NULL,   -- JSON blob
  @ScheduledAt      DATETIME2      = NULL,
  @CreatedBy        UNIQUEIDENTIFIER,
  @NewCampaignId    UNIQUEIDENTIFIER OUTPUT,
  @ErrorCode        NVARCHAR(50)   OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  IF LEN(LTRIM(RTRIM(@Name))) = 0
  BEGIN
    SET @ErrorCode = 'NAME_REQUIRED';
    RETURN;
  END

  IF @TargetAudience NOT IN ('all','byClass','byPosition','byStatus','custom')
  BEGIN
    SET @ErrorCode = 'INVALID_TARGET_AUDIENCE';
    RETURN;
  END

  -- Custom audience requires filters
  IF @TargetAudience = 'custom' AND (@AudienceFilters IS NULL OR LEN(@AudienceFilters) < 2)
  BEGIN
    SET @ErrorCode = 'CUSTOM_AUDIENCE_REQUIRES_FILTERS';
    RETURN;
  END

  -- Cannot schedule in the past
  IF @ScheduledAt IS NOT NULL AND @ScheduledAt < SYSUTCDATETIME()
  BEGIN
    SET @ErrorCode = 'SCHEDULED_DATE_IN_PAST';
    RETURN;
  END

  SET @NewCampaignId = NEWID();

  INSERT INTO dbo.outreach_campaigns
    (id, name, description, target_audience, audience_filters, scheduled_at, created_by)
  VALUES
    (@NewCampaignId, @Name, @Description, @TargetAudience, @AudienceFilters, @ScheduledAt, @CreatedBy);
END;
GO

-- ============================================================
-- sp_GetCampaigns
-- Returns all campaigns with computed message metrics.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetCampaigns
AS
BEGIN
  SET NOCOUNT ON;

  SELECT
    c.id,
    c.name,
    c.description,
    c.target_audience   AS targetAudience,
    c.status,
    c.scheduled_at      AS scheduledAt,
    c.completed_at      AS completedAt,
    c.created_by        AS createdBy,
    c.created_at        AS createdAt,
    -- Computed metrics in SQL — no aggregation in application code
    COUNT(m.id)                                                        AS totalMessages,
    SUM(CASE WHEN m.status = 'sent'      THEN 1 ELSE 0 END)           AS sentCount,
    SUM(CASE WHEN m.status = 'responded' THEN 1 ELSE 0 END)           AS respondedCount,
    SUM(CASE WHEN m.status = 'bounced'   THEN 1 ELSE 0 END)           AS bouncedCount,
    CASE
      WHEN SUM(CASE WHEN m.status = 'sent' THEN 1 ELSE 0 END) > 0
      THEN CAST(
        SUM(CASE WHEN m.status = 'responded' THEN 1 ELSE 0 END) * 100.0 /
        SUM(CASE WHEN m.status = 'sent'      THEN 1 ELSE 0 END)
        AS DECIMAL(5,2))
      ELSE 0
    END                                                                AS responseRatePct
  FROM dbo.outreach_campaigns c
  LEFT JOIN dbo.outreach_messages m ON m.campaign_id = c.id
  GROUP BY c.id, c.name, c.description, c.target_audience, c.status,
           c.scheduled_at, c.completed_at, c.created_by, c.created_at
  ORDER BY c.created_at DESC;
END;
GO

-- ============================================================
-- sp_GetAlumniStats
-- Dashboard summary stats — all computed in SQL.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetAlumniStats
AS
BEGIN
  SET NOCOUNT ON;

  SELECT
    COUNT(*)                                                      AS totalAlumni,
    SUM(CASE WHEN status = 'active'       THEN 1 ELSE 0 END)     AS active,
    SUM(CASE WHEN status = 'lostContact'  THEN 1 ELSE 0 END)     AS lostContact,
    SUM(CASE WHEN status = 'doNotContact' THEN 1 ELSE 0 END)     AS doNotContact,
    SUM(CASE WHEN is_donor = 1            THEN 1 ELSE 0 END)     AS donors,
    ISNULL(SUM(total_donations), 0)                              AS totalDonations,
    ISNULL(CAST(AVG(CAST(engagement_score AS FLOAT)) AS DECIMAL(5,1)), 0) AS avgEngagement,
    MIN(graduation_year)                                          AS earliestClass,
    MAX(graduation_year)                                          AS latestClass,
    -- Class breakdown as JSON
    (
      SELECT graduation_year AS gradYear, COUNT(*) AS cnt
      FROM dbo.alumni
      GROUP BY graduation_year
      ORDER BY graduation_year DESC
      FOR JSON PATH
    ) AS classCounts
  FROM dbo.alumni;
END;
GO

-- ============================================================
-- sp_ResolveAudienceForCampaign
-- Given a campaign ID, returns the list of alumni IDs that match
-- its targeting rules. Called before dispatching messages.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ResolveAudienceForCampaign
  @CampaignId UNIQUEIDENTIFIER,
  @ErrorCode  NVARCHAR(50) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET @ErrorCode = NULL;

  DECLARE @Audience       NVARCHAR(20);
  DECLARE @FiltersJson    NVARCHAR(MAX);

  SELECT @Audience = target_audience, @FiltersJson = audience_filters
  FROM dbo.outreach_campaigns
  WHERE id = @CampaignId;

  IF @Audience IS NULL
  BEGIN
    SET @ErrorCode = 'CAMPAIGN_NOT_FOUND';
    RETURN;
  END

  -- Parse filter values from JSON (used by byClass, byPosition, byStatus, custom)
  DECLARE @FilterGradYear   SMALLINT     = TRY_CAST(JSON_VALUE(@FiltersJson, '$.gradYear')   AS SMALLINT);
  DECLARE @FilterPosition   NVARCHAR(10) = JSON_VALUE(@FiltersJson, '$.position');
  DECLARE @FilterStatus     NVARCHAR(20) = JSON_VALUE(@FiltersJson, '$.status');

  SELECT a.id AS alumniId, a.first_name AS firstName, a.last_name AS lastName,
         a.personal_email AS personalEmail, a.phone
  FROM dbo.alumni a
  WHERE a.status <> 'doNotContact'
    AND (
      @Audience = 'all'
      OR (@Audience = 'byClass'    AND a.graduation_year = @FilterGradYear)
      OR (@Audience = 'byPosition' AND a.position        = @FilterPosition)
      OR (@Audience = 'byStatus'   AND a.status          = @FilterStatus)
      OR (@Audience = 'custom'
          AND (@FilterGradYear IS NULL OR a.graduation_year = @FilterGradYear)
          AND (@FilterPosition IS NULL OR a.position        = @FilterPosition)
          AND (@FilterStatus   IS NULL OR a.status          = @FilterStatus)
      )
    );
END;
GO
