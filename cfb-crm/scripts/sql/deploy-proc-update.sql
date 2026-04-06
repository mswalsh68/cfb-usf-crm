-- ============================================================
-- LEGACYLINK — Deploy Stored Procedure Update to All Clients
-- Run against: CfbGlobal
-- ============================================================
-- USE CASE: After updating a stored procedure in the codebase,
--   run this script to push the change to every active client DB.
--
-- ADMIN INSTRUCTIONS:
--   1. Set @TargetDbType to 'roster' or 'alumni'
--   2. Paste the full updated stored procedure SQL into @ProcSql
--      - Use CREATE OR ALTER PROCEDURE (always idempotent)
--      - Do NOT include GO statements
--      - Do NOT include a USE statement (added automatically)
--   3. Run against CfbGlobal
--
-- The script loops every active team and applies the SP to
-- their roster_db or alumni_db using dynamic SQL.
-- ============================================================

USE LegacyLinkGlobal;
GO

-- ─── ADMIN: Configure these two variables ───────────────────
DECLARE @TargetDbType NVARCHAR(10)  = 'roster';   -- 'roster' or 'alumni'

DECLARE @ProcSql NVARCHAR(MAX) = N'
CREATE OR ALTER PROCEDURE dbo.your_proc_name
  @Param1 NVARCHAR(100)
AS
BEGIN
  SET NOCOUNT ON;
  -- Paste your complete stored procedure body here.
  -- Do NOT include GO or USE statements.
  -- Single quotes inside the SP body do NOT need escaping here —
  -- this is an NVARCHAR variable, not a nested string literal.
  SELECT ''example'';
END;
';
-- ────────────────────────────────────────────────────────────

-- Validate target DB type
IF @TargetDbType NOT IN ('roster', 'alumni')
  THROW 50010, '@TargetDbType must be ''roster'' or ''alumni''.', 1;

IF LEN(LTRIM(RTRIM(ISNULL(@ProcSql, '')))) < 10
  THROW 50011, '@ProcSql is empty. Paste the stored procedure SQL before running.', 1;

-- ─── Loop all active teams and deploy ───────────────────────
DECLARE @TeamId    UNIQUEIDENTIFIER;
DECLARE @TeamAbbr  NVARCHAR(10);
DECLARE @DbName    NVARCHAR(110);
DECLARE @ExecSql   NVARCHAR(MAX);
DECLARE @Success   INT = 0;
DECLARE @Failed    INT = 0;

DECLARE team_cursor CURSOR FOR
  SELECT id, abbr,
         CASE @TargetDbType WHEN 'roster' THEN roster_db ELSE alumni_db END AS db_name
  FROM dbo.teams
  WHERE is_active = 1
  ORDER BY abbr;

OPEN team_cursor;
FETCH NEXT FROM team_cursor INTO @TeamId, @TeamAbbr, @DbName;

WHILE @@FETCH_STATUS = 0
BEGIN
  BEGIN TRY
    -- Build: USE [ClientDb]; <proc sql>
    -- The @ProcSql variable is passed as a parameter to sp_executesql,
    -- so single quotes inside it do NOT need escaping here.
    SET @ExecSql = N'USE [' + @DbName + N']; EXEC sp_executesql @Proc;';

    EXEC sp_executesql
      @ExecSql,
      N'@Proc NVARCHAR(MAX)',
      @Proc = @ProcSql;

    PRINT 'OK  [' + @TeamAbbr + '] ' + @DbName;
    SET @Success = @Success + 1;
  END TRY
  BEGIN CATCH
    PRINT 'ERR [' + @TeamAbbr + '] ' + @DbName + ' — ' + ERROR_MESSAGE();
    SET @Failed = @Failed + 1;
  END CATCH;

  FETCH NEXT FROM team_cursor INTO @TeamId, @TeamAbbr, @DbName;
END

CLOSE team_cursor;
DEALLOCATE team_cursor;

-- ─── Summary ─────────────────────────────────────────────────
PRINT '';
PRINT '============================================================';
PRINT 'Deploy complete.';
PRINT '  Succeeded : ' + CAST(@Success AS NVARCHAR(10));
PRINT '  Failed    : ' + CAST(@Failed  AS NVARCHAR(10));
IF @Failed > 0
  PRINT '  Review ERR lines above and re-run manually for failed DBs.';
PRINT '============================================================';
GO


-- ============================================================
-- EXAMPLE: How to deploy sp_GetPlayers to all roster DBs
-- ============================================================
--
-- 1. Set @TargetDbType = 'roster'
-- 2. Set @ProcSql to the new version of the procedure, e.g.:
--
-- DECLARE @ProcSql NVARCHAR(MAX) = N'
-- CREATE OR ALTER PROCEDURE dbo.sp_GetPlayers
--   @Search     NVARCHAR(255) = NULL,
--   @Status     NVARCHAR(20)  = NULL,
--   ...
-- AS
-- BEGIN
--   SET NOCOUNT ON;
--   -- new logic here
-- END;
-- ';
--
-- 3. Run the full script against CfbGlobal.
--    Each client DB will be updated in the loop above.
-- ============================================================
