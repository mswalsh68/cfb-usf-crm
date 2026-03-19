import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { verifyAccessToken, extractBearerToken, hasAppAccess, getAppRole, isAdmin } from '@cfb-crm/auth';
import type { AuthTokenPayload } from '@cfb-crm/types';
import { getDb, sql } from './db';

const app  = express();
const PORT = process.env.PORT || 3002;

app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(','), credentials: true }));
app.use(rateLimit({ windowMs: 15 * 60 * 1000, max: 500 }));
app.use(express.json({ limit: '10kb' }));

declare global { namespace Express { interface Request { user?: AuthTokenPayload } } }

function auth(req: express.Request, res: express.Response, next: express.NextFunction) {
  const token = extractBearerToken(req.headers.authorization);
  if (!token) return res.status(401).json({ success: false, error: 'Authentication required' });
  try { req.user = verifyAccessToken(token); next(); }
  catch { return res.status(401).json({ success: false, error: 'Invalid token' }); }
}

function rosterAccess(req: express.Request, res: express.Response, next: express.NextFunction) {
  if (!req.user || !hasAppAccess(req.user, 'roster')) return res.status(403).json({ success: false, error: 'Roster access required' });
  next();
}

function rosterWrite(req: express.Request, res: express.Response, next: express.NextFunction) {
  const role = req.user ? getAppRole(req.user, 'roster') : null;
  if (!role || !['global_admin','app_admin','coach_staff'].includes(role)) return res.status(403).json({ success: false, error: 'Write access required' });
  next();
}

function rosterAdmin(req: express.Request, res: express.Response, next: express.NextFunction) {
  const role = req.user ? getAppRole(req.user, 'roster') : null;
  if (!role || !isAdmin(role)) return res.status(403).json({ success: false, error: 'Admin access required' });
  next();
}

// GET /players
app.get('/players', auth, rosterAccess, async (req, res) => {
  const { search, status, position, academicYear, recruitingClass, page = '1', pageSize = '50' } = req.query as Record<string, string>;
  try {
    const db = await getDb();
    const r = await db.request()
      .input('Search',          sql.NVarChar, search           || null)
      .input('Status',          sql.NVarChar, status           || null)
      .input('Position',        sql.NVarChar, position         || null)
      .input('AcademicYear',    sql.NVarChar, academicYear     || null)
      .input('RecruitingClass', sql.SmallInt, recruitingClass ? parseInt(recruitingClass) : null)
      .input('Page',            sql.Int,      parseInt(page))
      .input('PageSize',        sql.Int,      parseInt(pageSize))
      .output('TotalCount',     sql.Int)
      .execute('dbo.sp_GetPlayers');
    return res.json({ success: true, data: (r.recordsets as any)[0], total: r.output.TotalCount, page: parseInt(page), pageSize: parseInt(pageSize) });
  } catch (err) { console.error('[GET /players]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// GET /players/:id
app.get('/players/:id', auth, rosterAccess, async (req, res) => {
  try {
    const db = await getDb();
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
  const b = req.body;
  try {
    const db = await getDb();
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
app.patch('/players/:id', auth, rosterAccess, rosterWrite, async (req, res) => {
  const b = req.body;
  try {
    const db = await getDb();
    const r = await db.request()
      .input('PlayerId',              sql.UniqueIdentifier, req.params.id)
      .input('JerseyNumber',          sql.TinyInt,          b.jerseyNumber          ?? null)
      .input('AcademicYear',          sql.NVarChar,         b.academicYear          ?? null)
      .input('Status',                sql.NVarChar,         b.status                ?? null)
      .input('HeightInches',          sql.TinyInt,          b.heightInches          ?? null)
      .input('WeightLbs',             sql.SmallInt,         b.weightLbs             ?? null)
      .input('Gpa',                   sql.Decimal(3,2),     b.gpa                   ?? null)
      .input('Major',                 sql.NVarChar,         b.major                 ?? null)
      .input('Phone',                 sql.NVarChar,         b.phone                 ?? null)
      .input('EmergencyContactName',  sql.NVarChar,         b.emergencyContactName  ?? null)
      .input('EmergencyContactPhone', sql.NVarChar,         b.emergencyContactPhone ?? null)
      .input('Notes',                 sql.NVarChar,         b.notes                 ?? null)
      .input('UpdatedBy',             sql.UniqueIdentifier, req.user!.sub)
      .output('ErrorCode',            sql.NVarChar(50))
      .execute('dbo.sp_UpdatePlayer');
    if (r.output.ErrorCode === 'USE_SP_GRADUATE_PLAYER') return res.status(400).json({ success: false, error: 'Use the graduate endpoint to graduate players' });
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.json({ success: true, message: 'Player updated' });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /players/graduate
app.post('/players/graduate', auth, rosterAccess, rosterAdmin, async (req, res) => {
  const { playerIds, graduationYear, graduationSemester, notes } = req.body;
  if (!playerIds?.length) return res.status(400).json({ success: false, error: 'playerIds array is required' });
  try {
    const db = await getDb();
    const r = await db.request()
      .input('PlayerIds',      sql.NVarChar(sql.MAX), JSON.stringify(playerIds))
      .input('GraduationYear', sql.SmallInt,          graduationYear)
      .input('Semester',       sql.NVarChar(10),      graduationSemester)
      .input('TriggeredBy',    sql.NVarChar(100),     req.user!.sub)
      .input('Notes',          sql.NVarChar(sql.MAX), notes ?? null)
      .output('TransactionId', sql.UniqueIdentifier)
      .output('SuccessCount',  sql.Int)
      .output('FailureJson',   sql.NVarChar(sql.MAX))
      .execute('dbo.sp_GraduatePlayer');
    return res.json({
      success: true,
      data: {
        transactionId:  r.output.TransactionId,
        graduatedCount: r.output.SuccessCount,
        failures:       JSON.parse(r.output.FailureJson || '[]'),
        totalRequested: playerIds.length,
      },
    });
  } catch (err) { console.error('[POST /players/graduate]', err); return res.status(500).json({ success: false, error: 'Graduation failed. No changes were made.' }); }
});

// POST /players/:id/stats
app.post('/players/:id/stats', auth, rosterAccess, rosterWrite, async (req, res) => {
  const { seasonYear, gamesPlayed, statsJson } = req.body;
  try {
    const db = await getDb();
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

// ─── POST /players/bulk ──────────────────────────────────────
app.post('/players/bulk', auth, rosterAccess, rosterWrite, async (req, res) => {
  const { players } = req.body;
  if (!Array.isArray(players) || players.length === 0)
    return res.status(400).json({ success: false, error: 'players array is required' });
  if (players.length > 500)
    return res.status(400).json({ success: false, error: 'Maximum 500 players per upload' });
  try {
    const db = await getDb();
    const r = await db.request()
      .input('PlayersJson',   sql.NVarChar(sql.MAX), JSON.stringify(players))
      .input('CreatedBy',     sql.UniqueIdentifier,  req.user!.sub)
      .output('SuccessCount', sql.Int)
      .output('SkippedCount', sql.Int)
      .output('ErrorJson',    sql.NVarChar(sql.MAX))
      .execute('dbo.sp_BulkCreatePlayers');
    return res.json({
      success: true,
      data: {
        inserted: r.output.SuccessCount,
        skipped:  r.output.SkippedCount,
        errors:   JSON.parse(r.output.ErrorJson || '[]'),
      },
    });
  } catch (err) {
    console.error('[POST /players/bulk]', err);
    return res.status(500).json({ success: false, error: 'Bulk insert failed' });
  }
});

// Health
app.get('/health', async (_req, res) => {
  try {
    const db = await getDb();
    await db.request().query('SELECT 1');
    res.json({ success: true, service: 'roster-api', db: 'connected' });
  } catch {
    res.status(503).json({ success: false, service: 'roster-api', db: 'disconnected' });
  }
});

app.listen(PORT, () => console.log(`[Roster API] Running on port ${PORT}`));
export default app;