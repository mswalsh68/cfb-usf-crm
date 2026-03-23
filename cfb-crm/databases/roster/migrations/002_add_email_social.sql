-- ============================================================
-- ROSTER DB — Migration 002
-- Adds email, instagram, twitter, snapchat to players table
-- Run on: CfbRoster database
-- ============================================================

ALTER TABLE dbo.players
  ADD email     NVARCHAR(255) NULL,
      instagram NVARCHAR(100) NULL,
      twitter   NVARCHAR(100) NULL,
      snapchat  NVARCHAR(100) NULL;
GO
