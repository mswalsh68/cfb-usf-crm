-- ============================================================
-- CLEAR TEST DATA
-- Run each section against the correct database.
-- The seed global admin (admin@yourprogram.com) is preserved.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. CfbRoster  — run this block against CfbRoster
-- ────────────────────────────────────────────────────────────
USE CfbRoster;

DELETE FROM dbo.graduation_log;
DELETE FROM dbo.player_documents;
DELETE FROM dbo.player_stats;
DELETE FROM dbo.players;

PRINT 'CfbRoster cleared';
GO

-- ────────────────────────────────────────────────────────────
-- 2. CfbAlumni  — run this block against CfbAlumni
-- ────────────────────────────────────────────────────────────
USE CfbAlumni;

DELETE FROM dbo.outreach_messages;
DELETE FROM dbo.outreach_campaigns;
DELETE FROM dbo.interaction_log;
DELETE FROM dbo.alumni;

PRINT 'CfbAlumni cleared';
GO

-- ────────────────────────────────────────────────────────────
-- 3. CfbGlobal  — run this block against CfbGlobal
--    Keeps the seed admin account (admin@yourprogram.com)
-- ────────────────────────────────────────────────────────────
USE CfbGlobal;

DELETE FROM dbo.invite_tokens;
DELETE FROM dbo.password_reset_tokens;
DELETE FROM dbo.refresh_tokens;
DELETE FROM dbo.audit_log;
DELETE FROM dbo.app_permissions
WHERE user_id != (SELECT id FROM dbo.users WHERE email = 'admin@yourprogram.com');
DELETE FROM dbo.users
WHERE email != 'admin@yourprogram.com';

PRINT 'CfbGlobal cleared (seed admin preserved)';
GO
