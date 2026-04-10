import { Router } from 'express';
import bcrypt from 'bcryptjs';
import path from 'path';
import fs from 'fs/promises';
import * as mssql from 'mssql';
import { requireAuth, requirePlatformOwner } from '../middleware/auth';
import { getDb, sql } from '../db';

function audit(event: string, details: Record<string, unknown>) {
  console.log(JSON.stringify({ type: 'AUDIT', event, timestamp: new Date().toISOString(), ...details }));
}

export const platformRouter = Router();

// All /platform routes require platform_owner role
platformRouter.use(requireAuth, requirePlatformOwner);

// ─── GET /platform/teams ──────────────────────────────────────────────────────
platformRouter.get('/teams', async (_req, res) => {
  try {
    const db = await getDb();
    const r  = await db.request()
      .input('IncludeInactive', sql.Bit, 1)
      .execute('dbo.sp_GetTeams');
    return res.json({ success: true, data: r.recordset });
  } catch (err) {
    console.error('[GET /platform/teams]', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// ─── PATCH /platform/teams/:id ────────────────────────────────────────────────
platformRouter.patch('/teams/:id', async (req, res) => {
  const { isActive, name, abbr, sport, level, subscriptionTier } = req.body;
  try {
    const db = await getDb();
    const r  = await db.request()
      .input('TeamId',          sql.UniqueIdentifier, req.params.id)
      .input('Name',            sql.NVarChar,         name             ?? null)
      .input('Abbr',            sql.NVarChar,         abbr             ?? null)
      .input('Sport',           sql.NVarChar,         sport            ?? null)
      .input('Level',           sql.NVarChar,         level            ?? null)
      .input('SubscriptionTier',sql.NVarChar,         subscriptionTier ?? null)
      .input('IsActive',        sql.Bit,              isActive         ?? null)
      .input('ActorId',         sql.UniqueIdentifier, req.user!.sub)
      .output('ErrorCode',      sql.NVarChar(50))
      .execute('dbo.sp_UpdateTeam');
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.json({ success: true, message: 'Team updated' });
  } catch (err) {
    console.error('[PATCH /platform/teams/:id]', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// ─── GET /platform/users/lookup ──────────────────────────────────────────────
// Look up an existing global user by email so platform owner can grant them
// admin access to a new client instead of creating a fresh account.
platformRouter.get('/users/lookup', async (req, res) => {
  const email = (req.query.email as string ?? '').trim().toLowerCase();
  if (!email) return res.status(400).json({ success: false, error: 'email query param required' });
  try {
    const db = await getDb();
    const r  = await db.request()
      .input('Email', sql.NVarChar, email)
      .query(`
        SELECT id, email, first_name AS firstName, last_name AS lastName,
               global_role AS globalRole, is_active AS isActive
        FROM   dbo.users
        WHERE  email = @Email
      `);
    if (!r.recordset.length) return res.status(404).json({ success: false, error: 'USER_NOT_FOUND' });
    return res.json({ success: true, data: r.recordset[0] });
  } catch (err) {
    console.error('[GET /platform/users/lookup]', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// ─── POST /platform/onboard-client ───────────────────────────────────────────
// Provisions a new client:
//   1. Registers team in LegacyLinkGlobal (sp_CreateTeam)
//   2. Creates AppDB and applies full schema + stored procedures
//   3. Seeds sport row and team_config
//   4. Creates or grants access to admin user
//
// adminMode:
//   'new'      — create a brand-new user account and grant global_admin
//   'existing' — look up an existing user by email and grant team access
platformRouter.post('/onboard-client', async (req, res) => {
  const {
    clientName,
    clientAbbr,
    appDbName,
    sport         = 'football',
    level         = 'college',
    colorPrimary  = '#1B1B2F',
    colorAccent   = '#B8973D',
    subscriptionTier = 'starter',
    dbServer,
    adminMode     = 'new',
    // new admin fields
    adminEmail,
    adminPassword,
    adminFirstName,
    adminLastName,
    // existing admin field
    existingAdminEmail,
  } = req.body;

  // ── Validation ──────────────────────────────────────────────────────────────
  if (!clientName || !clientAbbr || !appDbName) {
    return res.status(400).json({ success: false, error: 'clientName, clientAbbr, and appDbName are required' });
  }
  if (!/^[A-Za-z][A-Za-z0-9_]{0,149}$/.test(appDbName)) {
    return res.status(400).json({ success: false, error: 'appDbName must start with a letter and contain only letters, numbers, or underscores (max 150 chars)' });
  }
  if (!/^[A-Za-z0-9_]{1,10}$/.test(clientAbbr)) {
    return res.status(400).json({ success: false, error: 'clientAbbr must be 1–10 alphanumeric characters or underscores' });
  }
  if (!['college', 'high_school', 'club'].includes(level)) {
    return res.status(400).json({ success: false, error: 'level must be college, high_school, or club' });
  }
  if (!['new', 'existing'].includes(adminMode)) {
    return res.status(400).json({ success: false, error: 'adminMode must be new or existing' });
  }
  if (adminMode === 'new') {
    if (!adminEmail || !adminPassword || !adminFirstName || !adminLastName) {
      return res.status(400).json({ success: false, error: 'adminEmail, adminPassword, adminFirstName, adminLastName are required for adminMode=new' });
    }
    if (adminPassword.length < 10) {
      return res.status(400).json({ success: false, error: 'Admin password must be at least 10 characters' });
    }
  } else {
    if (!existingAdminEmail) {
      return res.status(400).json({ success: false, error: 'existingAdminEmail is required for adminMode=existing' });
    }
  }

  const serverName = (dbServer ?? process.env.DB_SERVER ?? 'localhost\\SQLEXPRESS').replace('\\\\', '\\');
  const safeDbName = appDbName.replace(/[^A-Za-z0-9_]/g, '');

  /** Creates a new connection pool to a specific database on the same server */
  const connectToDb = (database: string) => new mssql.ConnectionPool({
    server:   serverName,
    database,
    options:  { encrypt: false, trustServerCertificate: true },
    authentication: {
      type: 'default' as const,
      options: { userName: process.env.GLOBAL_DB_USER ?? '', password: process.env.GLOBAL_DB_PASS ?? '' },
    },
  }).connect();

  try {
    const db = await getDb();

    // ── Step 1: Register team in LegacyLinkGlobal ───────────────────────────
    let newTeamId: string;
    try {
      const teamR = await db.request()
        .input('Name',             sql.NVarChar,         clientName.trim())
        .input('Abbr',             sql.NVarChar,         clientAbbr.toUpperCase().trim())
        .input('Sport',            sql.NVarChar,         sport)
        .input('Level',            sql.NVarChar,         level)
        .input('AppDb',            sql.NVarChar,         safeDbName)
        .input('DbServer',         sql.NVarChar,         serverName)
        .input('SubscriptionTier', sql.NVarChar,         subscriptionTier)
        .input('CreatedBy',        sql.UniqueIdentifier, req.user!.sub)
        .output('NewTeamId',       sql.UniqueIdentifier)
        .output('ErrorCode',       sql.NVarChar(50))
        .execute('dbo.sp_CreateTeam');

      if (teamR.output.ErrorCode) {
        return res.status(400).json({ success: false, error: teamR.output.ErrorCode });
      }
      newTeamId = teamR.output.NewTeamId;
    } catch (err) {
      console.error('[onboard Step 1: sp_CreateTeam]', err);
      return res.status(500).json({ success: false, error: `Step 1 (register team) failed: ${err instanceof Error ? err.message : String(err)}` });
    }

    // ── Step 2: Create AppDB ─────────────────────────────────────────────────
    try {
      await db.request().query(`
        IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'${safeDbName}')
          CREATE DATABASE [${safeDbName}];
      `);
    } catch (err) {
      console.error('[onboard Step 2: CREATE DATABASE]', err);
      return res.status(500).json({ success: false, error: `Step 2 (create database "${safeDbName}") failed: ${err instanceof Error ? err.message : String(err)}` });
    }

    // ── Step 3: Apply AppDB schema + stored procedures ───────────────────────
    try {
      const appPool = await connectToDb(safeDbName);
      try {
        await applyAppDbSchema(appPool);
        await applyAppDbSps(appPool);
      } finally {
        await appPool.close();
      }
    } catch (err) {
      console.error('[onboard Step 3: apply schema]', err);
      return res.status(500).json({ success: false, error: `Step 3 (apply schema to "${safeDbName}") failed: ${err instanceof Error ? err.message : String(err)}` });
    }

    // ── Step 4: Seed all standard sports in AppDB ────────────────────────────
    // The AppDB is multi-sport — seed all common sports so coaches can use any.
    const ALL_SPORTS = [
      { name: 'Football',   abbr: 'FB' },
      { name: 'Basketball', abbr: 'BB' },
      { name: 'Baseball',   abbr: 'BA' },
      { name: 'Soccer',     abbr: 'SO' },
      { name: 'Softball',   abbr: 'SB' },
      { name: 'Volleyball', abbr: 'VB' },
      { name: 'Other',      abbr: 'OT' },
    ];
    try {
      const appPool2 = await connectToDb(safeDbName);
      try {
        for (const s of ALL_SPORTS) {
          await appPool2.request()
            .input('Abbr', sql.NVarChar, s.abbr)
            .input('Name', sql.NVarChar, s.name)
            .query(`
              IF NOT EXISTS (SELECT 1 FROM dbo.sports WHERE abbr = @Abbr)
                INSERT INTO dbo.sports (name, abbr) VALUES (@Name, @Abbr);
            `);
        }
      } finally {
        await appPool2.close();
      }
    } catch (err) {
      console.error('[onboard Step 4: seed sports]', err);
      return res.status(500).json({ success: false, error: `Step 4 (seed sports) failed: ${err instanceof Error ? err.message : String(err)}` });
    }

    // ── Step 5: Seed team_config in LegacyLinkGlobal ─────────────────────────
    try {
      await db.request()
        .input('TeamId',   sql.UniqueIdentifier, newTeamId)
        .input('TeamName', sql.NVarChar,         clientName.trim())
        .input('TeamAbbr', sql.NVarChar,         clientAbbr.toUpperCase().trim())
        .input('Sport',    sql.NVarChar,         sport)
        .input('Level',    sql.NVarChar,         level)
        .input('Primary',  sql.NVarChar,         colorPrimary ?? '#1B1B2F')
        .input('Accent',   sql.NVarChar,         colorAccent  ?? '#B8973D')
        .query(`
          IF NOT EXISTS (SELECT 1 FROM dbo.team_config WHERE team_id = @TeamId)
            INSERT INTO dbo.team_config (
              team_id, team_name, team_abbr, sport, level,
              color_primary, color_accent
            ) VALUES (
              @TeamId, @TeamName, @TeamAbbr, @Sport, @Level,
              @Primary, @Accent
            );
        `);
    } catch (err) {
      console.error('[onboard Step 5: seed team_config]', err);
      return res.status(500).json({ success: false, error: `Step 5 (seed team config) failed: ${err instanceof Error ? err.message : String(err)}` });
    }

    // ── Step 5b: Seed welcome post in AppDB ─────────────────────────────────
    // Welcome post uses white-label tokens substituted here before insert.
    // is_welcome_post = 1 so the check is idempotent on re-run.
    try {
      const welcomeTitle = `Welcome to ${clientName.trim()}!`;
      const welcomeBody  = `<p>Welcome to the <strong style="color:${colorPrimary}">${clientName.trim()}</strong> team portal. `
        + `This is your central hub for team news, roster information, and alumni connections.</p>`
        + `<p>Your coaching staff will use this feed to share updates, announcements, and highlights with you. `
        + `Check back regularly to stay in the loop.</p>`;
      const appPool3 = await connectToDb(safeDbName);
      try {
        await appPool3.request()
          .input('Title',    sql.NVarChar, welcomeTitle)
          .input('BodyHtml', sql.NVarChar, welcomeBody)
          .query(`
            IF NOT EXISTS (SELECT 1 FROM dbo.feed_posts WHERE is_welcome_post = 1)
              INSERT INTO dbo.feed_posts (created_by, title, body_html, audience, is_pinned, is_welcome_post)
              VALUES ('00000000-0000-0000-0000-000000000000', @Title, @BodyHtml, 'all', 1, 1);
          `);
      } finally {
        await appPool3.close();
      }
    } catch (err) {
      console.error('[onboard Step 5b: seed welcome post]', err);
      // Non-fatal — log and continue
    }

    // ── Step 6: Handle admin user ────────────────────────────────────────────
    let resolvedAdminEmail: string;

    if (adminMode === 'new') {
      resolvedAdminEmail = adminEmail.trim().toLowerCase();
      const passwordHash = await bcrypt.hash(adminPassword, 12);

      const userR = await db.request()
        .input('Email',        sql.NVarChar,         resolvedAdminEmail)
        .input('PasswordHash', sql.NVarChar,         passwordHash)
        .input('FirstName',    sql.NVarChar,         adminFirstName.trim())
        .input('LastName',     sql.NVarChar,         adminLastName.trim())
        .input('GlobalRole',   sql.NVarChar,         'global_admin')
        .input('CreatedBy',    sql.UniqueIdentifier, req.user!.sub)
        .input('TeamId',       sql.UniqueIdentifier, newTeamId)
        .input('GrantAppName', sql.NVarChar,         'roster')
        .input('GrantAppRole', sql.NVarChar,         'global_admin')
        .output('NewUserId',   sql.UniqueIdentifier)
        .output('ErrorCode',   sql.NVarChar(50))
        .execute('dbo.sp_CreateUser');

      if (userR.output.ErrorCode && userR.output.ErrorCode !== 'EMAIL_ALREADY_EXISTS') {
        return res.status(400).json({ success: false, error: `Admin creation failed: ${userR.output.ErrorCode}` });
      }

      // If email already existed, still grant them team access
      if (userR.output.ErrorCode === 'EMAIL_ALREADY_EXISTS') {
        await grantExistingUserTeamAccess(db, resolvedAdminEmail, newTeamId, req.user!.sub);
      }

    } else {
      // Existing user — look up + grant access
      resolvedAdminEmail = existingAdminEmail.trim().toLowerCase();
      const existingUserErr = await grantExistingUserTeamAccess(db, resolvedAdminEmail, newTeamId, req.user!.sub);
      if (existingUserErr) {
        return res.status(400).json({ success: false, error: existingUserErr });
      }
    }

    audit('CLIENT_ONBOARDED', {
      actorId: req.user!.sub,
      teamId:  newTeamId,
      clientAbbr,
      appDbName: safeDbName,
      adminMode,
      adminEmail: resolvedAdminEmail,
    });

    return res.status(201).json({
      success: true,
      data: {
        teamId:     newTeamId,
        appDb:      safeDbName,
        adminEmail: resolvedAdminEmail,
        adminMode,
        message: `${clientName.trim()} provisioned. ${adminMode === 'new' ? 'Admin account created' : 'Access granted to existing user'} — ${resolvedAdminEmail}.`,
      },
    });

  } catch (err) {
    console.error('[POST /platform/onboard-client]', err);
    return res.status(500).json({ success: false, error: 'Server error during onboarding' });
  }
});

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Grant an existing global user admin access to a team + app permissions */
async function grantExistingUserTeamAccess(
  db:        mssql.ConnectionPool,
  email:     string,
  teamId:    string,
  actorId:   string,
): Promise<string | null> {
  const userR = await db.request()
    .input('Email', sql.NVarChar, email)
    .query(`SELECT id FROM dbo.users WHERE email = @Email AND is_active = 1`);

  if (!userR.recordset.length) return 'USER_NOT_FOUND';

  const userId: string = userR.recordset[0].id;

  // Grant team membership (idempotent)
  await db.request()
    .input('UserId', sql.UniqueIdentifier, userId)
    .input('TeamId', sql.UniqueIdentifier, teamId)
    .query(`
      IF NOT EXISTS (SELECT 1 FROM dbo.user_teams WHERE user_id = @UserId AND team_id = @TeamId)
        INSERT INTO dbo.user_teams (user_id, team_id, role) VALUES (@UserId, @TeamId, 'global_admin');
    `);

  // Grant app_permissions (idempotent via revoke-then-insert)
  for (const appName of ['roster', 'alumni']) {
    await db.request()
      .input('UserId',  sql.UniqueIdentifier, userId)
      .input('AppName', sql.NVarChar,         appName)
      .input('ActorId', sql.UniqueIdentifier, actorId)
      .query(`
        UPDATE dbo.app_permissions SET revoked_at = SYSUTCDATETIME()
        WHERE user_id = @UserId AND app_name = @AppName AND revoked_at IS NULL;
        INSERT INTO dbo.app_permissions (user_id, app_name, role, granted_by)
        VALUES (@UserId, @AppName, 'global_admin', @ActorId);
      `);
  }

  await db.request()
    .input('ActorId',  sql.UniqueIdentifier, actorId)
    .input('UserId',   sql.UniqueIdentifier, userId)
    .input('TeamId',   sql.UniqueIdentifier, teamId)
    .query(`
      INSERT INTO dbo.audit_log (actor_id, action, target_type, target_id, payload)
      VALUES (@ActorId, 'admin_access_granted', 'user', CAST(@UserId AS NVARCHAR(100)),
        JSON_OBJECT('teamId': CAST(@TeamId AS NVARCHAR(100))));
    `);

  return null; // success
}

/** Apply the full AppDB schema to a connected pool (idempotent). */
async function applyAppDbSchema(pool: mssql.ConnectionPool): Promise<void> {
  const batches: string[] = [
    // player_status_types
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'player_status_types' AND schema_id = SCHEMA_ID('dbo'))
    BEGIN
      CREATE TABLE dbo.player_status_types (
        id          INT           NOT NULL PRIMARY KEY,
        status_name NVARCHAR(30)  NOT NULL,
        description NVARCHAR(200) NULL
      );
      INSERT INTO dbo.player_status_types (id, status_name, description) VALUES
        (1, 'current_player', 'Active roster player'),
        (2, 'alumni',         'Graduated — moved to Alumni CRM'),
        (3, 'removed',        'Removed from roster — no longer active');
    END`,

    // sports
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'sports' AND schema_id = SCHEMA_ID('dbo'))
    CREATE TABLE dbo.sports (
      id         UNIQUEIDENTIFIER  NOT NULL DEFAULT NEWID() PRIMARY KEY,
      name       NVARCHAR(100)     NOT NULL,
      abbr       NVARCHAR(10)      NOT NULL,
      is_active  BIT               NOT NULL DEFAULT 1,
      created_at DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT uq_sports_abbr UNIQUE (abbr)
    )`,

    // users (unified players + alumni)
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'users' AND schema_id = SCHEMA_ID('dbo'))
    BEGIN
      CREATE TABLE dbo.users (
        id                      UNIQUEIDENTIFIER  NOT NULL PRIMARY KEY,
        email                   NVARCHAR(255)     NULL,
        first_name              NVARCHAR(100)     NOT NULL,
        last_name               NVARCHAR(100)     NOT NULL,
        status_id               INT               NOT NULL DEFAULT 1
                                REFERENCES dbo.player_status_types(id),
        sport_id                UNIQUEIDENTIFIER  NULL REFERENCES dbo.sports(id),
        jersey_number           TINYINT           NULL,
        position                NVARCHAR(10)      NULL,
        academic_year           NVARCHAR(20)      NULL,
        recruiting_class        SMALLINT          NULL,
        height_inches           TINYINT           NULL,
        weight_lbs              SMALLINT          NULL,
        home_town               NVARCHAR(100)     NULL,
        home_state              NVARCHAR(50)      NULL,
        high_school             NVARCHAR(150)     NULL,
        gpa                     DECIMAL(3,2)      NULL,
        major                   NVARCHAR(100)     NULL,
        phone                   NVARCHAR(20)      NULL,
        personal_email          NVARCHAR(255)     NULL,
        instagram               NVARCHAR(100)     NULL,
        twitter                 NVARCHAR(100)     NULL,
        snapchat                NVARCHAR(100)     NULL,
        emergency_contact_name  NVARCHAR(150)     NULL,
        emergency_contact_phone NVARCHAR(20)      NULL,
        graduation_year         SMALLINT          NULL,
        graduation_semester     NVARCHAR(10)      NULL,
        graduated_at            DATETIME2         NULL,
        linkedin_url            NVARCHAR(500)     NULL,
        twitter_url             NVARCHAR(100)     NULL,
        current_employer        NVARCHAR(200)     NULL,
        current_job_title       NVARCHAR(150)     NULL,
        current_city            NVARCHAR(100)     NULL,
        current_state           NVARCHAR(50)      NULL,
        is_donor                BIT               NULL DEFAULT 0,
        last_donation_date      DATE              NULL,
        total_donations         DECIMAL(10,2)     NULL,
        engagement_score        TINYINT           NULL DEFAULT 0,
        communication_consent   BIT               NULL DEFAULT 1,
        years_on_roster         TINYINT           NULL,
        notes                   NVARCHAR(MAX)     NULL,
        created_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME()
      );
      CREATE UNIQUE INDEX uix_users_jersey_sport
        ON dbo.users (jersey_number, sport_id)
        WHERE jersey_number IS NOT NULL AND status_id = 1 AND sport_id IS NOT NULL;
    END`,

    // users_sports
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'users_sports' AND schema_id = SCHEMA_ID('dbo'))
    CREATE TABLE dbo.users_sports (
      id        UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
      user_id   UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id)  ON DELETE CASCADE,
      sport_id  UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.sports(id) ON DELETE CASCADE,
      username  NVARCHAR(100)    NULL,
      joined_at DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT uq_users_sports UNIQUE (user_id, sport_id)
    )`,

    // player_stats
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'player_stats' AND schema_id = SCHEMA_ID('dbo'))
    CREATE TABLE dbo.player_stats (
      id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
      user_id      UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
      season_year  SMALLINT         NOT NULL,
      games_played TINYINT          NULL,
      stats_json   NVARCHAR(MAX)    NULL,
      updated_at   DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT uq_player_stats UNIQUE (user_id, season_year)
    )`,

    // player_documents
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'player_documents' AND schema_id = SCHEMA_ID('dbo'))
    CREATE TABLE dbo.player_documents (
      id          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
      user_id     UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
      doc_type    NVARCHAR(50)     NOT NULL,
      file_name   NVARCHAR(255)    NOT NULL,
      blob_url    NVARCHAR(1000)   NOT NULL,
      uploaded_at DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
    )`,

    // graduation_log
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'graduation_log' AND schema_id = SCHEMA_ID('dbo'))
    CREATE TABLE dbo.graduation_log (
      id                   UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
      transaction_id       UNIQUEIDENTIFIER NOT NULL,
      user_id              UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id),
      graduation_year      SMALLINT         NOT NULL,
      graduation_semester  NVARCHAR(10)     NOT NULL,
      triggered_by         UNIQUEIDENTIFIER NULL,
      status               NVARCHAR(20)     NOT NULL DEFAULT 'success',
      notes                NVARCHAR(MAX)    NULL,
      logged_at            DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
    )`,

    // interaction_log
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'interaction_log' AND schema_id = SCHEMA_ID('dbo'))
    CREATE TABLE dbo.interaction_log (
      id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
      user_id      UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
      logged_by    UNIQUEIDENTIFIER NULL,
      channel      NVARCHAR(30)     NOT NULL,
      summary      NVARCHAR(MAX)    NOT NULL,
      outcome      NVARCHAR(50)     NULL,
      follow_up_at DATETIME2        NULL,
      logged_at    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
    )`,

    // outreach_campaigns
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'outreach_campaigns' AND schema_id = SCHEMA_ID('dbo'))
    CREATE TABLE dbo.outreach_campaigns (
      id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
      name             NVARCHAR(200)    NOT NULL,
      description      NVARCHAR(MAX)    NULL,
      target_audience  NVARCHAR(20)     NOT NULL DEFAULT 'all',
      audience_filters NVARCHAR(MAX)    NULL,
      status           NVARCHAR(20)     NOT NULL DEFAULT 'draft'
                       CONSTRAINT chk_campaign_status CHECK (status IN ('draft','scheduled','active','completed','cancelled')),
      scheduled_at     DATETIME2        NULL,
      completed_at     DATETIME2        NULL,
      sport_id         UNIQUEIDENTIFIER NULL REFERENCES dbo.sports(id),
      created_by       UNIQUEIDENTIFIER NULL,
      created_at       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
      updated_at       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
    )`,

    // outreach_messages
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'outreach_messages' AND schema_id = SCHEMA_ID('dbo'))
    CREATE TABLE dbo.outreach_messages (
      id           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
      campaign_id  UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.outreach_campaigns(id) ON DELETE CASCADE,
      user_id      UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id),
      channel      NVARCHAR(20)     NOT NULL,
      status       NVARCHAR(20)     NOT NULL DEFAULT 'pending',
      sent_at      DATETIME2        NULL,
      delivered_at DATETIME2        NULL,
      opened_at    DATETIME2        NULL,
      created_at   DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
    )`,

    // seasons
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'seasons' AND schema_id = SCHEMA_ID('dbo'))
    CREATE TABLE dbo.seasons (
      id          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
      sport_id    UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.sports(id) ON DELETE CASCADE,
      season_year SMALLINT         NOT NULL,
      label       NVARCHAR(50)     NULL,
      is_current  BIT              NOT NULL DEFAULT 0,
      starts_at   DATE             NULL,
      ends_at     DATE             NULL,
      CONSTRAINT uq_seasons UNIQUE (sport_id, season_year)
    )`,

    // season_players
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'season_players' AND schema_id = SCHEMA_ID('dbo'))
    CREATE TABLE dbo.season_players (
      id          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
      season_id   UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.seasons(id)  ON DELETE CASCADE,
      user_id     UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.users(id),
      enrolled_at DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT uq_season_players UNIQUE (season_id, user_id)
    )`,

    // user_roles
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'user_roles' AND schema_id = SCHEMA_ID('dbo'))
    CREATE TABLE dbo.user_roles (
      id         UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
      user_id    UNIQUEIDENTIFIER NOT NULL,
      sport_id   UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.sports(id),
      role       NVARCHAR(30)     NOT NULL,
      granted_by UNIQUEIDENTIFIER NULL,
      revoked_at DATETIME2        NULL,
      created_at DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT uq_user_roles UNIQUE (user_id, sport_id)
    )`,

    // RLS — drop policy first so we can CREATE OR ALTER the function it references
    `IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'user_access_policy' AND schema_id = SCHEMA_ID('dbo'))
      DROP SECURITY POLICY dbo.user_access_policy`,

    `CREATE OR ALTER FUNCTION dbo.fn_user_access(
      @session_user_id   NVARCHAR(100),
      @session_user_role NVARCHAR(50),
      @row_sport_id      UNIQUEIDENTIFIER,
      @row_user_id       UNIQUEIDENTIFIER,
      @row_status_id     INT
    )
    RETURNS TABLE
    WITH SCHEMABINDING
    AS
    RETURN
      SELECT 1 AS access_granted
      WHERE
        EXISTS (
          SELECT 1 FROM dbo.user_roles ur
          WHERE ur.user_id    = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
            AND ur.sport_id   = @row_sport_id
            AND ur.role       = 'coach_admin'
            AND ur.revoked_at IS NULL
        )
        OR
        (
          @row_status_id = 1
          AND EXISTS (
            SELECT 1 FROM dbo.user_roles ur
            WHERE ur.user_id    = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
              AND ur.sport_id   = @row_sport_id
              AND ur.role       = 'roster_only_admin'
              AND ur.revoked_at IS NULL
          )
        )
        OR
        @row_user_id = TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER)
        OR
        (
          @row_sport_id IS NULL
          AND TRY_CAST(@session_user_id AS UNIQUEIDENTIFIER) IS NOT NULL
        )`,

    `IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'user_access_policy')
    CREATE SECURITY POLICY dbo.user_access_policy
      ADD FILTER PREDICATE dbo.fn_user_access(
        CAST(SESSION_CONTEXT(N'user_id')   AS NVARCHAR(100)),
        CAST(SESSION_CONTEXT(N'user_role') AS NVARCHAR(50)),
        sport_id,
        id,
        status_id
      ) ON dbo.users
    WITH (STATE = ON)`,

    // audit_log
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'audit_log' AND schema_id = SCHEMA_ID('dbo'))
    CREATE TABLE dbo.audit_log (
      id          BIGINT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
      user_id     UNIQUEIDENTIFIER NULL,
      action      NVARCHAR(100)    NOT NULL,
      target_type NVARCHAR(50)     NULL,
      target_id   NVARCHAR(100)    NULL,
      details     NVARCHAR(MAX)    NULL,
      ip_address  NVARCHAR(45)     NULL,
      created_at  DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
    )`,

    // email_unsubscribes — CAN-SPAM opt-out store (migration 012)
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'email_unsubscribes' AND schema_id = SCHEMA_ID('dbo'))
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
    END`,

    // Extend outreach_campaigns with email fields (migration 012)
    `IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'subject_line')
      ALTER TABLE dbo.outreach_campaigns ADD subject_line NVARCHAR(500) NULL`,
    `IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'body_html')
      ALTER TABLE dbo.outreach_campaigns ADD body_html NVARCHAR(MAX) NULL`,
    `IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'from_name')
      ALTER TABLE dbo.outreach_campaigns ADD from_name NVARCHAR(200) NULL`,
    `IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'reply_to_email')
      ALTER TABLE dbo.outreach_campaigns ADD reply_to_email NVARCHAR(255) NULL`,
    `IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'campaign_type')
      ALTER TABLE dbo.outreach_campaigns ADD campaign_type NVARCHAR(20) NOT NULL DEFAULT 'outreach'`,
    `IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'physical_address')
      ALTER TABLE dbo.outreach_campaigns ADD physical_address NVARCHAR(500) NULL`,
    `IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_campaigns' AND COLUMN_NAME = 'started_at')
      ALTER TABLE dbo.outreach_campaigns ADD started_at DATETIME2 NULL`,

    // Extend outreach_messages with email dispatch fields (migration 012)
    `IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_messages' AND COLUMN_NAME = 'email_address')
      ALTER TABLE dbo.outreach_messages ADD email_address NVARCHAR(255) NULL`,
    `IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'outreach_messages' AND COLUMN_NAME = 'unsubscribe_token')
      ALTER TABLE dbo.outreach_messages ADD unsubscribe_token UNIQUEIDENTIFIER NULL`,

    // feed_posts — newsfeed (migration 012)
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'feed_posts' AND schema_id = SCHEMA_ID('dbo'))
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
    END`,

    // feed_post_reads — read receipts (migration 012)
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'feed_post_reads' AND schema_id = SCHEMA_ID('dbo'))
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
    END`,

    // migration_history — column name MUST be migration_name to match ll-db-deploy tool
    `IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'migration_history' AND schema_id = SCHEMA_ID('dbo'))
    BEGIN
      CREATE TABLE dbo.migration_history (
        id             INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
        migration_name NVARCHAR(260) NOT NULL UNIQUE,
        applied_at     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
        applied_by     NVARCHAR(100) NOT NULL DEFAULT SYSTEM_USER
      );
      -- Pre-mark all migrations that are superseded by the create script above.
      -- ll-db-deploy will skip any migration_name already present here.
      INSERT INTO dbo.migration_history (migration_name) VALUES
        ('001_app_db_schema.sql'),
        ('002_migrate_data.sql'),
        ('003_rbac_infrastructure.sql'),
        ('004_add_sport_classification.sql'),
        ('005_rls_policies.sql'),
        ('006_nullable_user_id.sql'),
        ('008_consolidate_dbo_schema.sql'),
        ('009_users_status_consolidation.sql'),
        ('010_campaign_completed_at.sql'),
        ('011_drop_current_country.sql'),
        ('012_email_infrastructure.sql');
    END`,

    // sp_GetSports — needed by GET /sports on app-api
    `CREATE OR ALTER PROCEDURE dbo.sp_GetSports
    AS
    BEGIN
      SET NOCOUNT ON;
      SELECT id, name, abbr, is_active AS isActive
      FROM   dbo.sports
      WHERE  is_active = 1
      ORDER  BY name;
    END`,
  ];

  for (const batch of batches) {
    await pool.request().query(batch);
  }
}

/** Apply AppDB stored procedures. Best-effort — logs errors but doesn't abort. */
async function applyAppDbSps(pool: mssql.ConnectionPool): Promise<void> {
  // Resolve the SP file path — try a few common roots
  const relPath = path.join('databases', 'app', 'stored-procedures', 'sp_App_AllProcedures.sql');
  const candidates = [
    path.resolve(process.cwd(), relPath),
    path.resolve(process.cwd(), '..', '..', relPath),
    path.resolve(__dirname, '..', '..', '..', '..', relPath),
    path.resolve(__dirname, '..', '..', '..', '..', '..', relPath),
  ];

  let spSql: string | null = null;
  for (const p of candidates) {
    try {
      spSql = await fs.readFile(p, 'utf8');
      break;
    } catch { /* try next */ }
  }

  if (!spSql) {
    console.warn('[applyAppDbSps] Could not locate sp_App_AllProcedures.sql — SPs not applied.');
    return;
  }

  // Split on GO (line by itself, optional whitespace)
  const batches = spSql
    .split(/^\s*GO\s*$/im)
    .map(b => b.trim())
    .filter(b => b.length > 0 && !/^--/.test(b) && !/^SET\s+(QUOTED|ANSI)/i.test(b));

  let applied = 0;
  let failed  = 0;
  for (const batch of batches) {
    try {
      await pool.request().query(batch);
      applied++;
    } catch (err: unknown) {
      failed++;
      const msg = err instanceof Error ? err.message : String(err);
      console.warn(`[applyAppDbSps] SP batch failed (skipping): ${msg.substring(0, 120)}`);
    }
  }
  console.log(`[applyAppDbSps] Applied ${applied} SP batches, ${failed} failed/skipped.`);
}
