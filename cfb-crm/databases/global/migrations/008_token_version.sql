-- ============================================================
-- Migration 008: Per-user token version for session revocation
-- Run on: CfbGlobal database
-- ============================================================

ALTER TABLE dbo.users
  ADD token_version INT NOT NULL DEFAULT 1;
GO
