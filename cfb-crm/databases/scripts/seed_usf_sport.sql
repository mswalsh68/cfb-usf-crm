-- ============================================================
-- SEED: USF Football Sport + User Roles
-- Run on: USFBullsApp after 003_rbac_infrastructure.sql
--         and 004_add_sport_classification.sql
--
-- What this does:
--   1. Creates the Football sport in dbo.sports (idempotent)
--   2. Assigns sport_id to all existing players and alumni
--      (removes the NULL sport_id transition bypass in RLS)
--   3. Grants coach_admin to ALL existing users in CfbGlobal
--      so they can access data while sport-scoped RBAC builds out
--
-- After running this seed, the RLS transition bypass (sport_id IS NULL)
-- will no longer fire and proper sport-scoped access takes over.
-- ============================================================

USE USFBullsApp;
GO

DECLARE @SportId UNIQUEIDENTIFIER;

-- ─── 1. Create Football sport ─────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM dbo.sports WHERE abbr = 'FB')
BEGIN
  SET @SportId = NEWID();
  INSERT INTO dbo.sports (id, name, abbr, is_active)
  VALUES (@SportId, 'Football', 'FB', 1);
  PRINT 'Created Football sport: ' + CAST(@SportId AS NVARCHAR(50));
END
ELSE
BEGIN
  SELECT @SportId = id FROM dbo.sports WHERE abbr = 'FB';
  PRINT 'Football sport already exists: ' + CAST(@SportId AS NVARCHAR(50));
END

-- ─── 2. Assign sport_id to all existing rows ─────────────────
-- This eliminates the NULL sport_id transition bypass in RLS.
-- After this runs, access is governed purely by dbo.user_roles.

UPDATE roster.players SET sport_id = @SportId WHERE sport_id IS NULL;
PRINT 'Updated ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' player(s) with sport_id';

UPDATE alumni.alumni SET sport_id = @SportId WHERE sport_id IS NULL;
PRINT 'Updated ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' alumni with sport_id';

-- ─── 3. Grant coach_admin to all existing global users ────────
-- Cross-DB query: pulls user IDs from CfbGlobal.dbo.users
-- and inserts coach_admin roles for any not already assigned.
-- In production, revoke and reassign granular roles per user.

DECLARE @GrantCount INT = 0;

INSERT INTO dbo.user_roles (user_id, sport_id, role, granted_by)
SELECT
  u.id          AS user_id,
  @SportId      AS sport_id,
  'coach_admin' AS role,
  u.id          AS granted_by   -- self-bootstrapped
FROM LegacyLinkGlobal.dbo.users u
WHERE NOT EXISTS (
  SELECT 1 FROM dbo.user_roles ur
  WHERE ur.user_id  = u.id
    AND ur.sport_id = @SportId
);

SET @GrantCount = @@ROWCOUNT;
PRINT 'Granted coach_admin to ' + CAST(@GrantCount AS NVARCHAR(20)) + ' user(s)';

PRINT '';
PRINT '=== Seed complete ===';
PRINT 'All existing rows have sport_id assigned.';
PRINT 'All existing users have coach_admin for Football.';
PRINT 'RLS transition bypass is now inactive (sport_id IS NOT NULL on all rows).';
PRINT 'Adjust user roles per user via dbo.user_roles when ready to enforce RBAC.';
GO
