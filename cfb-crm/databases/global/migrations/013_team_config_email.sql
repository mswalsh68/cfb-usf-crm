-- ============================================================
-- 013_team_config_email.sql
-- Adds email branding and governance columns to team_config.
-- ============================================================

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'team_config' AND COLUMN_NAME = 'email_from_address')
  ALTER TABLE dbo.team_config ADD email_from_address NVARCHAR(255) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'team_config' AND COLUMN_NAME = 'email_from_name')
  ALTER TABLE dbo.team_config ADD email_from_name NVARCHAR(200) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'team_config' AND COLUMN_NAME = 'email_reply_to')
  ALTER TABLE dbo.team_config ADD email_reply_to NVARCHAR(255) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'team_config' AND COLUMN_NAME = 'email_physical_address')
  ALTER TABLE dbo.team_config ADD email_physical_address NVARCHAR(500) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'team_config' AND COLUMN_NAME = 'email_daily_send_limit')
  ALTER TABLE dbo.team_config ADD email_daily_send_limit INT NOT NULL DEFAULT 500;
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'team_config' AND COLUMN_NAME = 'email_monthly_send_limit')
  ALTER TABLE dbo.team_config ADD email_monthly_send_limit INT NOT NULL DEFAULT 5000;
GO
