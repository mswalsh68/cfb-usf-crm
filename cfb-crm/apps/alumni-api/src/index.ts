import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { verifyAccessToken, extractBearerToken, hasAppAccess, getAppRole, isAdmin } from '@cfb-crm/auth';
import type { AuthTokenPayload } from '@cfb-crm/types';
import { getClientDb, sql } from '@cfb-crm/db';
import { getHealthDb } from './db';

// Returns a connection pool scoped to this user's alumni database
function alumniDb(user: AuthTokenPayload) {
  return getClientDb({
    server:    user.dbServer,
    database:  user.appDb,
    user:      process.env.DB_USER,
    password:  process.env.DB_PASS,
    encrypt:   process.env.DB_ENCRYPT === 'true',
    trustCert: process.env.DB_TRUST_CERT === 'true',
  });
}

const app  = express();
const PORT = process.env.PORT || 3003;

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

const alumniAccess = (req: express.Request, res: express.Response, next: express.NextFunction) => {
  if (!req.user || !hasAppAccess(req.user, 'alumni')) return res.status(403).json({ success: false, error: 'Alumni access required' });
  next();
};

const alumniWrite = (req: express.Request, res: express.Response, next: express.NextFunction) => {
  const role = req.user ? getAppRole(req.user, 'alumni') : null;
  if (!role || !['global_admin','app_admin','coach_staff'].includes(role)) return res.status(403).json({ success: false, error: 'Write access required' });
  next();
};

const alumniAdmin = (req: express.Request, res: express.Response, next: express.NextFunction) => {
  const role = req.user ? getAppRole(req.user, 'alumni') : null;
  if (!role || !isAdmin(role)) return res.status(403).json({ success: false, error: 'Admin access required' });
  next();
};

// GET /alumni
app.get('/alumni', auth, alumniAccess, async (req, res) => {
  const { search, status, isDonor, gradYear, position, page = '1', pageSize = '50' } = req.query as Record<string, string>;
  try {
    const db = await alumniDb(req.user!);
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
    const db = await alumniDb(req.user!);
    const r = await db.request()
      .input('AlumniId',   sql.UniqueIdentifier, req.params.id)
      .output('ErrorCode', sql.NVarChar(50))
      .execute('dbo.sp_GetAlumniById');
    if (r.output.ErrorCode) return res.status(404).json({ success: false, error: 'Alumni not found' });
    return res.json({ success: true, data: { ...(r.recordsets as any)[0][0], interactions: (r.recordsets as any)[1] } });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// PATCH /alumni/:id
// Admins/coaches can update all fields including status and donor info.
// Alumni can only update their own record and only personal/contact fields.
app.patch('/alumni/:id', auth, alumniAccess, async (req, res) => {
  const b    = req.body;
  const role = req.user ? getAppRole(req.user, 'alumni') : null;
  const isWriter = role && ['global_admin', 'app_admin', 'coach_staff'].includes(role);

  try {
    const db = await alumniDb(req.user!);

    // If not a writer, verify the caller owns this alumni record
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
      // Admin-only fields — alumni send null so SP leaves them unchanged
      .input('Status',           sql.NVarChar,         isWriter ? (b.status           ?? null) : null)
      .input('IsDonor',          sql.Bit,              isWriter ? (b.isDonor          ?? null) : null)
      .input('LastDonationDate', sql.Date,             isWriter && b.lastDonationDate ? new Date(b.lastDonationDate) : null)
      .input('TotalDonations',   sql.Decimal(10,2),    isWriter ? (b.totalDonations   ?? null) : null)
      // Personal fields — alumni can update their own
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
  const { channel, summary, outcome, followUpAt } = req.body;
  try {
    const db = await alumniDb(req.user!);
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

// ─── POST /alumni ─────────────────────────────────────────────
app.post('/alumni',  auth, alumniAccess , async (req, res) => {
  const b = req.body;
  try {
    const db = await alumniDb(req.user!);
    const result = await db.request()
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
    // ALUMNI_ALREADY_EXISTS is idempotent — treat as success
    if (result.output.ErrorCode && result.output.ErrorCode !== 'ALUMNI_ALREADY_EXISTS')
      return res.status(400).json({ success: false, error: result.output.ErrorCode });
    return res.status(201).json({ success: true, data: { id: result.output.NewAlumniId } });
  } catch (err) {
    console.error('[POST /alumni]', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// GET /campaigns
app.get('/campaigns', auth, alumniAccess, async (req, res) => {
  try {
    const db = await alumniDb(req.user!);
    const r = await db.request().execute('dbo.sp_GetCampaigns');
    return res.json({ success: true, data: r.recordset });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /campaigns
app.post('/campaigns', auth, alumniAccess, alumniAdmin, async (req, res) => {
  const { name, description, targetAudience, audienceFilters, scheduledAt } = req.body;
  try {
    const db = await alumniDb(req.user!);
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
    const db = await alumniDb(req.user!);
    const r = await db.request().execute('dbo.sp_GetAlumniStats');
    const row = r.recordset[0];
    if (row?.classCounts) row.classCounts = JSON.parse(row.classCounts);
    return res.json({ success: true, data: row });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});


app.post('/alumni/bulk', auth, alumniAccess, alumniWrite, async (req, res) => {
  const { alumni } = req.body;
  if (!Array.isArray(alumni) || alumni.length === 0)
    return res.status(400).json({ success: false, error: 'alumni array is required' });
  if (alumni.length > 500)
    return res.status(400).json({ success: false, error: 'Maximum 500 alumni per upload' });
  try {
    const db = await alumniDb(req.user!);
    const r = await db.request()
    .input('AlumniJson',    sql.NVarChar(sql.MAX), JSON.stringify(alumni))
      .input('CreatedBy',     sql.UniqueIdentifier,  req.user!.sub)
      .output('SuccessCount', sql.Int)
      .output('SkippedCount', sql.Int)
      .output('ErrorJson',    sql.NVarChar(sql.MAX))
      .execute('dbo.sp_BulkCreateAlumni');
      return res.json({ success: true, data: { inserted: r.output.SuccessCount, skipped: r.output.SkippedCount, errors: JSON.parse(r.output.ErrorJson || '[]') } });
    } catch (err) {
      console.error('[POST /alumni/bulk]', err);
      return res.status(500).json({ success: false, error: 'Bulk insert failed' });
    }
  });
  
  // Health
  app.get('/health', async (_req, res) => {
    try {
      const db = await getHealthDb();
      await db.request().query('SELECT 1');
      res.json({ success: true, service: 'alumni-api', db: 'connected' });
    } catch {
      res.status(503).json({ success: false, service: 'alumni-api', db: 'disconnected' });
    }
  });

  
app.listen(PORT, () => console.log(`[Alumni API] Running on port ${PORT}`));
export default app;