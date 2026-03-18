import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import sql from 'mssql';
import { verifyAccessToken, extractBearerToken, hasAppAccess, getAppRole, isAdmin } from '@cfb-crm/auth';
import type { AuthTokenPayload } from '@cfb-crm/types';

const dbConfig: sql.config = {
  server: process.env.ALUMNI_DB_SERVER!, database: process.env.ALUMNI_DB_NAME!,
  authentication: process.env.NODE_ENV === 'development'
    ? { type: 'default', options: { userName: process.env.ALUMNI_DB_USER!, password: process.env.ALUMNI_DB_PASS! } }
    : { type: 'azure-active-directory-default' },
  options: { encrypt: true, enableArithAbort: true }, pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
};
let pool: sql.ConnectionPool | null = null;
async function getDb() { if (pool?.connected) return pool; pool = await sql.connect(dbConfig); return pool; }

const app  = express();
const PORT = process.env.PORT || 3003;
app.use(helmet()); app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(','), credentials: true }));
app.use(rateLimit({ windowMs: 15 * 60 * 1000, max: 500 })); app.use(express.json({ limit: '10kb' }));
declare global { namespace Express { interface Request { user?: AuthTokenPayload } } }

function auth(req: express.Request, res: express.Response, next: express.NextFunction) {
  const token = extractBearerToken(req.headers.authorization);
  if (!token) return res.status(401).json({ success: false, error: 'Authentication required' });
  try { req.user = verifyAccessToken(token); next(); } catch { return res.status(401).json({ success: false, error: 'Invalid token' }); }
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

// GET /alumni — sp_GetAlumni
app.get('/alumni', auth, alumniAccess, async (req, res) => {
  const { search, status, isDonor, gradYear, position, page = '1', pageSize = '50' } = req.query as Record<string, string>;
  try {
    const db = await getDb();
    const r = await db.request()
      .input('Search',    sql.NVarChar, search   || null)
      .input('Status',    sql.NVarChar, status   || null)
      .input('IsDonor',   sql.Bit,      isDonor  ? isDonor === 'true' : null)
      .input('GradYear',  sql.SmallInt, gradYear ? parseInt(gradYear) : null)
      .input('Position',  sql.NVarChar, position || null)
      .input('Page',      sql.Int,      parseInt(page))
      .input('PageSize',  sql.Int,      parseInt(pageSize))
      .output('TotalCount', sql.Int)
      .execute('dbo.sp_GetAlumni');
    return res.json({ success: true, data: r.recordset, total: r.output.TotalCount, page: parseInt(page), pageSize: parseInt(pageSize) });
  } catch (err) { console.error('[GET /alumni]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// GET /alumni/:id — sp_GetAlumniById
app.get('/alumni/:id', auth, alumniAccess, async (req, res) => {
  try {
    const db = await getDb();
    const r = await db.request()
      .input('AlumniId',  sql.UniqueIdentifier, req.params.id)
      .output('ErrorCode', sql.NVarChar(50))
      .execute('dbo.sp_GetAlumniById');
    if (r.output.ErrorCode) return res.status(404).json({ success: false, error: 'Alumni not found' });
    return res.json({ success: true, data: { ...r.recordsets[0][0], interactions: r.recordsets[1] } });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// PATCH /alumni/:id — sp_UpdateAlumni (also recalculates engagement score in SQL)
app.patch('/alumni/:id', auth, alumniAccess, alumniWrite, async (req, res) => {
  const b = req.body;
  try {
    const db = await getDb();
    const r = await db.request()
      .input('AlumniId',        sql.UniqueIdentifier, req.params.id)
      .input('Status',          sql.NVarChar,         b.status          ?? null)
      .input('PersonalEmail',   sql.NVarChar,         b.personalEmail   ?? null)
      .input('Phone',           sql.NVarChar,         b.phone           ?? null)
      .input('LinkedInUrl',     sql.NVarChar,         b.linkedInUrl     ?? null)
      .input('CurrentEmployer', sql.NVarChar,         b.currentEmployer ?? null)
      .input('CurrentJobTitle', sql.NVarChar,         b.currentJobTitle ?? null)
      .input('CurrentCity',     sql.NVarChar,         b.currentCity     ?? null)
      .input('CurrentState',    sql.NVarChar,         b.currentState    ?? null)
      .input('IsDonor',         sql.Bit,              b.isDonor         ?? null)
      .input('LastDonationDate',sql.Date,             b.lastDonationDate ? new Date(b.lastDonationDate) : null)
      .input('TotalDonations',  sql.Decimal(10,2),    b.totalDonations  ?? null)
      .input('Notes',           sql.NVarChar,         b.notes           ?? null)
      .input('UpdatedBy',       sql.UniqueIdentifier, req.user!.sub)
      .output('ErrorCode',      sql.NVarChar(50))
      .execute('dbo.sp_UpdateAlumni');
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.json({ success: true, message: 'Alumni updated' });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /alumni/:id/interactions — sp_LogInteraction (also bumps engagement score in SQL)
app.post('/alumni/:id/interactions', auth, alumniAccess, alumniWrite, async (req, res) => {
  const { channel, summary, outcome, followUpAt } = req.body;
  try {
    const db = await getDb();
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

// GET /campaigns — sp_GetCampaigns (response metrics computed in SQL)
app.get('/campaigns', auth, alumniAccess, async (_req, res) => {
  try {
    const db = await getDb();
    const r = await db.request().execute('dbo.sp_GetCampaigns');
    return res.json({ success: true, data: r.recordset });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /campaigns — sp_CreateCampaign
app.post('/campaigns', auth, alumniAccess, alumniAdmin, async (req, res) => {
  const { name, description, targetAudience, audienceFilters, scheduledAt } = req.body;
  try {
    const db = await getDb();
    const r = await db.request()
      .input('Name',            sql.NVarChar,         name)
      .input('Description',     sql.NVarChar,         description      || null)
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

// GET /stats — sp_GetAlumniStats (all aggregation in SQL)
app.get('/stats', auth, alumniAccess, async (_req, res) => {
  try {
    const db = await getDb();
    const r = await db.request().execute('dbo.sp_GetAlumniStats');
    const row = r.recordset[0];
    if (row?.classCounts) row.classCounts = JSON.parse(row.classCounts);
    return res.json({ success: true, data: row });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// Health
app.get('/health', async (_req, res) => {
  try { const db = await getDb(); await db.request().query('SELECT 1'); res.json({ success: true, service: 'alumni-api', db: 'connected' }); }
  catch { res.status(503).json({ success: false, service: 'alumni-api', db: 'disconnected' }); }
});

app.listen(PORT, () => console.log(`[Alumni API] Running on port ${PORT}`));
export default app;
