import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import cookieParser from 'cookie-parser';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { verifyAccessToken, extractBearerToken, hasAppAccess, getAppRole, isAdmin, canWrite } from '@cfb-crm/auth';
import type { AuthTokenPayload } from '@cfb-crm/types';
import { createExecutor } from '@cfb-crm/db';
import { getHealthDb } from './db';

// ─── Validation schemas ───────────────────────────────────────
const createPlayerSchema = z.object({
  userId:                z.string().uuid(),
  firstName:             z.string().min(1),
  lastName:              z.string().min(1),
  position:              z.string().min(1),
  academicYear:          z.string().min(1),
  recruitingClass:       z.number().int(),
  jerseyNumber:          z.number().int().nullable().optional(),
  heightInches:          z.number().int().nullable().optional(),
  weightLbs:             z.number().int().nullable().optional(),
  homeTown:              z.string().nullable().optional(),
  homeState:             z.string().nullable().optional(),
  highSchool:            z.string().nullable().optional(),
  gpa:                   z.number().nullable().optional(),
  major:                 z.string().nullable().optional(),
  phone:                 z.string().nullable().optional(),
  email:                 z.string().nullable().optional(),
  instagram:             z.string().nullable().optional(),
  twitter:               z.string().nullable().optional(),
  snapchat:              z.string().nullable().optional(),
  emergencyContactName:  z.string().nullable().optional(),
  emergencyContactPhone: z.string().nullable().optional(),
  notes:                 z.string().nullable().optional(),
});

const transferSchema = z.object({
  playerIds:        z.array(z.string().uuid()).min(1),
  transferReason:   z.enum(['graduated', 'transferred', 'withdrew', 'other']),
  transferYear:     z.number().int().min(2000).max(2100),
  transferSemester: z.enum(['spring', 'fall', 'summer']),
  notes:            z.string().nullable().optional(),
});

const playerStatsSchema = z.object({
  seasonYear:  z.number().int(),
  gamesPlayed: z.number().int().nullable().optional(),
  statsJson:   z.record(z.unknown()).nullable().optional(),
});

const createAlumniSchema = z.object({
  firstName:          z.string().min(1),
  lastName:           z.string().min(1),
  graduationYear:     z.number().int(),
  userId:             z.string().uuid().nullable().optional(),
  sourcePlayerId:     z.string().uuid().nullable().optional(),
  graduationSemester: z.enum(['spring', 'fall', 'summer']).optional().default('spring'),
  position:           z.string().nullable().optional(),
  recruitingClass:    z.number().int().nullable().optional(),
  phone:              z.string().nullable().optional(),
  personalEmail:      z.string().nullable().optional(),
});

const logInteractionSchema = z.object({
  channel:    z.string().min(1),
  summary:    z.string().min(1),
  outcome:    z.string().nullable().optional(),
  followUpAt: z.string().datetime({ offset: true }).nullable().optional(),
});

const createCampaignSchema = z.object({
  name:            z.string().min(1),
  targetAudience:  z.enum(['all', 'byClass', 'byPosition', 'byStatus', 'custom']),
  description:     z.string().nullable().optional(),
  audienceFilters: z.record(z.unknown()).nullable().optional(),
  scheduledAt:     z.string().datetime({ offset: true }).nullable().optional(),
});

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

app.use(helmet({
  hsts: {
    maxAge:            31536000,
    includeSubDomains: true,
    preload:           true,
  },
  contentSecurityPolicy: {
    directives: {
      defaultSrc:     ["'self'"],
      scriptSrc:      ["'self'"],
      styleSrc:       ["'self'"],
      imgSrc:         ["'self'", 'data:'],
      connectSrc:     ["'self'"],
      frameAncestors: ["'none'"],
    },
  },
}));
app.use(cookieParser());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(','), credentials: true }));
app.use(rateLimit({ windowMs: 15 * 60 * 1000, max: 500 }));
app.use(express.json({ limit: '500kb' }));
app.disable('etag');
app.use((_req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });

// Request logging
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () =>
    console.log(`[App API] ${req.method} ${req.path} ${res.statusCode} ${Date.now() - start}ms`));
  next();
});

declare global { namespace Express { interface Request { user?: AuthTokenPayload } } }

// ─── DB helper ────────────────────────────────────────────────
// Returns the ONE sanctioned database executor for this user's tenant.
// All data operations flow through db.execute(). No other DB access is permitted.
function appDb(user: AuthTokenPayload) {
  return createExecutor({
    server:    user.dbServer,
    database:  user.appDb,
    user:      process.env.DB_USER,
    password:  process.env.DB_PASS,
    encrypt:   process.env.DB_ENCRYPT === 'true',
    trustCert: process.env.DB_TRUST_CERT === 'true',
  });
}

// ─── Session context helper ───────────────────────────────────
// Returns the two params every SP needs to set its own session context
// so RLS filter functions can identify the requesting user.
function reqCtx(req: express.Request) {
  return {
    RequestingUserId:   req.user!.sub,
    RequestingUserRole: req.user!.globalRole || '',
  };
}

function parsePage(raw: string | undefined)     { return Math.max(parseInt(raw ?? '1')  || 1,  1); }
function parsePageSize(raw: string | undefined) { return Math.min(Math.max(parseInt(raw ?? '50') || 50, 1), 200); }

// ─── Auth middleware ──────────────────────────────────────────
// Accepts token from Authorization header (mobile) or httpOnly cookie (web)
function auth(req: express.Request, res: express.Response, next: express.NextFunction) {
  const token = extractBearerToken(req.headers.authorization) ?? req.cookies?.cfb_access_token ?? null;
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
  const role = req.user ? getAppRole(req.user, 'roster') : null;
  if (!canWrite(role)) return res.status(403).json({ success: false, error: 'Write access required' });
  next();
}
function rosterAdmin(req: express.Request, res: express.Response, next: express.NextFunction) {
  const role = req.user ? getAppRole(req.user, 'roster') : null;
  if (!isAdmin(role)) return res.status(403).json({ success: false, error: 'Admin access required' });
  next();
}

// ─── Alumni access guards ─────────────────────────────────────
function alumniAccess(req: express.Request, res: express.Response, next: express.NextFunction) {
  if (!req.user || !hasAppAccess(req.user, 'alumni')) return res.status(403).json({ success: false, error: 'Alumni access required' });
  next();
}
function alumniWrite(req: express.Request, res: express.Response, next: express.NextFunction) {
  const role = req.user ? getAppRole(req.user, 'alumni') : null;
  if (!canWrite(role)) return res.status(403).json({ success: false, error: 'Write access required' });
  next();
}
function alumniAdmin(req: express.Request, res: express.Response, next: express.NextFunction) {
  const role = req.user ? getAppRole(req.user, 'alumni') : null;
  if (!isAdmin(role)) return res.status(403).json({ success: false, error: 'Admin access required' });
  next();
}

// ══════════════════════════════════════════════════════════════
// ROSTER ROUTES
// ══════════════════════════════════════════════════════════════

// GET /sports — returns all active sports in this AppDB
app.get('/sports', auth, async (req, res) => {
  try {
    const db = appDb(req.user!);
    const { rows } = await db.execute('dbo.sp_GetSports', {}, {});
    return res.json({ success: true, data: rows });
  } catch (err) { console.error('[GET /sports]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// GET /players
app.get('/players', auth, rosterAccess, async (req, res) => {
  const { search, status, position, academicYear, recruitingClass, sportId, page, pageSize } = req.query as Record<string, string>;
  const p = parsePage(page); const ps = parsePageSize(pageSize);
  try {
    const db = appDb(req.user!);
    const { rows, output } = await db.execute(
      'dbo.sp_GetPlayers',
      {
        Search:          search           || null,
        Position:        position         || null,
        AcademicYear:    academicYear     || null,
        RecruitingClass: recruitingClass  ? parseInt(recruitingClass) : null,
        SportId:         sportId          || null,
        Page:            p,
        PageSize:        ps,
        ...reqCtx(req),
      },
      { TotalCount: 'int' }
    );
    return res.json({ success: true, data: rows, total: output.TotalCount, page: p, pageSize: ps });
  } catch (err) { console.error('[GET /players]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// GET /players/:id
app.get('/players/:id', auth, rosterAccess, async (req, res) => {
  try {
    const db = appDb(req.user!);
    const { sets, output } = await db.execute(
      'dbo.sp_GetPlayerById',
      { PlayerId: req.params.id, ...reqCtx(req) },
      { ErrorCode: 'nvarchar50' }
    );
    if (output.ErrorCode) return res.status(404).json({ success: false, error: 'Player not found' });
    return res.json({ success: true, data: { ...(sets[0]?.[0] ?? {}), stats: sets[1] ?? [] } });
  } catch (err) { console.error('[GET /players/:id]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /players
app.post('/players', auth, rosterAccess, rosterWrite, async (req, res) => {
  const b = validate(createPlayerSchema, req.body, res);
  if (!b) return;
  try {
    const db = appDb(req.user!);
    const { output } = await db.execute(
      'dbo.sp_CreatePlayer',
      {
        UserId:                b.userId,
        JerseyNumber:          b.jerseyNumber          ?? null,
        FirstName:             b.firstName,
        LastName:              b.lastName,
        Position:              b.position,
        AcademicYear:          b.academicYear,
        RecruitingClass:       b.recruitingClass,
        HeightInches:          b.heightInches          ?? null,
        WeightLbs:             b.weightLbs             ?? null,
        HomeTown:              b.homeTown              ?? null,
        HomeState:             b.homeState             ?? null,
        HighSchool:            b.highSchool            ?? null,
        Gpa:                   b.gpa                   ?? null,
        Major:                 b.major                 ?? null,
        Phone:                 b.phone                 ?? null,
        Email:                 b.email                 ?? null,
        Instagram:             b.instagram             ?? null,
        Twitter:               b.twitter               ?? null,
        Snapchat:              b.snapchat              ?? null,
        EmergencyContactName:  b.emergencyContactName  ?? null,
        EmergencyContactPhone: b.emergencyContactPhone ?? null,
        Notes:                 b.notes                 ?? null,
        CreatedBy:             req.user!.sub,
        ...reqCtx(req),
      },
      { NewPlayerId: 'uniqueidentifier', ErrorCode: 'nvarchar50' }
    );
    if (output.ErrorCode === 'JERSEY_NUMBER_IN_USE')           return res.status(409).json({ success: false, error: 'Jersey number already in use' });
    if (output.ErrorCode === 'PLAYER_ALREADY_EXISTS_FOR_USER') return res.status(409).json({ success: false, error: 'Player already exists for this user' });
    if (output.ErrorCode) return res.status(400).json({ success: false, error: output.ErrorCode });
    return res.status(201).json({ success: true, data: { id: output.NewPlayerId } });
  } catch (err) { console.error('[POST /players]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// PATCH /players/:id
// Access control delegated to sp_UpdatePlayer: admins update all fields,
// players may only update their own contact info. SP enforces this internally.
app.patch('/players/:id', auth, rosterAccess, async (req, res) => {
  const b    = req.body;
  const role = req.user ? getAppRole(req.user, 'roster') : null;
  const isWriter = canWrite(role);
  try {
    const db = appDb(req.user!);

    // If not an admin, verify ownership via SP before allowing update
    if (!isWriter) {
      const { rows, output } = await db.execute(
        'dbo.sp_GetPlayerById',
        { PlayerId: req.params.id, ...reqCtx(req) },
        { ErrorCode: 'nvarchar50' }
      );
      const playerRow = rows[0] as { userId?: string } | undefined;
      if (!playerRow || output.ErrorCode) return res.status(404).json({ success: false, error: 'Player not found' });
      if (playerRow.userId !== req.user!.sub) return res.status(403).json({ success: false, error: 'You can only edit your own profile' });
    }

    const { output } = await db.execute(
      'dbo.sp_UpdatePlayer',
      {
        PlayerId:              req.params.id,
        JerseyNumber:          isWriter ? (b.jerseyNumber ?? null) : null,
        Position:              isWriter ? (b.position     ?? null) : null,
        AcademicYear:          isWriter ? (b.academicYear ?? null) : null,
        Status:                isWriter ? (b.status       ?? null) : null,
        HeightInches:          isWriter ? (b.heightInches ?? null) : null,
        WeightLbs:             isWriter ? (b.weightLbs    ?? null) : null,
        Gpa:                   b.gpa                   ?? null,
        Major:                 b.major                 ?? null,
        Phone:                 b.phone                 ?? null,
        Email:                 b.email                 ?? null,
        Instagram:             b.instagram             ?? null,
        Twitter:               b.twitter               ?? null,
        Snapchat:              b.snapchat              ?? null,
        EmergencyContactName:  b.emergencyContactName  ?? null,
        EmergencyContactPhone: b.emergencyContactPhone ?? null,
        Notes:                 b.notes                 ?? null,
        UpdatedBy:             req.user!.sub,
        ...reqCtx(req),
      },
      { ErrorCode: 'nvarchar50' }
    );
    if (output.ErrorCode) return res.status(400).json({ success: false, error: output.ErrorCode });
    return res.json({ success: true, message: 'Player updated' });
  } catch (err) { console.error('[PATCH /players/:id]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /players/transfer
app.post('/players/transfer', auth, rosterAccess, rosterAdmin, async (req, res) => {
  const body = validate(transferSchema, req.body, res);
  if (!body) return;
  const { playerIds, transferReason, transferYear, transferSemester, notes = null } = body;
  try {
    const db = appDb(req.user!);

    // Step 1: Mark players graduated / transferred in roster schema
    const { output } = await db.execute(
      'dbo.sp_TransferToAlumni',
      {
        PlayerIds:        JSON.stringify(playerIds),
        TransferReason:   transferReason,
        TransferYear:     transferYear,
        TransferSemester: transferSemester,
        Notes:            notes,
        TriggeredBy:      req.user!.sub,
        ...reqCtx(req),
      },
      {
        TransactionId: 'uniqueidentifier',
        SuccessCount:  'int',
        FailureJson:   'nvarcharmax',
        PlayersJson:   'nvarcharmax',
      }
    );

    const transferredPlayers = JSON.parse((output.PlayersJson as string) || '[]');
    const failures           = JSON.parse((output.FailureJson  as string) || '[]');

    // Step 2: Create alumni records (same DB, no HTTP hop)
    const alumniFailures: Array<{ playerId: string; reason: string }> = [];
    for (const p of transferredPlayers) {
      try {
        const { output: ao } = await db.execute(
          'dbo.sp_CreateAlumniFromPlayer',
          {
            UserId:             p.userId,
            SourcePlayerId:     p.playerId,
            FirstName:          p.firstName,
            LastName:           p.lastName,
            GraduationYear:     transferYear,
            GraduationSemester: transferSemester,
            Position:           p.position,
            RecruitingClass:    p.recruitingClass,
            Phone:              p.phone        ?? null,
            PersonalEmail:      p.email        ?? null,
            ...reqCtx(req),
          },
          { NewAlumniId: 'uniqueidentifier', ErrorCode: 'nvarchar50' }
        );
        // ALUMNI_ALREADY_EXISTS is idempotent — not a failure
        if (ao.ErrorCode && ao.ErrorCode !== 'ALUMNI_ALREADY_EXISTS') {
          alumniFailures.push({ playerId: p.playerId, reason: ao.ErrorCode as string });
        }
      } catch (err: unknown) {
        alumniFailures.push({ playerId: p.playerId, reason: err instanceof Error ? err.message : 'Failed to create alumni record' });
      }
    }

    return res.json({
      success: true,
      data: {
        transactionId:    output.TransactionId,
        transferredCount: output.SuccessCount,
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
const bulkPlayerSchema = createPlayerSchema.omit({ userId: true }).extend({ userId: z.string().uuid().optional() });
app.post('/players/bulk', auth, rosterAccess, rosterWrite, async (req, res) => {
  const { players } = req.body;
  if (!Array.isArray(players) || players.length === 0) return res.status(400).json({ success: false, error: 'players array is required' });
  if (players.length > 500) return res.status(400).json({ success: false, error: 'Maximum 500 players per upload' });
  const validationErrors: Array<{ index: number; error: string }> = [];
  const validPlayers = players.map((p, i) => {
    const result = bulkPlayerSchema.safeParse(p);
    if (!result.success) validationErrors.push({ index: i, error: result.error.errors[0]?.message ?? 'Invalid record' });
    return result.success ? result.data : null;
  });
  if (validationErrors.length > 0) return res.status(400).json({ success: false, error: 'Validation failed', details: validationErrors });
  try {
    const db = appDb(req.user!);
    const { output } = await db.execute(
      'dbo.sp_BulkCreatePlayers',
      { PlayersJson: JSON.stringify(validPlayers), CreatedBy: req.user!.sub, ...reqCtx(req) },
      { SuccessCount: 'int', SkippedCount: 'int', ErrorJson: 'nvarcharmax' }
    );
    return res.json({
      success: true,
      data: {
        inserted: output.SuccessCount,
        skipped:  output.SkippedCount,
        errors:   JSON.parse((output.ErrorJson as string) || '[]'),
      },
    });
  } catch (err) { console.error('[POST /players/bulk]', err); return res.status(500).json({ success: false, error: 'Bulk insert failed' }); }
});

// POST /players/:id/stats
app.post('/players/:id/stats', auth, rosterAccess, rosterWrite, async (req, res) => {
  const body = validate(playerStatsSchema, req.body, res);
  if (!body) return;
  try {
    const db = appDb(req.user!);
    const { output } = await db.execute(
      'dbo.sp_UpsertPlayerStats',
      {
        PlayerId:    req.params.id,
        SeasonYear:  body.seasonYear,
        GamesPlayed: body.gamesPlayed ?? null,
        StatsJson:   body.statsJson ? JSON.stringify(body.statsJson) : null,
        ...reqCtx(req),
      },
      { ErrorCode: 'nvarchar50' }
    );
    if (output.ErrorCode) return res.status(400).json({ success: false, error: output.ErrorCode });
    return res.json({ success: true, message: 'Stats updated' });
  } catch (err) { console.error('[POST /players/:id/stats]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// ══════════════════════════════════════════════════════════════
// ALUMNI ROUTES
// ══════════════════════════════════════════════════════════════

// GET /alumni
app.get('/alumni', auth, alumniAccess, async (req, res) => {
  const { search, status, isDonor, gradYear, position, sportId, page, pageSize } = req.query as Record<string, string>;
  const p = parsePage(page); const ps = parsePageSize(pageSize);
  try {
    const db = appDb(req.user!);
    const { rows, output } = await db.execute(
      'dbo.sp_GetAlumni',
      {
        Search:   search   || null,
        IsDonor:  isDonor  ? isDonor === 'true' : null,
        GradYear: gradYear ? parseInt(gradYear) : null,
        Position: position || null,
        SportId:  sportId  || null,
        Page:     p,
        PageSize: ps,
        ...reqCtx(req),
      },
      { TotalCount: 'int' }
    );
    return res.json({ success: true, data: rows, total: output.TotalCount, page: p, pageSize: ps });
  } catch (err) { console.error('[GET /alumni]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// GET /alumni/:id
app.get('/alumni/:id', auth, alumniAccess, async (req, res) => {
  try {
    const db = appDb(req.user!);
    const { sets, output } = await db.execute(
      'dbo.sp_GetAlumniById',
      { AlumniId: req.params.id, ...reqCtx(req) },
      { ErrorCode: 'nvarchar50' }
    );
    if (output.ErrorCode) return res.status(404).json({ success: false, error: 'Alumni not found' });
    return res.json({ success: true, data: { ...(sets[0]?.[0] ?? {}), interactions: sets[1] ?? [] } });
  } catch (err) { console.error('[GET /alumni/:id]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /alumni
app.post('/alumni', auth, alumniAccess, async (req, res) => {
  const b = validate(createAlumniSchema, req.body, res);
  if (!b) return;
  try {
    const db = appDb(req.user!);
    const { output } = await db.execute(
      'dbo.sp_CreateAlumniFromPlayer',
      {
        UserId:             b.userId             ?? null,
        SourcePlayerId:     b.sourcePlayerId     ?? null,
        FirstName:          b.firstName,
        LastName:           b.lastName,
        GraduationYear:     b.graduationYear,
        GraduationSemester: b.graduationSemester,
        Position:           b.position           ?? null,
        RecruitingClass:    b.recruitingClass    ?? null,
        Phone:              b.phone              ?? null,
        PersonalEmail:      b.personalEmail      ?? null,
        ...reqCtx(req),
      },
      { NewAlumniId: 'uniqueidentifier', ErrorCode: 'nvarchar50' }
    );
    if (output.ErrorCode && output.ErrorCode !== 'ALUMNI_ALREADY_EXISTS')
      return res.status(400).json({ success: false, error: output.ErrorCode });
    return res.status(201).json({ success: true, data: { id: output.NewAlumniId } });
  } catch (err) { console.error('[POST /alumni]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// PATCH /alumni/:id
// Ownership verification delegated to sp_UpdateAlumni — no inline SQL.
app.patch('/alumni/:id', auth, alumniAccess, async (req, res) => {
  const b    = req.body;
  const role = req.user ? getAppRole(req.user, 'alumni') : null;
  const isWriter = canWrite(role);
  try {
    const db = appDb(req.user!);

    // For non-admins: ownership check via SP (no inline SQL)
    if (!isWriter) {
      const { rows, output: chk } = await db.execute(
        'dbo.sp_GetAlumniById',
        { AlumniId: req.params.id, ...reqCtx(req) },
        { ErrorCode: 'nvarchar50' }
      );
      const alumniRow = rows[0] as { userId?: string } | undefined;
      if (!alumniRow || chk.ErrorCode) return res.status(404).json({ success: false, error: 'Alumni not found' });
      if (alumniRow.userId !== req.user!.sub) return res.status(403).json({ success: false, error: 'You can only edit your own profile' });
    }

    const { output } = await db.execute(
      'dbo.sp_UpdateAlumni',
      {
        AlumniId:         req.params.id,
        Status:           isWriter ? (b.status           ?? null) : null,
        IsDonor:          isWriter ? (b.isDonor          ?? null) : null,
        LastDonationDate: isWriter && b.lastDonationDate ? new Date(b.lastDonationDate) : null,
        TotalDonations:   isWriter ? (b.totalDonations   ?? null) : null,
        PersonalEmail:    b.personalEmail    ?? null,
        Phone:            b.phone            ?? null,
        LinkedInUrl:      b.linkedInUrl      ?? null,
        TwitterUrl:       b.twitterUrl       ?? null,
        CurrentEmployer:  b.currentEmployer  ?? null,
        CurrentJobTitle:  b.currentJobTitle  ?? null,
        CurrentCity:      b.currentCity      ?? null,
        CurrentState:     b.currentState     ?? null,
        Notes:            b.notes            ?? null,
        UpdatedBy:        req.user!.sub,
        ...reqCtx(req),
      },
      { ErrorCode: 'nvarchar50' }
    );
    if (output.ErrorCode) return res.status(400).json({ success: false, error: output.ErrorCode });
    return res.json({ success: true, message: 'Alumni updated' });
  } catch (err) { console.error('[PATCH /alumni/:id]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /alumni/:id/interactions
app.post('/alumni/:id/interactions', auth, alumniAccess, alumniWrite, async (req, res) => {
  const body = validate(logInteractionSchema, req.body, res);
  if (!body) return;
  try {
    const db = appDb(req.user!);
    const { output } = await db.execute(
      'dbo.sp_LogInteraction',
      {
        AlumniId:   req.params.id,
        LoggedBy:   req.user!.sub,
        Channel:    body.channel,
        Summary:    body.summary,
        Outcome:    body.outcome    ?? null,
        FollowUpAt: body.followUpAt ? new Date(body.followUpAt) : null,
        ...reqCtx(req),
      },
      { ErrorCode: 'nvarchar50' }
    );
    if (output.ErrorCode) return res.status(400).json({ success: false, error: output.ErrorCode });
    return res.status(201).json({ success: true, message: 'Interaction logged' });
  } catch (err) { console.error('[POST /alumni/:id/interactions]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /alumni/bulk
app.post('/alumni/bulk', auth, alumniAccess, alumniWrite, async (req, res) => {
  const { alumni } = req.body;
  if (!Array.isArray(alumni) || alumni.length === 0) return res.status(400).json({ success: false, error: 'alumni array is required' });
  if (alumni.length > 500) return res.status(400).json({ success: false, error: 'Maximum 500 alumni per upload' });
  const validationErrors: Array<{ index: number; error: string }> = [];
  const validAlumni = alumni.map((a, i) => {
    const result = createAlumniSchema.safeParse(a);
    if (!result.success) validationErrors.push({ index: i, error: result.error.errors[0]?.message ?? 'Invalid record' });
    return result.success ? result.data : null;
  });
  if (validationErrors.length > 0) return res.status(400).json({ success: false, error: 'Validation failed', details: validationErrors });
  try {
    const db = appDb(req.user!);
    const { output } = await db.execute(
      'dbo.sp_BulkCreateAlumni',
      { AlumniJson: JSON.stringify(validAlumni), CreatedBy: req.user!.sub, ...reqCtx(req) },
      { SuccessCount: 'int', SkippedCount: 'int', ErrorJson: 'nvarcharmax' }
    );
    return res.json({
      success: true,
      data: {
        inserted: output.SuccessCount,
        skipped:  output.SkippedCount,
        errors:   JSON.parse((output.ErrorJson as string) || '[]'),
      },
    });
  } catch (err) { console.error('[POST /alumni/bulk]', err); return res.status(500).json({ success: false, error: 'Bulk insert failed' }); }
});

// ══════════════════════════════════════════════════════════════
// CAMPAIGNS & STATS
// ══════════════════════════════════════════════════════════════

// GET /campaigns
app.get('/campaigns', auth, alumniAccess, async (req, res) => {
  try {
    const db = appDb(req.user!);
    const { rows } = await db.execute('dbo.sp_GetCampaigns', { ...reqCtx(req) });
    return res.json({ success: true, data: rows });
  } catch (err) { console.error('[GET /campaigns]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /campaigns
app.post('/campaigns', auth, alumniAccess, alumniAdmin, async (req, res) => {
  const body = validate(createCampaignSchema, req.body, res);
  if (!body) return;
  try {
    const db = appDb(req.user!);
    const { output } = await db.execute(
      'dbo.sp_CreateCampaign',
      {
        Name:            body.name,
        Description:     body.description     ?? null,
        TargetAudience:  body.targetAudience,
        AudienceFilters: body.audienceFilters ? JSON.stringify(body.audienceFilters) : null,
        ScheduledAt:     body.scheduledAt ? new Date(body.scheduledAt) : null,
        CreatedBy:       req.user!.sub,
        ...reqCtx(req),
      },
      { NewCampaignId: 'uniqueidentifier', ErrorCode: 'nvarchar50' }
    );
    if (output.ErrorCode) return res.status(400).json({ success: false, error: output.ErrorCode });
    return res.status(201).json({ success: true, data: { id: output.NewCampaignId } });
  } catch (err) { console.error('[POST /campaigns]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// GET /stats
app.get('/stats', auth, alumniAccess, async (req, res) => {
  try {
    const db = appDb(req.user!);
    const { rows } = await db.execute('dbo.sp_GetAlumniStats', { ...reqCtx(req) });
    const row = rows[0] as Record<string, unknown> | undefined;
    if (row?.classCounts) row.classCounts = JSON.parse(row.classCounts as string);
    return res.json({ success: true, data: row });
  } catch (err) { console.error('[GET /stats]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
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
