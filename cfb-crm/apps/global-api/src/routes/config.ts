import { Router } from 'express';
import { requireAuth, requireGlobalAdmin } from '../middleware/auth';
import { extractBearerToken, verifyAccessToken } from '@cfb-crm/auth';
import { getDb, sql } from '../db';
import { DEFAULT_POSITIONS, DEFAULT_ACADEMIC_YEARS } from '../constants';

export const configRouter = Router();

function parseConfigRow(row: Record<string, unknown>) {
  return {
    ...row,
    positions:     row.positionsJson     ? JSON.parse(row.positionsJson as string)     : DEFAULT_POSITIONS,
    academicYears: row.academicYearsJson ? JSON.parse(row.academicYearsJson as string) : DEFAULT_ACADEMIC_YEARS,
    positionsJson:     undefined,
    academicYearsJson: undefined,
  };
}

// GET /config — public, no auth required
// Resolves the team to serve:
//   1. ?teamId query param (platform_owner only — validated in route)
//   2. currentTeamId from JWT (if a valid token is present in Authorization header)
//   3. First/default team config (fallback for unauthenticated / ThemeProvider initial load)
configRouter.get('/', async (req, res) => {
  try {
    const db = await getDb();

    // Try to resolve teamId from JWT (optional auth)
    // Accept token from Authorization header (mobile) OR httpOnly cookie (web)
    let teamId: string | null = null;
    const token = extractBearerToken(req.headers.authorization) ?? req.cookies?.cfb_access_token ?? null;
    if (token) {
      try {
        const decoded = verifyAccessToken(token);
        // platform_owner can request any team via ?teamId query param
        if (decoded.globalRole === 'platform_owner' && req.query.teamId) {
          teamId = req.query.teamId as string;
        } else {
          teamId = decoded.currentTeamId || null;
        }
      } catch {
        // Invalid token — fall through to default config
      }
    }

    const r = await db.request()
      .input('TeamId', sql.UniqueIdentifier, teamId ?? null)
      .execute('dbo.sp_GetTeamConfig');

    const row = r.recordset[0];
    if (!row) return res.status(500).json({ success: false, error: 'Team config not found' });

    return res.json({ success: true, data: parseConfigRow(row) });
  } catch (err) {
    console.error('[GET /config]', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// PATCH /config — global admin only, uses currentTeamId from JWT
configRouter.patch('/', requireAuth, requireGlobalAdmin, async (req, res) => {
  const b      = req.body;
  const teamId = req.user!.currentTeamId || null;
  try {
    const db = await getDb();
    const r  = await db.request()
      .input('TeamId',            sql.UniqueIdentifier,  teamId ?? null)
      .input('TeamName',          sql.NVarChar,          b.teamName          ?? null)
      .input('TeamAbbr',          sql.NVarChar,          b.teamAbbr          ?? null)
      .input('Sport',             sql.NVarChar,          b.sport             ?? null)
      .input('Level',             sql.NVarChar,          b.level             ?? null)
      .input('LogoUrl',           sql.NVarChar,          b.logoUrl           ?? null)
      .input('ColorPrimary',      sql.NVarChar,          b.colorPrimary      ?? null)
      .input('ColorPrimaryDark',  sql.NVarChar,          b.colorPrimaryDark  ?? null)
      .input('ColorPrimaryLight', sql.NVarChar,          b.colorPrimaryLight ?? null)
      .input('ColorAccent',       sql.NVarChar,          b.colorAccent       ?? null)
      .input('ColorAccentDark',   sql.NVarChar,          b.colorAccentDark   ?? null)
      .input('ColorAccentLight',  sql.NVarChar,          b.colorAccentLight  ?? null)
      .input('PositionsJson',     sql.NVarChar(sql.MAX), b.positions     ? JSON.stringify(b.positions)     : null)
      .input('AcademicYearsJson', sql.NVarChar(sql.MAX), b.academicYears ? JSON.stringify(b.academicYears) : null)
      .input('AlumniLabel',       sql.NVarChar,          b.alumniLabel       ?? null)
      .input('RosterLabel',       sql.NVarChar,          b.rosterLabel       ?? null)
      .input('ClassLabel',        sql.NVarChar,          b.classLabel        ?? null)
      .output('ErrorCode',        sql.NVarChar(50))
      .execute('dbo.sp_UpdateTeamConfig');

    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.json({ success: true, message: 'Team config updated' });
  } catch (err) {
    console.error('[PATCH /config]', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});
