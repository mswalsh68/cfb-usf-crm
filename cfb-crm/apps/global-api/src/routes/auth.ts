import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { signAccessToken, signRefreshToken, verifyRefreshToken } from '@cfb-crm/auth';
import type { AuthTokenPayload, TeamSummary } from '@cfb-crm/types';
import { getDb, sql } from '../db';
import { requireAuth } from '../middleware/auth';
import { DEFAULT_POSITIONS, DEFAULT_ACADEMIC_YEARS } from '../constants';

export const authRouter = Router();
const hash = (t: string) => crypto.createHash('sha256').update(t).digest('hex');

function audit(event: string, details: Record<string, unknown>) {
  console.log(JSON.stringify({ type: 'AUDIT', event, timestamp: new Date().toISOString(), ...details }));
}

const COOKIE_BASE = {
  httpOnly: true,
  secure:   process.env.NODE_ENV === 'production',
  sameSite: 'strict' as const,
  path:     '/',
};
const ACCESS_COOKIE_OPTS  = { ...COOKIE_BASE, maxAge: 15 * 60 * 1000 };
const REFRESH_COOKIE_OPTS = { ...COOKIE_BASE, maxAge: 7 * 24 * 60 * 60 * 1000 };

interface SpUserJson {
  email:          string;
  globalRole:     string;
  currentTeamId?: string;
  teams?:         TeamSummary[];
  appPermissions?: AuthTokenPayload['appPermissions'];
  appDb?:         string;
  dbServer?:      string;
}

/** Build access token payload from sp_Login / sp_RefreshToken JSON output */
function buildAccessToken(userId: string, user: SpUserJson, overrideTeamId?: string): string {
  const teams: TeamSummary[] = user.teams ?? [];

  // Honour the client's currentTeamId if it's still in their team list
  let currentTeamId = overrideTeamId ?? user.currentTeamId ?? '';
  const teamStillValid = teams.some(t => t.teamId === currentTeamId);
  if (!teamStillValid && teams.length > 0) currentTeamId = teams[0].teamId;

  // Resolve DB routing from the matching team (if available) or fall back to top-level fields
  const currentTeam = teams.find(t => t.teamId === currentTeamId);

  const payload: Omit<AuthTokenPayload, 'iat' | 'exp'> = {
    sub:           userId,
    email:         user.email,
    globalRole:    user.globalRole,
    currentTeamId,
    teams,
    appPermissions: user.appPermissions ?? [],
    appDb:    user.appDb    ?? '',
    dbServer:  user.dbServer  ?? '',
  };

  return signAccessToken(payload);
}

// ─── POST /auth/login ─────────────────────────────────────────────────────────
authRouter.post('/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ success: false, error: 'Email and password required' });
  try {
    const db = await getDb();
    const r = await db.request()
      .input('Email',      sql.NVarChar, email.trim().toLowerCase())
      .input('IpAddress',  sql.NVarChar, req.ip ?? null)
      .input('DeviceInfo', sql.NVarChar, req.headers['user-agent'] ?? null)
      .output('UserId',       sql.UniqueIdentifier)
      .output('PasswordHash', sql.NVarChar(255))
      .output('UserJson',     sql.NVarChar(sql.MAX))
      .output('ErrorCode',    sql.NVarChar(50))
      .execute('dbo.sp_Login');

    const { ErrorCode, UserId, PasswordHash, UserJson } = r.output;
    if (ErrorCode) return res.status(401).json({ success: false, error: 'Invalid credentials' });

    const ok = await bcrypt.compare(password, PasswordHash);
    if (!ok) {
      audit('LOGIN_FAILED', { email: email.trim().toLowerCase(), ip: req.ip, reason: 'bad_password' });
      return res.status(401).json({ success: false, error: 'Invalid credentials' });
    }

    const user        = JSON.parse(UserJson);
    const accessToken = buildAccessToken(UserId, user);
    const refreshToken = signRefreshToken(UserId);

    await db.request()
      .input('UserId',     sql.UniqueIdentifier, UserId)
      .input('TokenHash',  sql.NVarChar,         hash(refreshToken))
      .input('ExpiresAt',  sql.DateTime2,        new Date(Date.now() + 7 * 24 * 60 * 60 * 1000))
      .input('DeviceInfo', sql.NVarChar,         req.headers['user-agent'] ?? null)
      .execute('dbo.sp_StoreRefreshToken');

    audit('LOGIN_SUCCESS', { userId: UserId, email: email.trim().toLowerCase(), ip: req.ip });
    return res
      .cookie('cfb_access_token',  accessToken,  ACCESS_COOKIE_OPTS)
      .cookie('cfb_refresh_token', refreshToken, REFRESH_COOKIE_OPTS)
      .json({ success: true, data: { accessToken, refreshToken, user } });
  } catch (err) {
    console.error('[Login]', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// ─── POST /auth/refresh ───────────────────────────────────────────────────────
// Accepts refresh token from httpOnly cookie (web) or request body (mobile).
// Accepts optional currentTeamId so the client's active team is preserved.
authRouter.post('/refresh', async (req, res) => {
  const refreshToken = req.body.refreshToken ?? req.cookies?.cfb_refresh_token;
  const { currentTeamId } = req.body;
  if (!refreshToken) return res.status(400).json({ success: false, error: 'Refresh token required' });
  try { verifyRefreshToken(refreshToken); } catch { return res.status(401).json({ success: false, error: 'Invalid token' }); }
  try {
    const db         = await getDb();
    const newRefresh = signRefreshToken(crypto.randomUUID());
    const expiresAt  = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    const r = await db.request()
      .input('OldTokenHash',  sql.NVarChar,       hash(refreshToken))
      .input('NewTokenHash',  sql.NVarChar,       hash(newRefresh))
      .input('NewExpiresAt',  sql.DateTime2,      expiresAt)
      .input('CurrentTeamId', sql.UniqueIdentifier, currentTeamId ?? null)
      .output('UserJson',     sql.NVarChar(sql.MAX))
      .output('ErrorCode',    sql.NVarChar(50))
      .execute('dbo.sp_RefreshToken');

    if (r.output.ErrorCode) return res.status(401).json({ success: false, error: 'Token invalid or expired' });

    const user        = JSON.parse(r.output.UserJson);
    const accessToken = buildAccessToken(user.id, user, currentTeamId);

    return res
      .cookie('cfb_access_token',  accessToken, ACCESS_COOKIE_OPTS)
      .cookie('cfb_refresh_token', newRefresh,  REFRESH_COOKIE_OPTS)
      .json({ success: true, data: { accessToken, refreshToken: newRefresh } });
  } catch (err) {
    console.error('[Refresh]', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// ─── POST /auth/switch-team ───────────────────────────────────────────────────
// Issues a new access token with updated currentTeamId.
// platform_owner can switch to any active team.
// Regular users can only switch to teams in their user_teams rows.
authRouter.post('/switch-team', requireAuth, async (req, res) => {
  const { teamId } = req.body;
  if (!teamId) return res.status(400).json({ success: false, error: 'teamId required' });
  try {
    const db = await getDb();
    const r = await db.request()
      .input('UserId',    sql.UniqueIdentifier, req.user!.sub)
      .input('NewTeamId', sql.UniqueIdentifier, teamId)
      .output('TeamJson', sql.NVarChar(sql.MAX))
      .output('ErrorCode', sql.NVarChar(50))
      .execute('dbo.sp_SwitchTeam');

    if (r.output.ErrorCode) {
      const status = r.output.ErrorCode === 'ACCESS_DENIED' ? 403 : 404;
      return res.status(status).json({ success: false, error: r.output.ErrorCode });
    }

    const teamData = JSON.parse(r.output.TeamJson);

    // Re-sign the access token with the new currentTeamId and updated DB routing
    const updatedUser = {
      ...req.user!,
      currentTeamId: teamId,
      appDb:    teamData.appDb,
      dbServer: teamData.dbServer,
    };
    const newAccessToken = signAccessToken({
      sub:            updatedUser.sub,
      email:          updatedUser.email,
      globalRole:     updatedUser.globalRole,
      currentTeamId:  teamId,
      teams:          updatedUser.teams ?? [],
      appPermissions: updatedUser.appPermissions ?? [],
      appDb:          teamData.appDb,
      dbServer:       teamData.dbServer,
    });

    const teamConfig = {
      ...teamData,
      positions:     teamData.positionsJson     ? JSON.parse(teamData.positionsJson)     : DEFAULT_POSITIONS,
      academicYears: teamData.academicYearsJson ? JSON.parse(teamData.academicYearsJson) : DEFAULT_ACADEMIC_YEARS,
      positionsJson:     undefined,
      academicYearsJson: undefined,
    };

    return res
      .cookie('cfb_access_token', newAccessToken, ACCESS_COOKIE_OPTS)
      .json({ success: true, data: { accessToken: newAccessToken, teamConfig } });
  } catch (err) {
    console.error('[switch-team]', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// ─── GET /auth/invite/:token ──────────────────────────────────────────────────
authRouter.get('/invite/:token', async (req, res) => {
  try {
    const db = await getDb();
    const r  = await db.request()
      .input('TokenHash', sql.NVarChar, hash(req.params.token))
      .execute('dbo.sp_ValidateInviteToken');
    if (!r.recordset.length) return res.status(404).json({ success: false, error: 'Invite link is invalid or has expired' });
    return res.json({ success: true, data: r.recordset[0] });
  } catch (err) {
    console.error('[GET /auth/invite]', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// ─── POST /auth/accept-invite ─────────────────────────────────────────────────
authRouter.post('/accept-invite', async (req, res) => {
  const { token, password } = req.body;
  if (!token || !password) return res.status(400).json({ success: false, error: 'token and password are required' });
  if (password.length < 10) return res.status(400).json({ success: false, error: 'Password must be at least 10 characters' });
  try {
    const db           = await getDb();
    const passwordHash = await bcrypt.hash(password, 12);
    const r = await db.request()
      .input('TokenHash',    sql.NVarChar, hash(token))
      .input('PasswordHash', sql.NVarChar, passwordHash)
      .output('ErrorCode',   sql.NVarChar(50))
      .output('UserId',      sql.UniqueIdentifier)
      .output('Email',       sql.NVarChar(255))
      .execute('dbo.sp_RedeemInviteToken');
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: 'Invite link is invalid or has expired' });

    const email = (r.output.Email as string | null) ?? '';
    return res.json({ success: true, data: { email } });
  } catch (err) {
    console.error('[accept-invite]', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// ─── POST /auth/logout ────────────────────────────────────────────────────────
/** Return current user profile from the verified JWT — no DB call needed */
authRouter.get('/me', requireAuth, (req, res) => {
  const u = req.user!;
  res.json({
    success: true,
    data: {
      id:             u.sub,
      email:          u.email,
      globalRole:     u.globalRole,
      currentTeamId:  u.currentTeamId,
      teams:          u.teams,
      appPermissions: u.appPermissions,
    },
  });
});

authRouter.post('/logout', async (req, res) => {
  const refreshToken = req.body.refreshToken ?? req.cookies?.cfb_refresh_token;
  if (refreshToken) {
    try {
      const db = await getDb();
      await db.request().input('TokenHash', sql.NVarChar, hash(refreshToken)).execute('dbo.sp_Logout');
    } catch { /* best effort */ }
  }
  audit('LOGOUT', { ip: req.ip });
  return res
    .clearCookie('cfb_access_token',  { path: '/' })
    .clearCookie('cfb_refresh_token', { path: '/' })
    .json({ success: true, message: 'Logged out' });
});
