import { Router } from 'express';
import bcrypt from 'bcryptjs';
import fs from 'fs';
import path from 'path';
import { requireAuth, requirePlatformOwner } from '../middleware/auth';
import { getDb, sql } from '../db';
import * as mssql from 'mssql';

/** Split a SQL file on GO batch separators and execute each batch. */
async function executeSqlFile(pool: mssql.ConnectionPool, filePath: string): Promise<void> {
  const content = fs.readFileSync(filePath, 'utf8');
  const batches  = content.split(/^\s*GO\s*$/im).map(b => b.trim()).filter(Boolean);
  for (const batch of batches) {
    await pool.request().query(batch);
  }
}

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
// Creates a new client's unified app database, applies full schema + SPs,
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

  const appDb      = `${clientCode}App`;          // e.g. PHSPanthersApp
  const rosterDb   = `${clientCode}_Roster`;      // kept for legacy column compatibility
  const alumniDb   = `${clientCode}_Alumni`;      // kept for legacy column compatibility
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
      .input('AppDb',            sql.NVarChar, appDb)
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

    // 2. Create the unified app database (idempotent)
    await db.request().query(
      `IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'${appDb}')
         CREATE DATABASE [${appDb}];`
    );

    // 3. Apply schema + stored procedures to the new app database
    const appPool = await new mssql.ConnectionPool({
      server:   serverName.replace('\\\\', '\\'),
      database: appDb,
      options:  { encrypt: false, trustServerCertificate: true },
      authentication: {
        type: 'default' as const,
        options: { userName: process.env.DB_USER ?? '', password: process.env.DB_PASSWORD ?? '' },
      },
    }).connect();

    try {
      const dbRoot = path.resolve(__dirname, '../../../../databases');
      await executeSqlFile(appPool, path.join(dbRoot, 'app', 'migrations', '001_app_db_schema.sql'));
      await executeSqlFile(appPool, path.join(dbRoot, 'app', 'stored-procedures', 'sp_App_AllProcedures.sql'));
    } finally {
      await appPool.close();
    }

    // 4. Seed team_config for the new team
    const configR = await db.request()
      .input('TeamId',       sql.UniqueIdentifier, newTeamId)
      .input('ColorPrimary', sql.NVarChar,         colorPrimary ?? null)
      .input('ColorAccent',  sql.NVarChar,         colorAccent  ?? null)
      .output('ErrorCode',   sql.NVarChar(50))
      .execute('dbo.sp_UpdateTeamConfig');
    // Ignore config errors — config will be auto-seeded on first GET /config call

    // 5. Create the first admin user for this team
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
        teamId:    newTeamId,
        appDb,
        adminEmail,
        message: `Client ${clientAbbr} provisioned. Admin user created — they can log in immediately.`,
      },
    });
  } catch (err) {
    console.error('[POST /platform/onboard-client]', err);
    return res.status(500).json({ success: false, error: 'Server error during onboarding' });
  }
});
