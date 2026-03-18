-- ============================================================
-- GLOBAL DATABASE SCHEMA
-- Azure SQL Server
-- Purpose: Identity, authentication, role-based permissions
-- ============================================================

-- ─── Users ───────────────────────────────────────────────────
CREATE TABLE users (
  id            UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  email         NVARCHAR(255)     NOT NULL UNIQUE,
  password_hash NVARCHAR(255)     NOT NULL,
  first_name    NVARCHAR(100)     NOT NULL,
  last_name     NVARCHAR(100)     NOT NULL,
  global_role   NVARCHAR(50)      NOT NULL DEFAULT 'readonly'
                  CHECK (global_role IN (
                    'global_admin','app_admin','coach_staff','player','readonly'
                  )),
  is_active     BIT               NOT NULL DEFAULT 1,
  last_login_at DATETIME2,
  created_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ─── App Permissions ──────────────────────────────────────────
-- Each row grants a user access to a specific app at a specific role level.
-- A user can have different roles in each app.
CREATE TABLE app_permissions (
  id            UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  user_id       UNIQUEIDENTIFIER  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  app_name      NVARCHAR(50)      NOT NULL
                  CHECK (app_name IN ('roster','alumni','global-admin')),
  role          NVARCHAR(50)      NOT NULL
                  CHECK (role IN (
                    'global_admin','app_admin','coach_staff','player','readonly'
                  )),
  granted_by    UNIQUEIDENTIFIER  NOT NULL REFERENCES users(id),
  granted_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
  revoked_at    DATETIME2,        -- NULL means currently active
  CONSTRAINT uq_user_app UNIQUE (user_id, app_name)
);

-- ─── Refresh Tokens ───────────────────────────────────────────
CREATE TABLE refresh_tokens (
  id            UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  user_id       UNIQUEIDENTIFIER  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash    NVARCHAR(255)     NOT NULL UNIQUE,
  expires_at    DATETIME2         NOT NULL,
  revoked_at    DATETIME2,
  device_info   NVARCHAR(255),
  created_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ─── Audit Log ────────────────────────────────────────────────
-- Immutable log of all permission changes and sensitive actions.
CREATE TABLE audit_log (
  id            UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  actor_id      UNIQUEIDENTIFIER  REFERENCES users(id),
  actor_email   NVARCHAR(255),    -- denormalized in case user is deleted
  action        NVARCHAR(100)     NOT NULL,
  target_type   NVARCHAR(50),     -- 'user','permission','player', etc.
  target_id     NVARCHAR(255),
  payload       NVARCHAR(MAX),    -- JSON blob of before/after state
  ip_address    NVARCHAR(50),
  performed_at  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ─── Password Reset Tokens ────────────────────────────────────
CREATE TABLE password_reset_tokens (
  id            UNIQUEIDENTIFIER  DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
  user_id       UNIQUEIDENTIFIER  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash    NVARCHAR(255)     NOT NULL UNIQUE,
  expires_at    DATETIME2         NOT NULL,
  used_at       DATETIME2,
  created_at    DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ─── Indexes ──────────────────────────────────────────────────
CREATE INDEX idx_users_email            ON users(email);
CREATE INDEX idx_users_global_role      ON users(global_role);
CREATE INDEX idx_app_permissions_user   ON app_permissions(user_id);
CREATE INDEX idx_app_permissions_app    ON app_permissions(app_name);
CREATE INDEX idx_refresh_tokens_user    ON refresh_tokens(user_id);
CREATE INDEX idx_audit_actor            ON audit_log(actor_id);
CREATE INDEX idx_audit_performed_at     ON audit_log(performed_at DESC);

-- ─── Seed: First Global Admin ─────────────────────────────────
-- Password: Change_Me_On_First_Login!  (bcrypt hashed below is a placeholder)
-- Run update-password script after first deploy to set a real password.
INSERT INTO users (email, password_hash, first_name, last_name, global_role)
VALUES (
  'admin@yourprogram.com',
  '$2b$12$PLACEHOLDER_CHANGE_THIS_HASH_BEFORE_DEPLOYING_TO_PROD',
  'Global',
  'Admin',
  'global_admin'
);
