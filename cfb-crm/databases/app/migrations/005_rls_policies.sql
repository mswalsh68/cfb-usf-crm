-- ============================================================
-- APP DB — ROW-LEVEL SECURITY POLICIES
-- Defense-in-depth: RLS acts as a safety net beneath stored
-- procedure role checks. Even if a SP has a bug, RLS prevents
-- unauthorized data from being returned.
--
-- SQL Server RLS pattern:
--   The filter function receives SESSION_CONTEXT values AND
--   the target table's columns as parameters. The function
--   body never references the table by name — columns are
--   bound via the CREATE SECURITY POLICY statement.
--
-- Run on: each tenant AppDB after 004_add_sport_classification.sql
-- ============================================================

-- ─── Drop existing policies before altering functions ─────────
-- (policies must be dropped before their predicate functions)

IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'roster_security_policy')
BEGIN
  DROP SECURITY POLICY dbo.roster_security_policy;
  PRINT 'Dropped roster_security_policy';
END

IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'alumni_security_policy')
BEGIN
  DROP SECURITY POLICY dbo.alumni_security_policy;
  PRINT 'Dropped alumni_security_policy';
END
GO

-- ─── RLS Filter Function: Roster ─────────────────────────────
-- Parameters from SESSION_CONTEXT: @session_user_id, @session_user_role
-- Parameters from the table row:   @row_sport_id, @row_user_id, @row_classification
--
-- Allows access if:
--   1. Caller is coach_admin or roster_only_admin for this sport, OR
--   2. Caller IS the player (their own row, classification = 'roster')
-- Alumni users always get ZERO rows.

CREATE OR ALTER FUNCTION dbo.fn_roster_access(
  @session_user_id    NVARCHAR(100),   -- from SESSION_CONTEXT('user_id')
  @session_user_role  NVARCHAR(50),    -- from SESSION_CONTEXT('user_role')
  @row_sport_id       UNIQUEIDENTIFIER,
  @row_user_id        UNIQUEIDENTIFIER,
  @row_classification NVARCHAR(20)
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
  SELECT 1 AS access_granted
  WHERE
    -- Admin roles with roster access to this sport
    EXISTS (
      SELECT 1 FROM dbo.user_roles ur
      WHERE ur.user_id    = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
        AND ur.sport_id   = @row_sport_id
        AND ur.role       IN ('coach_admin', 'roster_only_admin')
        AND ur.revoked_at IS NULL
    )
    OR
    -- Player may only see their own row
    (
      @row_user_id            = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
      AND @row_classification = 'roster'
    );
GO

-- ─── RLS Filter Function: Alumni ─────────────────────────────
-- Parameters from SESSION_CONTEXT: @session_user_id, @session_user_role
-- Parameters from the table row:   @row_sport_id, @row_user_id, @row_classification
--
-- Allows access if:
--   1. Caller is coach_admin for this sport
--      (roster_only_admin CANNOT see alumni — zero rows), OR
--   2. Caller IS the alumni member (their own row, classification = 'alumni')
-- Roster/player users always get ZERO rows.

CREATE OR ALTER FUNCTION dbo.fn_alumni_access(
  @session_user_id    NVARCHAR(100),
  @session_user_role  NVARCHAR(50),
  @row_sport_id       UNIQUEIDENTIFIER,
  @row_user_id        UNIQUEIDENTIFIER,
  @row_classification NVARCHAR(20)
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
  SELECT 1 AS access_granted
  WHERE
    -- Coach admin with alumni access for this sport only
    EXISTS (
      SELECT 1 FROM dbo.user_roles ur
      WHERE ur.user_id    = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
        AND ur.sport_id   = @row_sport_id
        AND ur.role       = 'coach_admin'
        AND ur.revoked_at IS NULL
    )
    OR
    -- Alumni may only see their own record (Starter tier)
    (
      @row_user_id            = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
      AND @row_classification = 'alumni'
    );
GO

-- ─── Activate Security Policies ──────────────────────────────
-- Binds SESSION_CONTEXT values + table columns to function params.

CREATE SECURITY POLICY dbo.roster_security_policy
  ADD FILTER PREDICATE dbo.fn_roster_access(
    CAST(SESSION_CONTEXT(N'user_id')   AS NVARCHAR(100)),  -- @session_user_id
    CAST(SESSION_CONTEXT(N'user_role') AS NVARCHAR(50)),   -- @session_user_role
    sport_id,              -- @row_sport_id        (roster.players column)
    user_id,               -- @row_user_id         (roster.players column)
    user_classification    -- @row_classification  (roster.players column)
  ) ON roster.players
WITH (STATE = ON);

PRINT 'Created and activated roster_security_policy on roster.players';

CREATE SECURITY POLICY dbo.alumni_security_policy
  ADD FILTER PREDICATE dbo.fn_alumni_access(
    CAST(SESSION_CONTEXT(N'user_id')   AS NVARCHAR(100)),  -- @session_user_id
    CAST(SESSION_CONTEXT(N'user_role') AS NVARCHAR(50)),   -- @session_user_role
    sport_id,              -- @row_sport_id        (alumni.alumni column)
    user_id,               -- @row_user_id         (alumni.alumni column)
    user_classification    -- @row_classification  (alumni.alumni column)
  ) ON alumni.alumni
WITH (STATE = ON);

PRINT 'Created and activated alumni_security_policy on alumni.alumni';

PRINT '=== 005_rls_policies complete ===';
PRINT 'RLS is now ACTIVE. All subsequent development and testing must run with RLS enforced.';
GO
