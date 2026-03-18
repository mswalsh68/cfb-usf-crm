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

// POST /auth/logout — sp_Logout revokes the token by hash
authRouter.post('/logout', async (req, res) => {
  const { refreshToken } = req.body;
  if (refreshToken) {
    try { const db = await getDb(); await db.request().input('TokenHash', sql.NVarChar, hash(refreshToken)).execute('dbo.sp_Logout'); }
    catch { /* best effort */ }
  }
  return res.json({ success: true, message: 'Logged out' });
});
