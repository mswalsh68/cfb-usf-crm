-- ============================================================
-- APP DB — ROW-LEVEL SECURITY POLICIES
-- Defense-in-depth: RLS acts as a safety net beneath stored
-- procedure role checks. Even if a SP has a bug, RLS prevents
-- unauthorized data from being returned.
--
-- CRITICAL: Run this AFTER 003_rbac_infrastructure.sql and
-- 004_add_sport_classification.sql. RLS must be ACTIVE for all
-- subsequent development and testing. No exceptions.
--
-- Run on: each tenant AppDB
-- ============================================================

-- ─── RLS Filter Function: Roster ─────────────────────────────
-- Returns 1 (allow access) if:
--   1. Caller is a coach_admin or roster_only_admin for this sport, OR
--   2. Caller is the player (user_id matches, classification = 'roster')
-- Alumni users always get ZERO rows from this table.

IF OBJECT_ID('dbo.fn_roster_access') IS NOT NULL
  DROP FUNCTION dbo.fn_roster_access;
GO

CREATE FUNCTION dbo.fn_roster_access(@user_id NVARCHAR(100), @user_role NVARCHAR(50))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
  SELECT 1 AS access_granted
  WHERE
    -- Admin roles with roster access to this sport
    EXISTS (
      SELECT 1 FROM dbo.user_roles ur
      WHERE ur.user_id     = TRY_CAST(@user_id AS UNIQUEIDENTIFIER)
        AND ur.sport_id    = roster.players.sport_id
        AND ur.role        IN ('coach_admin', 'roster_only_admin')
        AND ur.revoked_at  IS NULL
    )
    OR
    -- Player accessing their own row only
    (
      roster.players.user_id            = TRY_CAST(@user_id AS UNIQUEIDENTIFIER)
      AND roster.players.user_classification = 'roster'
    );
GO

-- ─── RLS Filter Function: Alumni ─────────────────────────────
-- Returns 1 (allow access) if:
--   1. Caller is a coach_admin for this sport (roster_only_admin cannot see alumni), OR
--   2. Caller is the alumni member (user_id matches, classification = 'alumni')
-- Roster/player users always get ZERO rows from this table.

IF OBJECT_ID('dbo.fn_alumni_access') IS NOT NULL
  DROP FUNCTION dbo.fn_alumni_access;
GO

CREATE FUNCTION dbo.fn_alumni_access(@user_id NVARCHAR(100), @user_role NVARCHAR(50))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
  SELECT 1 AS access_granted
  WHERE
    -- Coach admin with alumni access for this sport
    EXISTS (
      SELECT 1 FROM dbo.user_roles ur
      WHERE ur.user_id    = TRY_CAST(@user_id AS UNIQUEIDENTIFIER)
        AND ur.sport_id   = alumni.alumni.sport_id
        AND ur.role       = 'coach_admin'
        AND ur.revoked_at IS NULL
    )
    OR
    -- Alumni accessing their own record only (Starter tier)
    (
      alumni.alumni.user_id              = TRY_CAST(@user_id AS UNIQUEIDENTIFIER)
      AND alumni.alumni.user_classification = 'alumni'
    );
GO

-- ─── Activate Security Policies ──────────────────────────────

-- Roster policy
IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'roster_security_policy')
BEGIN
  CREATE SECURITY POLICY dbo.roster_security_policy
    ADD FILTER PREDICATE dbo.fn_roster_access(
      CAST(SESSION_CONTEXT(N'user_id')   AS NVARCHAR(100)),
      CAST(SESSION_CONTEXT(N'user_role') AS NVARCHAR(50))
    ) ON roster.players
  WITH (STATE = ON);
  PRINT 'Created and activated roster_security_policy on roster.players';
END

-- Alumni policy
IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'alumni_security_policy')
BEGIN
  CREATE SECURITY POLICY dbo.alumni_security_policy
    ADD FILTER PREDICATE dbo.fn_alumni_access(
      CAST(SESSION_CONTEXT(N'user_id')   AS NVARCHAR(100)),
      CAST(SESSION_CONTEXT(N'user_role') AS NVARCHAR(50))
    ) ON alumni.alumni
  WITH (STATE = ON);
  PRINT 'Created and activated alumni_security_policy on alumni.alumni';
END

PRINT '=== 005_rls_policies complete ===';
PRINT 'RLS is now ACTIVE. All subsequent development and testing must run with RLS enforced.';
GO
