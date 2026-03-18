-- ============================================================
-- ROSTER DATABASE SCHEMA
-- Azure SQL Server (separate instance from Global DB)
-- Purpose: Current player roster CRM
-- ============================================================

-- ─── Players ─────────────────────────────────────────────────
CREATE TABLE players (
  id                      UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  user_id                 UNIQUEIDENTIFIER  NOT NULL UNIQUE, -- FK to global.users (logical, no hard constraint across DBs)
  jersey_number           TINYINT,
  first_name              NVARCHAR(100)     NOT NULL,
  last_name               NVARCHAR(100)     NOT NULL,
  position                NVARCHAR(10)      NOT NULL
                            CHECK (position IN ('QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH')),
  academic_year           NVARCHAR(20)
                            CHECK (academic_year IN ('freshman','sophomore','junior','senior','graduate')),
  status                  NVARCHAR(20)      NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active','injured','suspended','graduated','transferred','walkOn')),
  height_inches           TINYINT,
  weight_lbs              SMALLINT,
  home_town               NVARCHAR(100),
  home_state              NVARCHAR(50),
  high_school             NVARCHAR(150),
  recruiting_class        SMALLINT          NOT NULL,  -- year (e.g. 2022)
  gpa                     DECIMAL(3,2),
  major                   NVARCHAR(100),
  phone                   NVARCHAR(20),
  emergency_contact_name  NVARCHAR(150),
  emergency_contact_phone NVARCHAR(20),
  notes                   NVARCHAR(MAX),
  graduated_at            DATETIME2,        -- set when status = 'graduated'
  created_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ─── Player Stats ─────────────────────────────────────────────
CREATE TABLE player_stats (
  id          UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  player_id   UNIQUEIDENTIFIER  NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  season_year SMALLINT          NOT NULL,
  games_played TINYINT          DEFAULT 0,
  stats_json  NVARCHAR(MAX),    -- flexible JSON blob per position group
  created_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT uq_player_season UNIQUE (player_id, season_year)
);

-- ─── Player Documents ─────────────────────────────────────────
CREATE TABLE player_documents (
  id            UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  player_id     UNIQUEIDENTIFIER  NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  doc_type      NVARCHAR(50)      NOT NULL, -- 'eligibility','medical','academic', etc.
  file_name     NVARCHAR(255)     NOT NULL,
  azure_blob_url NVARCHAR(500)    NOT NULL,
  uploaded_by   UNIQUEIDENTIFIER  NOT NULL, -- user_id from global DB
  uploaded_at   DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  expires_at    DATETIME2
);

-- ─── Graduation Log ───────────────────────────────────────────
-- Tracks every graduation action for audit trail.
CREATE TABLE graduation_log (
  id                    UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  transaction_id        UNIQUEIDENTIFIER  NOT NULL,  -- groups a batch
  player_id             UNIQUEIDENTIFIER  NOT NULL REFERENCES players(id),
  graduation_year       SMALLINT          NOT NULL,
  graduation_semester   NVARCHAR(10)      NOT NULL
                          CHECK (graduation_semester IN ('spring','fall','summer')),
  triggered_by          UNIQUEIDENTIFIER  NOT NULL,  -- user_id
  status                NVARCHAR(20)      NOT NULL DEFAULT 'success'
                          CHECK (status IN ('success','failed','rolled_back')),
  notes                 NVARCHAR(MAX),
  performed_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ─── Indexes ──────────────────────────────────────────────────
CREATE INDEX idx_players_user_id        ON players(user_id);
CREATE INDEX idx_players_status         ON players(status);
CREATE INDEX idx_players_position       ON players(position);
CREATE INDEX idx_players_recruiting     ON players(recruiting_class);
CREATE INDEX idx_player_stats_player    ON player_stats(player_id);
CREATE INDEX idx_grad_log_transaction   ON graduation_log(transaction_id);
CREATE INDEX idx_grad_log_player        ON graduation_log(player_id);
