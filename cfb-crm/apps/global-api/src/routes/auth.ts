import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { signAccessToken, signRefreshToken, verifyRefreshToken } from '@cfb-crm/auth';
import { getDb, sql } from '../db';

export const authRouter = Router();
const hash = (t: string) => crypto.createHash('sha256').update(t).digest('hex');

// POST /auth/login — sp_Login handles all DB logic: fetch, active check, last_login, audit
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
    const ok = await bcrypt.compare(password, PasswordHash); // bcrypt stays in code
    if (!ok) return res.status(401).json({ success: false, error: 'Invalid credentials' });
    const user = JSON.parse(UserJson);
    const accessToken  = signAccessToken({ sub: UserId, email: user.email, globalRole: user.globalRole, appPermissions: user.appPermissions ?? [] });
    const refreshToken = signRefreshToken(UserId);
    await db.request()
      .input('UserId',    sql.UniqueIdentifier, UserId)
      .input('TokenHash', sql.NVarChar,         hash(refreshToken))
      .input('ExpiresAt', sql.DateTime2,        new Date(Date.now() + 7 * 24 * 60 * 60 * 1000))
      .input('DeviceInfo',sql.NVarChar,         req.headers['user-agent'] ?? null)
      .execute('dbo.sp_StoreRefreshToken');
    return res.json({ success: true, data: { accessToken, refreshToken, user } });
  } catch (err) { console.error('[Login]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /auth/refresh — sp_RefreshToken atomically rotates the token and returns fresh user payload
authRouter.post('/refresh', async (req, res) => {
  const { refreshToken } = req.body;
  if (!refreshToken) return res.status(400).json({ success: false, error: 'Refresh token required' });
  try { verifyRefreshToken(refreshToken); } catch { return res.status(401).json({ success: false, error: 'Invalid token' }); }
  try {
    const db          = await getDb();
    const newRefresh  = signRefreshToken(crypto.randomUUID());
    const expiresAt   = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    const r = await db.request()
      .input('OldTokenHash', sql.NVarChar,  hash(refreshToken))
      .input('NewTokenHash', sql.NVarChar,  hash(newRefresh))
      .input('NewExpiresAt', sql.DateTime2, expiresAt)
      .output('UserJson',    sql.NVarChar(sql.MAX))
      .output('ErrorCode',   sql.NVarChar(50))
      .execute('dbo.sp_RefreshToken');
    if (r.output.ErrorCode) return res.status(401).json({ success: false, error: 'Token invalid or expired' });
    const user        = JSON.parse(r.output.UserJson);
    const accessToken = signAccessToken({ sub: user.id, email: user.email, globalRole: user.globalRole, appPermissions: user.appPermissions ?? [] });
    return res.json({ success: true, data: { accessToken, refreshToken: newRefresh } });
  } catch (err) { console.error('[Refresh]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// GET /auth/invite/:token — validate invite token, return user info (public)
authRouter.get('/invite/:token', async (req, res) => {
  try {
    const db = await getDb();
    const r  = await db.request()
      .input('TokenHash', sql.NVarChar, hash(req.params.token))
      .execute('dbo.sp_ValidateInviteToken');
    if (!r.recordset.length) return res.status(404).json({ success: false, error: 'Invite link is invalid or has expired' });
    return res.json({ success: true, data: r.recordset[0] });
  } catch (err) { console.error('[GET /auth/invite]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /auth/accept-invite — redeem invite token, set password, return email so frontend can prefill login
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
      .execute('dbo.sp_RedeemInviteToken');
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: 'Invite link is invalid or has expired' });

    // Fetch the email so the frontend can prefill the login form
    const db2 = await getDb();
    const ur  = await db2.request()
      .input('UserId', sql.UniqueIdentifier, r.output.UserId)
      .query('SELECT email FROM dbo.users WHERE id = @UserId');
    const email = ur.recordset[0]?.email ?? '';
    return res.json({ success: true, data: { email } });
  } catch (err) { console.error('[accept-invite]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /auth/logout — sp_Logout revokes the token by hash
authRouter.post('/logout', async (req, res) => {
  const { refreshToken } = req.body;
  if (refreshToken) {
    try { const db = await getDb(); await db.request().input('TokenHash', sql.NVarChar, hash(refreshToken)).execute('dbo.sp_Logout'); }
    catch { /* best effort */ }
  }
  return res.json({ success: true, message: 'Logged out' });
});
