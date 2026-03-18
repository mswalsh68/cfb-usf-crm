-- ============================================================
-- ALUMNI DATABASE SCHEMA
-- Azure SQL Server (separate instance from Roster DB)
-- Purpose: Alumni CRM and outreach tracking
-- ============================================================

-- ─── Alumni ──────────────────────────────────────────────────
CREATE TABLE alumni (
  id                    UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  user_id               UNIQUEIDENTIFIER  NOT NULL UNIQUE, -- FK to global.users (logical)
  source_player_id      UNIQUEIDENTIFIER  NOT NULL,        -- original roster player id
  first_name            NVARCHAR(100)     NOT NULL,
  last_name             NVARCHAR(100)     NOT NULL,
  graduation_year       SMALLINT          NOT NULL,
  graduation_semester   NVARCHAR(10)      NOT NULL
                          CHECK (graduation_semester IN ('spring','fall','summer')),
  position              NVARCHAR(10)      NOT NULL,
  recruiting_class      SMALLINT          NOT NULL,
  status                NVARCHAR(20)      NOT NULL DEFAULT 'active'
                          CHECK (status IN ('active','lostContact','deceased','doNotContact')),
  -- Post-graduation contact
  personal_email        NVARCHAR(255),
  phone                 NVARCHAR(20),
  linkedin_url          NVARCHAR(500),
  -- Career info
  current_employer      NVARCHAR(200),
  current_job_title     NVARCHAR(150),
  current_city          NVARCHAR(100),
  current_state         NVARCHAR(50),
  current_country       NVARCHAR(100)     DEFAULT 'USA',
  -- Engagement
  is_donor              BIT               NOT NULL DEFAULT 0,
  last_donation_date    DATE,
  total_donations       DECIMAL(10,2)     DEFAULT 0,
  engagement_score      TINYINT           DEFAULT 50, -- 0-100
  notes                 NVARCHAR(MAX),
  created_at            DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at            DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ─── Outreach Campaigns ───────────────────────────────────────
CREATE TABLE outreach_campaigns (
  id                UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  name              NVARCHAR(200)     NOT NULL,
  description       NVARCHAR(MAX),
  target_audience   NVARCHAR(20)      NOT NULL DEFAULT 'all'
                      CHECK (target_audience IN ('all','byClass','byPosition','byStatus','custom')),
  audience_filters  NVARCHAR(MAX),    -- JSON blob of filter criteria
  status            NVARCHAR(20)      NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft','scheduled','active','completed','cancelled')),
  scheduled_at      DATETIME2,
  completed_at      DATETIME2,
  created_by        UNIQUEIDENTIFIER  NOT NULL,  -- user_id
  created_at        DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at        DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ─── Outreach Messages ────────────────────────────────────────
CREATE TABLE outreach_messages (
  id            UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  campaign_id   UNIQUEIDENTIFIER  NOT NULL REFERENCES outreach_campaigns(id),
  alumni_id     UNIQUEIDENTIFIER  NOT NULL REFERENCES alumni(id),
  channel       NVARCHAR(10)      NOT NULL
                  CHECK (channel IN ('email','sms','push')),
  status        NVARCHAR(20)      NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','sent','responded','bounced','unsubscribed')),
  content       NVARCHAR(MAX),
  sent_at       DATETIME2,
  opened_at     DATETIME2,
  responded_at  DATETIME2,
  created_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ─── Alumni Interaction Log ───────────────────────────────────
CREATE TABLE interaction_log (
  id            UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  alumni_id     UNIQUEIDENTIFIER  NOT NULL REFERENCES alumni(id) ON DELETE CASCADE,
  logged_by     UNIQUEIDENTIFIER  NOT NULL,  -- user_id of staff member
  channel       NVARCHAR(30)      NOT NULL,  -- 'phone','email','in_person','event', etc.
  summary       NVARCHAR(MAX)     NOT NULL,
  outcome       NVARCHAR(50),
  follow_up_at  DATETIME2,
  logged_at     DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ─── Indexes ──────────────────────────────────────────────────
CREATE INDEX idx_alumni_user_id         ON alumni(user_id);
CREATE INDEX idx_alumni_grad_year       ON alumni(graduation_year);
CREATE INDEX idx_alumni_status          ON alumni(status);
CREATE INDEX idx_alumni_is_donor        ON alumni(is_donor);
CREATE INDEX idx_alumni_engagement      ON alumni(engagement_score DESC);
CREATE INDEX idx_campaigns_status       ON outreach_campaigns(status);
CREATE INDEX idx_messages_campaign      ON outreach_messages(campaign_id);
CREATE INDEX idx_messages_alumni        ON outreach_messages(alumni_id);
CREATE INDEX idx_interactions_alumni    ON interaction_log(alumni_id);
