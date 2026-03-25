import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { requireAuth, requirePlatformOwner } from '../middleware/auth';
import { getDb, sql } from '../db';
import * as mssql from 'mssql';

export const platformRouter = Router();

// All /platform routes require platform_owner role
platformRouter.use(requireAuth, requirePlatformOwner);

// ─── GET /platform/teams ──────────────────────────────────────────────────────
// Returns all teams (active + inactive) with stats for the platform admin dashboard.
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
// Deactivate / reactivate a team (subscription kill switch).
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

// ─── POST /platform/onboard-client ───────────────────────────────────────────
// Creates a new client's two databases (Roster + Alumni), applies full schema,
// seeds team_config, creates the first admin user, and registers in teams table.
// Replaces the manual onboard-new-client.sql workflow from the web UI.
platformRouter.post('/onboard-client', async (req, res) => {
  const {
    clientCode,    // e.g. 'HSFC'
    clientName,    // e.g. 'Plant Panthers'
    clientAbbr,    // e.g. 'PLANT'
    sport,         // 'football' | 'basketball' | etc.
    level,         // 'college' | 'high_school' | 'club'
    colorPrimary,
    colorAccent,
    adminEmail,
    adminPassword,
    adminFirstName,
    adminLastName,
    subscriptionTier = 'starter',
    dbServer,
  } = req.body;

  // Basic validation
  if (!clientCode || !clientName || !clientAbbr || !sport || !level || !adminEmail || !adminPassword) {
    return res.status(400).json({ success: false, error: 'clientCode, clientName, clientAbbr, sport, level, adminEmail, adminPassword are required' });
  }
  if (adminPassword.length < 10) {
    return res.status(400).json({ success: false, error: 'Admin password must be at least 10 characters' });
  }

  const rosterDb   = `${clientCode}_Roster`;
  const alumniDb   = `${clientCode}_Alumni`;
  const serverName = dbServer ?? process.env.DB_SERVER ?? 'localhost\\SQLEXPRESS';

  try {
    const db = await getDb();

    // 1. Insert into teams (idempotent via sp_CreateTeam)
    const teamR = await db.request()
      .input('Name',             sql.NVarChar, clientName)
      .input('Abbr',             sql.NVarChar, clientAbbr)
      .input('Sport',            sql.NVarChar, sport)
      .input('Level',            sql.NVarChar, level)
      .input('RosterDb',         sql.NVarChar, rosterDb)
      .input('AlumniDb',         sql.NVarChar, alumniDb)
      .input('DbServer',         sql.NVarChar, serverName)
      .input('SubscriptionTier', sql.NVarChar, subscriptionTier)
      .input('ActorId',          sql.UniqueIdentifier, req.user!.sub)
      .output('NewTeamId',       sql.UniqueIdentifier)
      .output('ErrorCode',       sql.NVarChar(50))
      .execute('dbo.sp_CreateTeam');

    if (teamR.output.ErrorCode && teamR.output.ErrorCode !== 'TEAM_ALREADY_EXISTS') {
      return res.status(400).json({ success: false, error: teamR.output.ErrorCode });
    }

    const newTeamId: string = teamR.output.NewTeamId;

    // 2. Create databases and apply schemas via dynamic SQL
    //    (We run USE master so we can CREATE DATABASE)
    const createDbSql = `
      IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @RosterDb)
        CREATE DATABASE [${rosterDb}];
      IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @AlumniDb)
        CREATE DATABASE [${alumniDb}];
    `;
    await db.request()
      .input('RosterDb', sql.NVarChar, rosterDb)
      .input('AlumniDb', sql.NVarChar, alumniDb)
      .query(createDbSql);

    // 3. Apply Roster schema to new database
    //    Connect to the new Roster DB and run schema + SPs
    const rosterPool = await new mssql.ConnectionPool({
      server:   serverName.replace('\\\\', '\\'),
      database: rosterDb,
      options:  { encrypt: false, trustServerCertificate: true },
      authentication: {
        type: 'default' as const,
        options: { userName: process.env.DB_USER ?? '', password: process.env.DB_PASSWORD ?? '' },
      },
    }).connect();

    await rosterPool.request().query(`
      IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'players')
      CREATE TABLE dbo.players (
        id                    UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWID(),
        user_id               UNIQUEIDENTIFIER NULL,
        jersey_number         INT              NULL,
        first_name            NVARCHAR(100)    NOT NULL,
        last_name             NVARCHAR(100)    NOT NULL,
        position              NVARCHAR(50)     NOT NULL,
        academic_year         NVARCHAR(50)     NOT NULL,
        status                NVARCHAR(50)     NOT NULL DEFAULT 'active',
        height_inches         INT              NULL,
        weight_lbs            INT              NULL,
        home_town             NVARCHAR(100)    NULL,
        home_state            NVARCHAR(50)     NULL,
        high_school           NVARCHAR(100)    NULL,
        recruiting_class      INT              NULL,
        gpa                   DECIMAL(3,2)     NULL,
        major                 NVARCHAR(100)    NULL,
        phone                 NVARCHAR(30)     NULL,
        email                 NVARCHAR(255)    NULL,
        twitter_url           NVARCHAR(255)    NULL,
        instagram_url         NVARCHAR(255)    NULL,
        emergency_contact_name  NVARCHAR(100) NULL,
        emergency_contact_phone NVARCHAR(30)  NULL,
        notes                 NVARCHAR(MAX)    NULL,
        created_at            DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at            DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
      );

      IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'player_stats')
      CREATE TABLE dbo.player_stats (
        id            UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWID(),
        player_id     UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.players(id),
        season        INT              NOT NULL,
        stats_json    NVARCHAR(MAX)    NULL,
        created_at    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_player_season UNIQUE (player_id, season)
      );
    `);
    await rosterPool.close();

    // 4. Apply Alumni schema to new database
    const alumniPool = await new mssql.ConnectionPool({
      server:   serverName.replace('\\\\', '\\'),
      database: alumniDb,
      options:  { encrypt: false, trustServerCertificate: true },
      authentication: {
        type: 'default' as const,
        options: { userName: process.env.DB_USER ?? '', password: process.env.DB_PASSWORD ?? '' },
      },
    }).connect();

    await alumniPool.request().query(`
      IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'alumni')
      CREATE TABLE dbo.alumni (
        id                    UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWID(),
        source_player_id      UNIQUEIDENTIFIER NULL,
        user_id               UNIQUEIDENTIFIER NULL,
        first_name            NVARCHAR(100)    NOT NULL,
        last_name             NVARCHAR(100)    NOT NULL,
        graduation_year       INT              NOT NULL,
        graduation_semester   NVARCHAR(20)     NOT NULL DEFAULT 'spring',
        position              NVARCHAR(50)     NULL,
        recruiting_class      INT              NULL,
        status                NVARCHAR(50)     NOT NULL DEFAULT 'active',
        current_employer      NVARCHAR(200)    NULL,
        current_job_title     NVARCHAR(200)    NULL,
        current_city          NVARCHAR(100)    NULL,
        current_state         NVARCHAR(50)     NULL,
        personal_email        NVARCHAR(255)    NULL,
        phone                 NVARCHAR(30)     NULL,
        linked_in_url         NVARCHAR(500)    NULL,
        twitter_url           NVARCHAR(500)    NULL,
        is_donor              BIT              NOT NULL DEFAULT 0,
        last_donation_date    DATE             NULL,
        total_donations       DECIMAL(12,2)    NULL,
        engagement_score      INT              NULL,
        notes                 NVARCHAR(MAX)    NULL,
        created_at            DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at            DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
      );

      IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'interaction_log')
      CREATE TABLE dbo.interaction_log (
        id              UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWID(),
        alumni_id       UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.alumni(id),
        interaction_type NVARCHAR(50)    NOT NULL,
        notes           NVARCHAR(MAX)    NULL,
        logged_by       UNIQUEIDENTIFIER NULL,
        interaction_date DATE            NOT NULL DEFAULT CAST(SYSUTCDATETIME() AS DATE),
        created_at      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
      );

      IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'outreach_campaigns')
      CREATE TABLE dbo.outreach_campaigns (
        id               UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWID(),
        name             NVARCHAR(200)    NOT NULL,
        description      NVARCHAR(MAX)    NULL,
        target_audience  NVARCHAR(50)     NOT NULL DEFAULT 'all',
        audience_filters NVARCHAR(MAX)    NULL,
        status           NVARCHAR(50)     NOT NULL DEFAULT 'draft',
        scheduled_at     DATETIME2        NULL,
        completed_at     DATETIME2        NULL,
        created_by       UNIQUEIDENTIFIER NULL,
        created_at       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
      );
    `);
    await alumniPool.close();

    // 5. Seed team_config for the new team
    const configR = await db.request()
      .input('TeamId',       sql.UniqueIdentifier, newTeamId)
      .input('ColorPrimary', sql.NVarChar,         colorPrimary ?? null)
      .input('ColorAccent',  sql.NVarChar,         colorAccent  ?? null)
      .output('ErrorCode',   sql.NVarChar(50))
      .execute('dbo.sp_UpdateTeamConfig');
    // Ignore config errors — config will be auto-seeded on first GET /config call

    // 6. Create the first admin user for this team
    const passwordHash = await bcrypt.hash(adminPassword, 12);
    const userR = await db.request()
      .input('Email',        sql.NVarChar,         adminEmail.trim().toLowerCase())
      .input('PasswordHash', sql.NVarChar,         passwordHash)
      .input('FirstName',    sql.NVarChar,         adminFirstName ?? 'Admin')
      .input('LastName',     sql.NVarChar,         adminLastName  ?? clientAbbr)
      .input('GlobalRole',   sql.NVarChar,         'global_admin')
      .input('CreatedBy',    sql.UniqueIdentifier, req.user!.sub)
      .input('TeamId',       sql.UniqueIdentifier, newTeamId)
      .input('GrantAppName', sql.NVarChar,         'roster')
      .input('GrantAppRole', sql.NVarChar,         'global_admin')
      .output('NewUserId',   sql.UniqueIdentifier)
      .output('ErrorCode',   sql.NVarChar(50))
      .execute('dbo.sp_CreateUser');

    if (userR.output.ErrorCode && userR.output.ErrorCode !== 'EMAIL_ALREADY_EXISTS') {
      return res.status(400).json({ success: false, error: `User creation failed: ${userR.output.ErrorCode}` });
    }

    return res.status(201).json({
      success: true,
      data: {
        teamId:   newTeamId,
        rosterDb,
        alumniDb,
        adminEmail,
        message: `Client ${clientAbbr} provisioned. Admin user created — they can log in immediately.`,
      },
    });
  } catch (err) {
    console.error('[POST /platform/onboard-client]', err);
    return res.status(500).json({ success: false, error: 'Server error during onboarding' });
  }
});
