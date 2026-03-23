-- ============================================================
-- Migration 003: Invite Tokens
-- Supports the invite-based onboarding flow where admins create
-- user accounts and share a one-time link for password setup.
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'invite_tokens' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.invite_tokens (
    id           INT             IDENTITY(1,1) PRIMARY KEY,
    user_id      UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id),
    token_hash   VARCHAR(128)    NOT NULL UNIQUE,   -- sha256 of the raw token
    expires_at   DATETIME2       NOT NULL,
    used_at      DATETIME2       NULL,
    created_at   DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME()
  );

  CREATE INDEX IX_invite_tokens_token_hash ON dbo.invite_tokens(token_hash);
  CREATE INDEX IX_invite_tokens_user_id    ON dbo.invite_tokens(user_id);

  PRINT 'Created invite_tokens table';
END
ELSE
  PRINT 'invite_tokens table already exists — skipping';
GO
