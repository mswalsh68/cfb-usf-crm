-- ============================================================
-- Migration 004: Multi-Tenant Architecture
-- Adds a teams table, links users to a team, seeds USF as
-- client #1. Supports SaaS / LegacyLink multi-tenant rollout.
-- Run after: 003_invite_tokens.sql
-- ============================================================

-- ─── 1. Create teams table ────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'teams' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.teams (
    id                UNIQUEIDENTIFIER  NOT NULL PRIMARY KEY DEFAULT NEWID(),
    name              NVARCHAR(100)     NOT NULL,
    abbr              NVARCHAR(10)      NOT NULL,
    sport             NVARCHAR(50)      NOT NULL DEFAULT 'football',
    level             NVARCHAR(20)      NOT NULL DEFAULT 'college'
                        CHECK (level IN ('college', 'high_school', 'club')),
    roster_db         NVARCHAR(100)     NOT NULL,
    alumni_db         NVARCHAR(100)     NOT NULL,
    db_server         NVARCHAR(200)     NOT NULL DEFAULT 'localhost\SQLEXPRESS',
    subscription_tier NVARCHAR(20)      NOT NULL DEFAULT 'starter'
                        CHECK (subscription_tier IN ('starter', 'pro', 'enterprise')),
    is_active         BIT               NOT NULL DEFAULT 1,
    created_at        DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    expires_at        DATETIME2         NULL
  );

  CREATE INDEX IX_teams_abbr      ON dbo.teams(abbr);
  CREATE INDEX IX_teams_is_active ON dbo.teams(is_active);

  PRINT 'Created teams table';
END
ELSE
  PRINT 'teams table already exists — skipping';
GO

-- ─── 2. Seed USF as client #1 ─────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM dbo.teams WHERE abbr = 'USF')
BEGIN
  INSERT INTO dbo.teams (name, abbr, sport, level, roster_db, alumni_db, db_server)
  VALUES (
    'University of South Florida Bulls',
    'USF',
    'football',
    'college',
    'CfbRoster',
    'CfbAlumni',
    'localhost\SQLEXPRESS'
  );
  PRINT 'Seeded USF as team #1';
END
ELSE
  PRINT 'USF team already exists — skipping';
GO

-- ─── 3. Add team_id FK to users ───────────────────────────────
IF NOT EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id = OBJECT_ID('dbo.users') AND name = 'team_id'
)
BEGIN
  ALTER TABLE dbo.users
  ADD team_id UNIQUEIDENTIFIER NULL
    CONSTRAINT FK_users_teams FOREIGN KEY REFERENCES dbo.teams(id);

  CREATE INDEX IX_users_team_id ON dbo.users(team_id);

  PRINT 'Added team_id to users table';
END
ELSE
  PRINT 'team_id column already exists on users — skipping';
GO

-- ─── 4. Assign all existing users to USF ──────────────────────
UPDATE dbo.users
SET    team_id = (SELECT id FROM dbo.teams WHERE abbr = 'USF')
WHERE  team_id IS NULL;

PRINT CAST(@@ROWCOUNT AS NVARCHAR(10)) + ' existing user(s) assigned to USF team';
GO
