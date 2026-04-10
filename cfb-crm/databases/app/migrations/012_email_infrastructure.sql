-- ============================================================
-- 012_email_infrastructure.sql
-- Adds email dispatch columns to outreach tables, email
-- unsubscribes store, feed posts, and read receipts.
-- ============================================================

-- Extend outreach_campaigns with email fields
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'subject_line')
  ALTER TABLE dbo.outreach_campaigns ADD subject_line NVARCHAR(500) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'body_html')
  ALTER TABLE dbo.outreach_campaigns ADD body_html NVARCHAR(MAX) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'from_name')
  ALTER TABLE dbo.outreach_campaigns ADD from_name NVARCHAR(200) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'reply_to_email')
  ALTER TABLE dbo.outreach_campaigns ADD reply_to_email NVARCHAR(255) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'campaign_type')
  ALTER TABLE dbo.outreach_campaigns ADD campaign_type NVARCHAR(20) NOT NULL DEFAULT 'outreach';
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'physical_address')
  ALTER TABLE dbo.outreach_campaigns ADD physical_address NVARCHAR(500) NULL;
GO

-- Extend outreach_campaigns audience type
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'started_at')
  ALTER TABLE dbo.outreach_campaigns ADD started_at DATETIME2 NULL;
GO

-- Extend outreach_messages with email dispatch fields
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_messages' AND COLUMN_NAME = 'email_address')
  ALTER TABLE dbo.outreach_messages ADD email_address NVARCHAR(255) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_messages' AND COLUMN_NAME = 'unsubscribe_token')
  ALTER TABLE dbo.outreach_messages ADD unsubscribe_token UNIQUEIDENTIFIER NULL;
GO

-- email_unsubscribes: CAN-SPAM opt-out store
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'email_unsubscribes' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.email_unsubscribes (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    user_id         UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
    token           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    channel         NVARCHAR(20)     NOT NULL DEFAULT 'email',
    unsubscribed_at DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_unsub_user_channel UNIQUE (user_id, channel)
  );
  CREATE UNIQUE INDEX uix_email_unsubscribes_token ON dbo.email_unsubscribes(token);
END
GO

-- feed_posts: newsfeed posts per tenant
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'feed_posts' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.feed_posts (
    id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    created_by      UNIQUEIDENTIFIER NOT NULL,
    title           NVARCHAR(300)    NULL,
    body_html       NVARCHAR(MAX)    NOT NULL,
    audience        NVARCHAR(30)     NOT NULL DEFAULT 'all',
    audience_json   NVARCHAR(MAX)    NULL,
    sport_id        UNIQUEIDENTIFIER NULL REFERENCES dbo.sports(id),
    is_pinned       BIT              NOT NULL DEFAULT 0,
    is_welcome_post BIT              NOT NULL DEFAULT 0,
    campaign_id     UNIQUEIDENTIFIER NULL REFERENCES dbo.outreach_campaigns(id),
    published_at    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    created_at      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX idx_feed_posts_audience ON dbo.feed_posts(audience);
  CREATE INDEX idx_feed_posts_sport    ON dbo.feed_posts(sport_id);
  CREATE INDEX idx_feed_posts_pinned   ON dbo.feed_posts(is_pinned, published_at DESC);
END
GO

-- feed_post_reads: read receipts
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'feed_post_reads' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.feed_post_reads (
    id      UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    post_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.feed_posts(id) ON DELETE CASCADE,
    user_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id),
    read_at DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_post_read UNIQUE (post_id, user_id)
  );
  CREATE INDEX idx_feed_reads_post ON dbo.feed_post_reads(post_id);
  CREATE INDEX idx_feed_reads_user ON dbo.feed_post_reads(user_id);
END
GO
