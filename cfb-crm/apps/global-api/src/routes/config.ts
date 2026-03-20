import { Router } from 'express';
import { requireAuth, requireGlobalAdmin } from '../middleware/auth';
import { getDb, sql } from '../db';

export const configRouter = Router();

const DEFAULT_POSITIONS     = ['QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH'];
const DEFAULT_ACADEMIC_YEARS = [
  { value: 'freshman',  label: 'Freshman'  },
  { value: 'sophomore', label: 'Sophomore' },
  { value: 'junior',    label: 'Junior'    },
  { value: 'senior',    label: 'Senior'    },
  { value: 'graduate',  label: 'Graduate'  },
];

// GET /config — public, no auth required
// Web app fetches this on load to apply theme and get dynamic config
configRouter.get('/', async (_req, res) => {
  try {
    const db = await getDb();
    const r  = await db.request().execute('dbo.sp_GetTeamConfig');
    const row = r.recordset[0];
    if (!row) return res.status(500).json({ success: false, error: 'Team config not found' });

    const config = {
      ...row,
      positions:     row.positionsJson     ? JSON.parse(row.positionsJson)     : DEFAULT_POSITIONS,
      academicYears: row.academicYearsJson ? JSON.parse(row.academicYearsJson) : DEFAULT_ACADEMIC_YEARS,
      positionsJson:     undefined,
      academicYearsJson: undefined,
    };

    return res.json({ success: true, data: config });
  } catch (err) {
    console.error('[GET /config]', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// PATCH /config — global admin only
configRouter.patch('/', requireAuth, requireGlobalAdmin, async (req, res) => {
  const b = req.body;
  try {
    const db = await getDb();
    const r  = await db.request()
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
