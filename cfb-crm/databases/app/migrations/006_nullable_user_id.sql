-- ============================================================
-- APP DB — MIGRATION 006: Make roster.players.user_id nullable
-- Run on: each tenant AppDB (USFBullsApp, PHSPanthersApp)
-- Run after: 005_rls_policies.sql
--
-- Bulk player imports create player records before user accounts
-- exist. user_id is set when the player accepts their invite.
-- ============================================================

USE USFBullsApp; -- change to target DB before running

-- RLS policy references user_id — must drop/recreate around the ALTER
ALTER SECURITY POLICY dbo.roster_security_policy WITH (STATE = OFF);
DROP SECURITY POLICY dbo.roster_security_policy;

-- Drop explicit unique index if it exists
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_players_user_id' AND object_id = OBJECT_ID('roster.players'))
  DROP INDEX idx_players_user_id ON roster.players;

-- Drop system-generated unique constraint on user_id (created by inline UNIQUE in 001)
DECLARE @uqName NVARCHAR(200);
SELECT @uqName = name FROM sys.indexes
WHERE object_id = OBJECT_ID('roster.players') AND is_unique = 1 AND is_primary_key = 0
  AND name LIKE 'UQ__players__%';
IF @uqName IS NOT NULL
  EXEC('ALTER TABLE roster.players DROP CONSTRAINT ' + @uqName);

ALTER TABLE roster.players ALTER COLUMN user_id UNIQUEIDENTIFIER NULL;

-- Filtered index — only indexes rows that have a user linked
CREATE INDEX idx_players_user_id ON roster.players(user_id)
  WHERE user_id IS NOT NULL;

-- Re-activate RLS policy
CREATE SECURITY POLICY dbo.roster_security_policy
  ADD FILTER PREDICATE dbo.fn_roster_access(
    CAST(SESSION_CONTEXT(N'user_id')   AS NVARCHAR(100)),
    CAST(SESSION_CONTEXT(N'user_role') AS NVARCHAR(50)),
    sport_id,
    user_id,
    user_classification
  ) ON roster.players
WITH (STATE = ON);

PRINT '006_nullable_user_id complete';
GO
