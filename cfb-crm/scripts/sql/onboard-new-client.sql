-- ============================================================
-- Onboard New Client - Single AppDB Architecture
-- Run against: CfbGlobal. Safe to run twice (idempotent).
-- ============================================================

USE CfbGlobal;
GO

-- ADMIN: Set these before running
DECLARE @ClientCode  NVARCHAR(10)  = 'HSFC';
DECLARE @ClientName  NVARCHAR(100) = 'Hillsborough High School Football';
DECLARE @ClientAbbr  NVARCHAR(10)  = 'HSFC';
DECLARE @AppDbName   NVARCHAR(150) = 'PHSPanthersApp';
DECLARE @Sport       NVARCHAR(50)  = 'football';
DECLARE @Level       NVARCHAR(20)  = 'high_school';
DECLARE @DbServer    NVARCHAR(200) = 'localhost\SQLEXPRESS';
DECLARE @sql         NVARCHAR(MAX);

-- 1. Validate inputs
IF @ClientCode IS NULL OR LEN(LTRIM(RTRIM(@ClientCode))) = 0
  THROW 50001, '@ClientCode is required.', 1;
IF @Level NOT IN ('college', 'high_school', 'club')
  THROW 50002, '@Level must be college, high_school, or club.', 1;

-- 2. Create AppDB
SET @sql = N'IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N''' + @AppDbName + N''')
  CREATE DATABASE [' + @AppDbName + N'];';
EXEC sp_executesql @sql;
PRINT 'AppDB ' + @AppDbName + ' ready.';
GO

-- re-declare after GO
DECLARE @ClientCode  NVARCHAR(10)  = 'HSFC';
DECLARE @ClientName  NVARCHAR(100) = 'Hillsborough High School Football';
DECLARE @ClientAbbr  NVARCHAR(10)  = 'HSFC';
DECLARE @AppDbName   NVARCHAR(150) = 'PHSPanthersApp';
DECLARE @Sport       NVARCHAR(50)  = 'football';
DECLARE @Level       NVARCHAR(20)  = 'high_school';
DECLARE @DbServer    NVARCHAR(200) = 'localhost\SQLEXPRESS';

-- 3+4. Run schema + SPs on the AppDB (do this before step 5):
--   Invoke-Sqlcmd -ServerInstance 'localhost\SQLEXPRESS' -Database 'PlantPanthersApp' `
--     -InputFile '.\databases\app\migrations\001_app_db_schema.sql'
--   Invoke-Sqlcmd -ServerInstance 'localhost\SQLEXPRESS' -Database 'PlantPanthersApp' `
--     -InputFile '.\databases\app\stored-procedures\sp_App_AllProcedures.sql'

-- 5. Register team in CfbGlobal.dbo.teams
IF NOT EXISTS (SELECT 1 FROM dbo.teams WHERE abbr = @ClientAbbr)
BEGIN
  INSERT INTO dbo.teams (name, abbr, sport, level, app_db, db_server)
  VALUES (@ClientName, @ClientAbbr, @Sport, @Level, @AppDbName, @DbServer);
  PRINT 'Registered team ' + @ClientAbbr;
END
ELSE
BEGIN
  UPDATE dbo.teams SET app_db = @AppDbName WHERE abbr = @ClientAbbr;
  PRINT 'Team already exists - updated app_db.';
END

-- 6. Seed team_config
DECLARE @TeamId UNIQUEIDENTIFIER = (SELECT id FROM dbo.teams WHERE abbr = @ClientAbbr);
IF @TeamId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.team_config WHERE team_id = @TeamId)
BEGIN
  INSERT INTO dbo.team_config (team_id, sport, level)
  VALUES (@TeamId, @Sport, @Level);
  PRINT 'Seeded team_config for ' + @ClientAbbr;
END
ELSE
  PRINT 'team_config already exists - skipping';
GO

PRINT '=== Onboarding complete ===';
PRINT 'Next: create admin user via platform admin UI or sp_CreateUser';
GO
