-- ============================================================
-- MIGRATION 005 — USER TEAMS (Multi-tenant junction table)
-- Run on: LegacyLinkGlobal database
-- Run after: 004_multi_tenant.sql
-- ============================================================
-- Changes:
--   1. Create dbo.user_teams — junction table (user ↔ team + role)
--   2. Add team_id FK to dbo.team_config (1 config row per team)
--   3. Backfill team_config.team_id from existing USF seed data
--   4. Backfill user_teams from users.team_id (existing rows)
--   5. Add 'platform_owner' as valid globalRole
--   6. Seed mswalsh68@gmail.com as platform_owner + user_teams for USF + HSFC
-- ============================================================
USE LegacyLinkGlobal
GO

-- ─── 1. user_teams junction table ────────────────────────────────────────────

IF NOT EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.TABLES
  WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'user_teams'
)
BEGIN
  CREATE TABLE dbo.user_teams (
    id         UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_user_teams PRIMARY KEY DEFAULT NEWID(),
    user_id    UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_user_teams_users REFERENCES dbo.users(id),
    team_id    UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_user_teams_teams REFERENCES dbo.teams(id),
    role       NVARCHAR(50)     NOT NULL DEFAULT 'readonly',
    is_active  BIT              NOT NULL DEFAULT 1,
    created_at DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_user_team UNIQUE (user_id, team_id)
  );

  CREATE INDEX IX_user_teams_user_id ON dbo.user_teams (user_id);
  CREATE INDEX IX_user_teams_team_id ON dbo.user_teams (team_id);

  PRINT 'Created dbo.user_teams';
END
ELSE
  PRINT 'dbo.user_teams already exists — skipping';
GO

-- ─── 2. Add team_id to team_config ───────────────────────────────────────────

IF NOT EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'team_config' AND COLUMN_NAME = 'team_id'
)
BEGIN
  ALTER TABLE dbo.team_config
    ADD team_id UNIQUEIDENTIFIER NULL
        CONSTRAINT FK_team_config_teams REFERENCES dbo.teams(id);

  CREATE UNIQUE INDEX UQ_team_config_team_id
    ON dbo.team_config (team_id)
    WHERE team_id IS NOT NULL;

  PRINT 'Added team_id to dbo.team_config';
END
ELSE
  PRINT 'team_config.team_id already exists — skipping';
GO

-- ─── 3. Backfill team_config.team_id → USF ───────────────────────────────────

DECLARE @UsfTeamId UNIQUEIDENTIFIER = (SELECT id FROM dbo.teams WHERE abbr = 'USF');

IF @UsfTeamId IS NOT NULL
BEGIN
  -- Link the existing config row (team_name = USF or first row) to USF team
  UPDATE dbo.team_config
  SET    team_id = @UsfTeamId
  WHERE  team_id IS NULL
    AND  id = (SELECT TOP 1 id FROM dbo.team_config ORDER BY created_at);

  PRINT 'Backfilled USF team_config.team_id';
END
ELSE
  PRINT 'USF team not found — skipping team_config backfill';
GO

-- ─── 4. Backfill user_teams from users.team_id ───────────────────────────────
-- For every user who already has team_id set, create a user_teams row.
-- Role defaults to their global_role (or 'readonly' if not admin).

INSERT INTO dbo.user_teams (user_id, team_id, role)
SELECT
  u.id,
  u.team_id,
  CASE u.global_role
    WHEN 'global_admin' THEN 'global_admin'
    WHEN 'app_admin'    THEN 'app_admin'
    WHEN 'coach_staff'  THEN 'coach_staff'
    ELSE 'readonly'
  END
FROM dbo.users u
WHERE u.team_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM dbo.user_teams ut
    WHERE ut.user_id = u.id AND ut.team_id = u.team_id
  );

PRINT CONCAT('Backfilled ', @@ROWCOUNT, ' user_teams row(s) from users.team_id');
GO

-- ─── 5. Add platform_owner to valid roles ────────────────────────────────────
-- No CHECK constraint exists on global_role — the SP validates it.
-- Just update the seed user here. sp_CreateUser is updated in the SP file.
-- (Nothing structural to change in schema for this step.)
PRINT 'platform_owner role is validated in stored procedures (no schema change needed)';
GO

-- ─── 6. Seed mswalsh68@gmail.com as platform_owner ───────────────────────────

DECLARE @PlatformUserId UNIQUEIDENTIFIER = (
  SELECT id FROM dbo.users WHERE email = 'mswalsh68@gmail.com'
);
DECLARE @UsfId  UNIQUEIDENTIFIER = (SELECT id FROM dbo.teams WHERE abbr = 'USF');
DECLARE @HsfcId UNIQUEIDENTIFIER = (SELECT id FROM dbo.teams WHERE abbr = 'HSFC');

IF @PlatformUserId IS NOT NULL
BEGIN
  -- Elevate to platform_owner
  UPDATE dbo.users
  SET    global_role = 'platform_owner',
         updated_at  = SYSUTCDATETIME()
  WHERE  id = @PlatformUserId;

  PRINT CONCAT('Set mswalsh68@gmail.com global_role = platform_owner (id: ', CAST(@PlatformUserId AS NVARCHAR(100)), ')');

  -- Ensure user_teams rows exist for both teams
  IF @UsfId IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM dbo.user_teams WHERE user_id = @PlatformUserId AND team_id = @UsfId
  )
  BEGIN
    INSERT INTO dbo.user_teams (user_id, team_id, role)
    VALUES (@PlatformUserId, @UsfId, 'global_admin');
    PRINT 'Added user_teams row: mswalsh68 → USF (global_admin)';
  END
  ELSE
  BEGIN
    -- Update existing row to global_admin if it exists but with lower role
    UPDATE dbo.user_teams
    SET role = 'global_admin'
    WHERE user_id = @PlatformUserId AND team_id = @UsfId;
    PRINT 'user_teams USF row already exists — ensured role = global_admin';
  END

  IF @HsfcId IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM dbo.user_teams WHERE user_id = @PlatformUserId AND team_id = @HsfcId
  )
  BEGIN
    INSERT INTO dbo.user_teams (user_id, team_id, role)
    VALUES (@PlatformUserId, @HsfcId, 'global_admin');
    PRINT 'Added user_teams row: mswalsh68 → HSFC (global_admin)';
  END
  ELSE
  BEGIN
    UPDATE dbo.user_teams
    SET role = 'global_admin'
    WHERE user_id = @PlatformUserId AND team_id = @HsfcId;
    PRINT 'user_teams HSFC row already exists — ensured role = global_admin';
  END
END
ELSE
  PRINT 'mswalsh68@gmail.com not found — skipping platform_owner seed';
GO

PRINT '=== Migration 005 complete ===';
GO
