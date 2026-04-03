-- ============================================================
-- CLEAR TEST DATA — Single AppDB Architecture
-- Run each section against the correct database in SSMS.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. USFBullsApp — clears all roster + alumni data
-- ────────────────────────────────────────────────────────────
USE USFBullsApp;

DELETE FROM roster.graduation_log;
DELETE FROM roster.player_documents;
DELETE FROM roster.player_stats;
DELETE FROM roster.players;
DELETE FROM alumni.outreach_messages;
DELETE FROM alumni.outreach_campaigns;
DELETE FROM alumni.interaction_log;
DELETE FROM alumni.alumni;

PRINT 'USFBullsApp cleared';
GO

-- ────────────────────────────────────────────────────────────
-- 2. PHSPanthersApp — clears all roster + alumni data
-- ────────────────────────────────────────────────────────────
USE PHSPanthersApp;

DELETE FROM roster.graduation_log;
DELETE FROM roster.player_documents;
DELETE FROM roster.player_stats;
DELETE FROM roster.players;
DELETE FROM alumni.outreach_messages;
DELETE FROM alumni.outreach_campaigns;
DELETE FROM alumni.interaction_log;
DELETE FROM alumni.alumni;

PRINT 'PHSPanthersApp cleared';
GO

-- ────────────────────────────────────────────────────────────
-- 3. CfbGlobal — clears users, tokens, audit log
--    Keeps platform_owner account(s) intact
-- ────────────────────────────────────────────────────────────
USE CfbGlobal;

DELETE FROM dbo.invite_tokens;
DELETE FROM dbo.refresh_tokens;
DELETE FROM dbo.audit_log;
-- Delete all app_permissions — covers both user_id and granted_by FK references
DELETE FROM dbo.app_permissions;
DELETE FROM dbo.user_teams
WHERE user_id IN (
  SELECT id FROM dbo.users WHERE global_role != 'platform_owner'
);
DELETE FROM dbo.users
WHERE global_role != 'platform_owner';

PRINT 'CfbGlobal cleared (platform_owner accounts preserved)';
GO
