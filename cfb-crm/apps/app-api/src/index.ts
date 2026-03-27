import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { verifyAccessToken, extractBearerToken, hasAppAccess, getAppRole, isAdmin } from '@cfb-crm/auth';
import type { AuthTokenPayload } from '@cfb-crm/types';
import { getClientDb, sql } from '@cfb-crm/db';
import { getHealthDb } from './db';

// ─── Validation schemas ───────────────────────────────────────
const createPlayerSchema = z.object({
  userId:          z.string().uuid(),
  firstName:       z.string().min(1),
  lastName:        z.string().min(1),
  position:        z.string().min(1),
  academicYear:    z.string().min(1),
  recruitingClass: z.number().int(),
}).passthrough();

const transferSchema = z.object({
  playerIds:        z.array(z.string().uuid()).min(1),
  transferReason:   z.enum(['graduated', 'transferred', 'withdrew', 'other']),
  transferYear:     z.number().int().min(2000).max(2100),
  transferSemester: z.enum(['spring', 'fall', 'summer']),
});

const playerStatsSchema = z.object({
  seasonYear: z.number().int(),
});

const createAlumniSchema = z.object({
  firstName:      z.string().min(1),
  lastName:       z.string().min(1),
  graduationYear: z.number().int(),
}).passthrough();

const logInteractionSchema = z.object({
  channel: z.string().min(1),
  summary: z.string().min(1),
});

const createCampaignSchema = z.object({
  name:           z.string().min(1),
  targetAudience: z.enum(['all', 'byClass', 'byPosition', 'byStatus', 'custom']),
}).passthrough();

function validate<T>(schema: z.ZodType<T>, body: unknown, res: express.Response): T | null {
  const result = schema.safeParse(body);
  if (!result.success) {
    res.status(400).json({ success: false, error: result.error.errors[0]?.message ?? 'Invalid request body' });
    return null;
  }
  return result.data;
}

const app  = express();
const PORT = process.env.PORT || 3002;

app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(','), credentials: true }));
app.use(rateLimit({ windowMs: 15 * 60 * 1000, max: 500 }));
app.use(express.json({ limit: '10kb' }));

// Request logging
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () =>
    console.log(`[App API] ${req.method} ${req.path} ${res.statusCode} ${Date.now() - start}ms`));
  next();
});

declare global { namespace Express { interface Request { user?: AuthTokenPayload } } }

// ─── DB helper ────────────────────────────────────────────────
function appDb(user: AuthTokenPayload) {
  return getClientDb({
    server:    user.dbServer,
    database:  user.appDb,
    user:      process.env.DB_USER,
    password:  process.env.DB_PASS,
    encrypt:   process.env.DB_ENCRYPT === 'true',
    trustCert: process.env.DB_TRUST_CERT === 'true',
  });
}

// ─── Auth middleware ──────────────────────────────────────────
function auth(req: express.Request, res: express.Response, next: express.NextFunction) {
  const token = extractBearerToken(req.headers.authorization);
  if (!token) return res.status(401).json({ success: false, error: 'Authentication required' });
  try { req.user = verifyAccessToken(token); next(); }
  catch { return res.status(401).json({ success: false, error: 'Invalid token' }); }
}

// ─── Roster access guards ─────────────────────────────────────
function rosterAccess(req: express.Request, res: express.Response, next: express.NextFunction) {
  if (!req.user || !hasAppAccess(req.user, 'roster')) return res.status(403).json({ success: false, error: 'Roster access required' });
  next();
}
function rosterWrite(req: express.Request, res: express.Response, next: express.NextFunction) {
  if (req.user?.globalRole === 'global_admin') return next();
  const role = req.user ? getAppRole(req.user, 'roster') : null;
  if (!role || !['global_admin', 'app_admin', 'coach_staff'].includes(role)) return res.status(403).json({ success: false, error: 'Write access required' });
  next();
}
function rosterAdmin(req: express.Request, res: express.Response, next: express.NextFunction) {
  if (req.user?.globalRole === 'global_admin') return next();
  const role = req.user ? getAppRole(req.user, 'roster') : null;
  if (!role || !isAdmin(role)) return res.status(403).json({ success: false, error: 'Admin access required' });
  next();
}

// ─── Alumni access guards ─────────────────────────────────────
function alumniAccess(req: express.Request, res: express.Response, next: express.NextFunction) {
  if (!req.user || !hasAppAccess(req.user, 'alumni')) return res.status(403).json({ success: false, error: 'Alumni access required' });
  next();
}
function alumniWrite(req: express.Request, res: express.Response, next: express.NextFunction) {
  const role = req.user ? getAppRole(req.user, 'alumni') : null;
  if (!role || !['global_admin', 'app_admin', 'coach_staff'].includes(role)) return res.status(403).json({ success: false, error: 'Write access required' });
  next();
}
function alumniAdmin(req: express.Request, res: express.Response, next: express.NextFunction) {
  const role = req.user ? getAppRole(req.user, 'alumni') : null;
  if (!role || !isAdmin(role)) return res.status(403).json({ success: false, error: 'Admin access required' });
  next();
}

// ══════════════════════════════════════════════════════════════
// ROSTER ROUTES
// ══════════════════════════════════════════════════════════════

// GET /players
app.get('/players', auth, rosterAccess, async (req, res) => {
  const { search, status, position, academicYear, recruitingClass, page = '1', pageSize = '50' } = req.query as Record<string, string>;
  try {
    const db = await appDb(req.user!);
    const r = await db.request()
      .input('Search',          sql.NVarChar, search           || null)
      .input('Status',          sql.NVarChar, status           || null)
      .input('Position',        sql.NVarChar, position         || null)
      .input('AcademicYear',    sql.NVarChar, academicYear     || null)
      .input('RecruitingClass', sql.SmallInt, recruitingClass ? parseInt(recruitingClass) : null)
      .input('Page',            sql.Int,      parseInt(page))
      .input('PageSize',        sql.Int,      Math.min(parseInt(pageSize) || 50, 200))
      .output('TotalCount',     sql.Int)
      .execute('dbo.sp_GetPlayers');
    return res.json({ success: true, data: (r.recordsets as any)[0], total: r.output.TotalCount, page: parseInt(page), pageSize: parseInt(pageSize) });
  } catch (err) { console.error('[GET /players]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// GET /players/:id
app.get('/players/:id', auth, rosterAccess, async (req, res) => {
  try {
    const db = await appDb(req.user!);
    const r = await db.request()
      .input('PlayerId',   sql.UniqueIdentifier, req.params.id)
      .output('ErrorCode', sql.NVarChar(50))
      .execute('dbo.sp_GetPlayerById');
    if (r.output.ErrorCode) return res.status(404).json({ success: false, error: 'Player not found' });
    return res.json({ success: true, data: { ...(r.recordsets as any)[0][0], stats: (r.recordsets as any)[1] } });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /players
app.post('/players', auth, rosterAccess, rosterWrite, async (req, res) => {
  const b = validate(createPlayerSchema, req.body, res);
  if (!b) return;
  try {
    const db = await appDb(req.user!);
    const r = await db.request()
      .input('UserId',                sql.UniqueIdentifier, b.userId)
      .input('JerseyNumber',          sql.TinyInt,          b.jerseyNumber          ?? null)
      .input('FirstName',             sql.NVarChar,         b.firstName)
      .input('LastName',              sql.NVarChar,         b.lastName)
      .input('Position',              sql.NVarChar,         b.position)
      .input('AcademicYear',          sql.NVarChar,         b.academicYear)
      .input('RecruitingClass',       sql.SmallInt,         b.recruitingClass)
      .input('HeightInches',          sql.TinyInt,          b.heightInches          ?? null)
      .input('WeightLbs',             sql.SmallInt,         b.weightLbs             ?? null)
      .input('HomeTown',              sql.NVarChar,         b.homeTown              ?? null)
      .input('HomeState',             sql.NVarChar,         b.homeState             ?? null)
      .input('HighSchool',            sql.NVarChar,         b.highSchool            ?? null)
      .input('Gpa',                   sql.Decimal(3,2),     b.gpa                   ?? null)
      .input('Major',                 sql.NVarChar,         b.major                 ?? null)
      .input('Phone',                 sql.NVarChar,         b.phone                 ?? null)
      .input('Email',                 sql.NVarChar,         b.email                 ?? null)
      .input('Instagram',             sql.NVarChar,         b.instagram             ?? null)
      .input('Twitter',               sql.NVarChar,         b.twitter               ?? null)
      .input('Snapchat',              sql.NVarChar,         b.snapchat              ?? null)
      .input('EmergencyContactName',  sql.NVarChar,         b.emergencyContactName  ?? null)
      .input('EmergencyContactPhone', sql.NVarChar,         b.emergencyContactPhone ?? null)
      .input('Notes',                 sql.NVarChar,         b.notes                 ?? null)
      .input('CreatedBy',             sql.UniqueIdentifier, req.user!.sub)
      .output('NewPlayerId',          sql.UniqueIdentifier)
      .output('ErrorCode',            sql.NVarChar(50))
      .execute('dbo.sp_CreatePlayer');
    if (r.output.ErrorCode === 'JERSEY_NUMBER_IN_USE')           return res.status(409).json({ success: false, error: 'Jersey number already in use' });
    if (r.output.ErrorCode === 'PLAYER_ALREADY_EXISTS_FOR_USER') return res.status(409).json({ success: false, error: 'Player already exists for this user' });
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.status(201).json({ success: true, data: { id: r.output.NewPlayerId } });
  } catch (err) { console.error('[POST /players]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// PATCH /players/:id
app.patch('/players/:id', auth, rosterAccess, async (req, res) => {
  const b    = req.body;
  const role = req.user ? getAppRole(req.user, 'roster') : null;
  const isWriter = req.user?.globalRole === 'global_admin' || !!(role && ['global_admin', 'app_admin', 'coach_staff'].includes(role));
  try {
    const db = await appDb(req.user!);
    if (!isWriter) {
      const check = await db.request()
        .input('PlayerId', sql.UniqueIdentifier, req.params.id)
        .output('ErrorCode', sql.NVarChar(50))
        .execute('dbo.sp_GetPlayerById');
      const playerRow = (check.recordsets as any)[0]?.[0];
      if (!playerRow) return res.status(404).json({ success: false, error: 'Player not found' });
      if (playerRow.userId !== req.user!.sub) return res.status(403).json({ success: false, error: 'You can only edit your own profile' });
    }
    const r = await db.request()
      .input('PlayerId',              sql.UniqueIdentifier, req.params.id)
      .input('JerseyNumber',          sql.TinyInt,          isWriter ? (b.jerseyNumber ?? null) : null)
      .input('Position',              sql.NVarChar,         isWriter ? (b.position     ?? null) : null)
      .input('AcademicYear',          sql.NVarChar,         isWriter ? (b.academicYear ?? null) : null)
      .input('Status',                sql.NVarChar,         isWriter ? (b.status       ?? null) : null)
      .input('HeightInches',          sql.TinyInt,          isWriter ? (b.heightInches ?? null) : null)
      .input('WeightLbs',             sql.SmallInt,         isWriter ? (b.weightLbs    ?? null) : null)
      .input('Gpa',                   sql.Decimal(3,2),     b.gpa                   ?? null)
      .input('Major',                 sql.NVarChar,         b.major                 ?? null)
      .input('Phone',                 sql.NVarChar,         b.phone                 ?? null)
      .input('Email',                 sql.NVarChar,         b.email                 ?? null)
      .input('Instagram',             sql.NVarChar,         b.instagram             ?? null)
      .input('Twitter',               sql.NVarChar,         b.twitter               ?? null)
      .input('Snapchat',              sql.NVarChar,         b.snapchat              ?? null)
      .input('EmergencyContactName',  sql.NVarChar,         b.emergencyContactName  ?? null)
      .input('EmergencyContactPhone', sql.NVarChar,         b.emergencyContactPhone ?? null)
      .input('Notes',                 sql.NVarChar,         b.notes                 ?? null)
      .input('UpdatedBy',             sql.UniqueIdentifier, req.user!.sub)
      .output('ErrorCode',            sql.NVarChar(50))
      .execute('dbo.sp_UpdatePlayer');
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.json({ success: true, message: 'Player updated' });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /players/transfer
// Marks players graduated in roster schema, then creates alumni records
// in alumni schema — all in the same DB, no inter-service HTTP call.
app.post('/players/transfer', auth, rosterAccess, rosterAdmin, async (req, res) => {
  const body = validate(transferSchema, req.body, res);
  if (!body) return;
  const { playerIds, transferReason, transferYear, transferSemester } = body;
  const notes = (req.body as any).notes ?? null;
  try {
    const db = await appDb(req.user!);

    // Step 1: Mark players graduated / transferred in roster schema
    const r = await db.request()
      .input('PlayerIds',        sql.NVarChar(sql.MAX), JSON.stringify(playerIds))
      .input('TransferReason',   sql.NVarChar(50),      transferReason)
      .input('TransferYear',     sql.SmallInt,          transferYear)
      .input('TransferSemester', sql.NVarChar(10),      transferSemester)
      .input('Notes',            sql.NVarChar(sql.MAX), notes ?? null)
      .input('TriggeredBy',      sql.NVarChar(100),     req.user!.sub)
      .output('TransactionId',   sql.UniqueIdentifier)
      .output('SuccessCount',    sql.Int)
      .output('FailureJson',     sql.NVarChar(sql.MAX))
      .output('PlayersJson',     sql.NVarChar(sql.MAX))
      .execute('dbo.sp_TransferToAlumni');

    const transferredPlayers = JSON.parse(r.output.PlayersJson || '[]');
    const failures           = JSON.parse(r.output.FailureJson || '[]');

    // Step 2: Create alumni records in alumni schema (same DB, no HTTP hop)
    const alumniFailures: any[] = [];
    for (const p of transferredPlayers) {
      try {
        const ar = await db.request()
          .input('UserId',             sql.UniqueIdentifier, p.userId)
          .input('SourcePlayerId',     sql.UniqueIdentifier, p.playerId)
          .input('FirstName',          sql.NVarChar,         p.firstName)
          .input('LastName',           sql.NVarChar,         p.lastName)
          .input('GraduationYear',     sql.SmallInt,         transferYear)
          .input('GraduationSemester', sql.NVarChar,         transferSemester)
          .input('Position',           sql.NVarChar,         p.position)
          .input('RecruitingClass',    sql.SmallInt,         p.recruitingClass)
          .input('Phone',              sql.NVarChar,         p.phone   ?? null)
          .input('PersonalEmail',      sql.NVarChar,         p.email   ?? null)
          .output('NewAlumniId',       sql.UniqueIdentifier)
          .output('ErrorCode',         sql.NVarChar(50))
          .execute('dbo.sp_CreateAlumniFromPlayer');
        // ALUMNI_ALREADY_EXISTS is idempotent — not a failure
        if (ar.output.ErrorCode && ar.output.ErrorCode !== 'ALUMNI_ALREADY_EXISTS') {
          alumniFailures.push({ playerId: p.playerId, reason: ar.output.ErrorCode });
        }
      } catch (err: any) {
        alumniFailures.push({ playerId: p.playerId, reason: err?.message ?? 'Failed to create alumni record' });
      }
    }

    return res.json({
      success: true,
      data: {
        transactionId:    r.output.TransactionId,
        transferredCount: r.output.SuccessCount,
        failures:         [...failures, ...alumniFailures],
        totalRequested:   playerIds.length,
      },
    });
  } catch (err) {
    console.error('[POST /players/transfer]', err);
    return res.status(500).json({ success: false, error: 'Transfer failed. No changes were made.' });
  }
});

// POST /players/bulk
app.post('/players/bulk', auth, rosterAccess, rosterWrite, async (req, res) => {
  const { players } = req.body;
  if (!Array.isArray(players) || players.length === 0) return res.status(400).json({ success: false, error: 'players array is required' });
  if (players.length > 500) return res.status(400).json({ success: false, error: 'Maximum 500 players per upload' });
  try {
    const db = await appDb(req.user!);
    const r = await db.request()
      .input('PlayersJson',   sql.NVarChar(sql.MAX), JSON.stringify(players))
      .input('CreatedBy',     sql.UniqueIdentifier,  req.user!.sub)
      .output('SuccessCount', sql.Int)
      .output('SkippedCount', sql.Int)
      .output('ErrorJson',    sql.NVarChar(sql.MAX))
      .execute('dbo.sp_BulkCreatePlayers');
    return res.json({ success: true, data: { inserted: r.output.SuccessCount, skipped: r.output.SkippedCount, errors: JSON.parse(r.output.ErrorJson || '[]') } });
  } catch (err) { console.error('[POST /players/bulk]', err); return res.status(500).json({ success: false, error: 'Bulk insert failed' }); }
});

// POST /players/:id/stats
app.post('/players/:id/stats', auth, rosterAccess, rosterWrite, async (req, res) => {
  const body = validate(playerStatsSchema, req.body, res);
  if (!body) return;
  const { seasonYear } = body;
  const { gamesPlayed, statsJson } = req.body as any;
  try {
    const db = await appDb(req.user!);
    const r = await db.request()
      .input('PlayerId',    sql.UniqueIdentifier,  req.params.id)
      .input('SeasonYear',  sql.SmallInt,          seasonYear)
      .input('GamesPlayed', sql.TinyInt,           gamesPlayed ?? null)
      .input('StatsJson',   sql.NVarChar(sql.MAX), statsJson ? JSON.stringify(statsJson) : null)
      .output('ErrorCode',  sql.NVarChar(50))
      .execute('dbo.sp_UpsertPlayerStats');
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.json({ success: true, message: 'Stats updated' });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// ══════════════════════════════════════════════════════════════
// ALUMNI ROUTES
// ══════════════════════════════════════════════════════════════

// GET /alumni
app.get('/alumni', auth, alumniAccess, async (req, res) => {
  const { search, status, isDonor, gradYear, position, page = '1', pageSize = '50' } = req.query as Record<string, string>;
  try {
    const db = await appDb(req.user!);
    const r = await db.request()
      .input('Search',      sql.NVarChar, search   || null)
      .input('Status',      sql.NVarChar, status   || null)
      .input('IsDonor',     sql.Bit,      isDonor  ? isDonor === 'true' : null)
      .input('GradYear',    sql.SmallInt, gradYear ? parseInt(gradYear) : null)
      .input('Position',    sql.NVarChar, position || null)
      .input('Page',        sql.Int,      parseInt(page))
      .input('PageSize',    sql.Int,      Math.min(parseInt(pageSize) || 50, 200))
      .output('TotalCount', sql.Int)
      .execute('dbo.sp_GetAlumni');
    return res.json({ success: true, data: r.recordset, total: r.output.TotalCount, page: parseInt(page), pageSize: parseInt(pageSize) });
  } catch (err) { console.error('[GET /alumni]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// GET /alumni/:id
app.get('/alumni/:id', auth, alumniAccess, async (req, res) => {
  try {
    const db = await appDb(req.user!);
    const r = await db.request()
      .input('AlumniId',   sql.UniqueIdentifier, req.params.id)
      .output('ErrorCode', sql.NVarChar(50))
      .execute('dbo.sp_GetAlumniById');
    if (r.output.ErrorCode) return res.status(404).json({ success: false, error: 'Alumni not found' });
    return res.json({ success: true, data: { ...(r.recordsets as any)[0][0], interactions: (r.recordsets as any)[1] } });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /alumni
app.post('/alumni', auth, alumniAccess, async (req, res) => {
  const b = validate(createAlumniSchema, req.body, res);
  if (!b) return;
  try {
    const db = await appDb(req.user!);
    const r = await db.request()
      .input('UserId',             sql.UniqueIdentifier, b.userId             ?? null)
      .input('SourcePlayerId',     sql.UniqueIdentifier, b.sourcePlayerId     ?? null)
      .input('FirstName',          sql.NVarChar,         b.firstName)
      .input('LastName',           sql.NVarChar,         b.lastName)
      .input('GraduationYear',     sql.SmallInt,         b.graduationYear)
      .input('GraduationSemester', sql.NVarChar,         b.graduationSemester ?? 'spring')
      .input('Position',           sql.NVarChar,         b.position           ?? null)
      .input('RecruitingClass',    sql.SmallInt,         b.recruitingClass    ?? null)
      .input('Phone',              sql.NVarChar,         b.phone              ?? null)
      .input('PersonalEmail',      sql.NVarChar,         b.personalEmail      ?? null)
      .output('NewAlumniId',       sql.UniqueIdentifier)
      .output('ErrorCode',         sql.NVarChar(50))
      .execute('dbo.sp_CreateAlumniFromPlayer');
    if (r.output.ErrorCode && r.output.ErrorCode !== 'ALUMNI_ALREADY_EXISTS')
      return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.status(201).json({ success: true, data: { id: r.output.NewAlumniId } });
  } catch (err) { console.error('[POST /alumni]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// PATCH /alumni/:id
app.patch('/alumni/:id', auth, alumniAccess, async (req, res) => {
  const b    = req.body;
  const role = req.user ? getAppRole(req.user, 'alumni') : null;
  const isWriter = role && ['global_admin', 'app_admin', 'coach_staff'].includes(role);
  try {
    const db = await appDb(req.user!);
    if (!isWriter) {
      const check = await db.request()
        .input('AlumniId', sql.UniqueIdentifier, req.params.id)
        .query('SELECT user_id AS userId FROM alumni.alumni WHERE id = @AlumniId');
      const row = check.recordset[0];
      if (!row) return res.status(404).json({ success: false, error: 'Alumni not found' });
      if (row.userId !== req.user!.sub) return res.status(403).json({ success: false, error: 'You can only edit your own profile' });
    }
    const r = await db.request()
      .input('AlumniId',         sql.UniqueIdentifier, req.params.id)
      .input('Status',           sql.NVarChar,         isWriter ? (b.status           ?? null) : null)
      .input('IsDonor',          sql.Bit,              isWriter ? (b.isDonor          ?? null) : null)
      .input('LastDonationDate', sql.Date,             isWriter && b.lastDonationDate ? new Date(b.lastDonationDate) : null)
      .input('TotalDonations',   sql.Decimal(10,2),    isWriter ? (b.totalDonations   ?? null) : null)
      .input('PersonalEmail',    sql.NVarChar,         b.personalEmail    ?? null)
      .input('Phone',            sql.NVarChar,         b.phone            ?? null)
      .input('LinkedInUrl',      sql.NVarChar,         b.linkedInUrl      ?? null)
      .input('TwitterUrl',       sql.NVarChar,         b.twitterUrl       ?? null)
      .input('CurrentEmployer',  sql.NVarChar,         b.currentEmployer  ?? null)
      .input('CurrentJobTitle',  sql.NVarChar,         b.currentJobTitle  ?? null)
      .input('CurrentCity',      sql.NVarChar,         b.currentCity      ?? null)
      .input('CurrentState',     sql.NVarChar,         b.currentState     ?? null)
      .input('Notes',            sql.NVarChar,         b.notes            ?? null)
      .input('UpdatedBy',        sql.UniqueIdentifier, req.user!.sub)
      .output('ErrorCode',       sql.NVarChar(50))
      .execute('dbo.sp_UpdateAlumni');
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.json({ success: true, message: 'Alumni updated' });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /alumni/:id/interactions
app.post('/alumni/:id/interactions', auth, alumniAccess, alumniWrite, async (req, res) => {
  const body = validate(logInteractionSchema, req.body, res);
  if (!body) return;
  const { channel, summary } = body;
  const { outcome, followUpAt } = req.body as any;
  try {
    const db = await appDb(req.user!);
    const r = await db.request()
      .input('AlumniId',   sql.UniqueIdentifier, req.params.id)
      .input('LoggedBy',   sql.UniqueIdentifier, req.user!.sub)
      .input('Channel',    sql.NVarChar,         channel)
      .input('Summary',    sql.NVarChar,         summary)
      .input('Outcome',    sql.NVarChar,         outcome    ?? null)
      .input('FollowUpAt', sql.DateTime2,        followUpAt ? new Date(followUpAt) : null)
      .output('ErrorCode', sql.NVarChar(50))
      .execute('dbo.sp_LogInteraction');
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.status(201).json({ success: true, message: 'Interaction logged' });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /alumni/bulk
app.post('/alumni/bulk', auth, alumniAccess, alumniWrite, async (req, res) => {
  const { alumni } = req.body;
  if (!Array.isArray(alumni) || alumni.length === 0) return res.status(400).json({ success: false, error: 'alumni array is required' });
  if (alumni.length > 500) return res.status(400).json({ success: false, error: 'Maximum 500 alumni per upload' });
  try {
    const db = await appDb(req.user!);
    const r = await db.request()
      .input('AlumniJson',    sql.NVarChar(sql.MAX), JSON.stringify(alumni))
      .input('CreatedBy',     sql.UniqueIdentifier,  req.user!.sub)
      .output('SuccessCount', sql.Int)
      .output('SkippedCount', sql.Int)
      .output('ErrorJson',    sql.NVarChar(sql.MAX))
      .execute('dbo.sp_BulkCreateAlumni');
    return res.json({ success: true, data: { inserted: r.output.SuccessCount, skipped: r.output.SkippedCount, errors: JSON.parse(r.output.ErrorJson || '[]') } });
  } catch (err) { console.error('[POST /alumni/bulk]', err); return res.status(500).json({ success: false, error: 'Bulk insert failed' }); }
});

// ══════════════════════════════════════════════════════════════
// CAMPAIGNS & STATS
// ══════════════════════════════════════════════════════════════

// GET /campaigns
app.get('/campaigns', auth, alumniAccess, async (req, res) => {
  try {
    const db = await appDb(req.user!);
    const r = await db.request().execute('dbo.sp_GetCampaigns');
    return res.json({ success: true, data: r.recordset });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /campaigns
app.post('/campaigns', auth, alumniAccess, alumniAdmin, async (req, res) => {
  const body = validate(createCampaignSchema, req.body, res);
  if (!body) return;
  const { name, targetAudience } = body;
  const { description, audienceFilters, scheduledAt } = req.body as any;
  try {
    const db = await appDb(req.user!);
    const r = await db.request()
      .input('Name',            sql.NVarChar,         name)
      .input('Description',     sql.NVarChar,         description     || null)
      .input('TargetAudience',  sql.NVarChar,         targetAudience)
      .input('AudienceFilters', sql.NVarChar,         audienceFilters ? JSON.stringify(audienceFilters) : null)
      .input('ScheduledAt',     sql.DateTime2,        scheduledAt ? new Date(scheduledAt) : null)
      .input('CreatedBy',       sql.UniqueIdentifier, req.user!.sub)
      .output('NewCampaignId',  sql.UniqueIdentifier)
      .output('ErrorCode',      sql.NVarChar(50))
      .execute('dbo.sp_CreateCampaign');
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.status(201).json({ success: true, data: { id: r.output.NewCampaignId } });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// GET /stats
app.get('/stats', auth, alumniAccess, async (req, res) => {
  try {
    const db = await appDb(req.user!);
    const r = await db.request().execute('dbo.sp_GetAlumniStats');
    const row = r.recordset[0];
    if (row?.classCounts) row.classCounts = JSON.parse(row.classCounts);
    return res.json({ success: true, data: row });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// ══════════════════════════════════════════════════════════════
// HEALTH
// ══════════════════════════════════════════════════════════════

app.get('/health', async (_req, res) => {
  try {
    const db = await getHealthDb();
    await db.request().query('SELECT 1');
    res.json({ success: true, service: 'app-api', db: 'connected' });
  } catch {
    res.status(503).json({ success: false, service: 'app-api', db: 'disconnected' });
  }
});

app.listen(PORT, () => console.log(`[App API] Running on port ${PORT}`));
export default app;
