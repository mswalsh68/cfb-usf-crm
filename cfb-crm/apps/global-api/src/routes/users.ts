import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { z } from 'zod';
import { requireAuth, requireGlobalAdmin } from '../middleware/auth';
import { getDb, sql } from '../db';

export const usersRouter      = Router();
export const permissionsRouter = Router();
usersRouter.use(requireAuth);
permissionsRouter.use(requireAuth);

const sha256 = (t: string) => crypto.createHash('sha256').update(t).digest('hex');

// GET /users — sp_GetUsers handles filtering, pagination, counts
usersRouter.get('/', requireGlobalAdmin, async (req, res) => {
  const { search, role, page = '1', pageSize = '50' } = req.query as Record<string, string>;
  try {
    const db = await getDb();
    const r = await db.request()
      .input('Search',     sql.NVarChar, search    || null)
      .input('GlobalRole', sql.NVarChar, role      || null)
      .input('Page',       sql.Int,      Math.max(parseInt(page) || 1, 1))
      .input('PageSize',   sql.Int,      Math.min(Math.max(parseInt(pageSize) || 50, 1), 200))
      .output('TotalCount', sql.Int)
      .execute('dbo.sp_GetUsers');
    return res.json({ success: true, data: r.recordset, total: r.output.TotalCount, page: parseInt(page), pageSize: parseInt(pageSize) });
  } catch (err) { console.error('[GET /users]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /users — password is optional; if omitted an invite token is generated.
// Returns { user: { id }, inviteToken } — the frontend builds the invite URL.
const createSchema = z.object({
  email:        z.string().email(),
  firstName:    z.string().min(1),
  lastName:     z.string().min(1),
  globalRole:   z.enum(['global_admin','app_admin','coach_staff','player','readonly']),
  grantAppName: z.enum(['roster','alumni','global-admin']).optional(),
  grantAppRole: z.enum(['global_admin','app_admin','coach_staff','player','readonly']).optional(),
});
usersRouter.post('/', requireGlobalAdmin, async (req, res) => {
  const p = createSchema.safeParse(req.body);
  if (!p.success) return res.status(400).json({ success: false, error: p.error.flatten() });
  const { email, firstName, lastName, globalRole, grantAppName, grantAppRole } = p.data;
  try {
    const db = await getDb();
    // Use a random placeholder hash — real password set when invite is redeemed
    const placeholderHash = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), 12);
    const r = await db.request()
      .input('Email',        sql.NVarChar,         email.trim().toLowerCase())
      .input('PasswordHash', sql.NVarChar,         placeholderHash)
      .input('FirstName',    sql.NVarChar,         firstName.trim())
      .input('LastName',     sql.NVarChar,         lastName.trim())
      .input('GlobalRole',   sql.NVarChar,         globalRole)
      .input('CreatedBy',    sql.UniqueIdentifier, req.user!.sub)
      .input('GrantAppName', sql.NVarChar,         grantAppName || null)
      .input('GrantAppRole', sql.NVarChar,         grantAppRole || null)
      .output('NewUserId',   sql.UniqueIdentifier)
      .output('ErrorCode',   sql.NVarChar(50))
      .execute('dbo.sp_CreateUser');
    if (r.output.ErrorCode === 'EMAIL_ALREADY_EXISTS') {
      // User already exists — fetch their ID and issue a fresh invite so the
      // caller can still get a valid invite link (idempotent create).
      const existing = await db.request()
        .input('Search',     sql.NVarChar, email.trim().toLowerCase())
        .input('GlobalRole', sql.NVarChar, null)
        .input('Page',       sql.Int,      1)
        .input('PageSize',   sql.Int,      1)
        .output('TotalCount', sql.Int)
        .execute('dbo.sp_GetUsers');
      const existingUser = existing.recordset?.[0];
      if (!existingUser) return res.status(409).json({ success: false, error: 'Email already in use' });
      const rawToken  = crypto.randomBytes(32).toString('hex');
      const tokenHash = sha256(rawToken);
      const expiresAt = new Date(Date.now() + 72 * 60 * 60 * 1000);
      await db.request()
        .input('UserId',    sql.UniqueIdentifier, existingUser.id)
        .input('TokenHash', sql.NVarChar,         tokenHash)
        .input('ExpiresAt', sql.DateTime2,        expiresAt)
        .execute('dbo.sp_CreateInviteToken');
      return res.status(200).json({ success: true, data: { id: existingUser.id, inviteToken: rawToken }, alreadyExisted: true });
    }
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });

    const newUserId = r.output.NewUserId;

    // Generate invite token (72-hour expiry)
    const rawToken  = crypto.randomBytes(32).toString('hex');
    const tokenHash = sha256(rawToken);
    const expiresAt = new Date(Date.now() + 72 * 60 * 60 * 1000);
    await db.request()
      .input('UserId',    sql.UniqueIdentifier, newUserId)
      .input('TokenHash', sql.NVarChar,         tokenHash)
      .input('ExpiresAt', sql.DateTime2,        expiresAt)
      .execute('dbo.sp_CreateInviteToken');

    return res.status(201).json({ success: true, data: { id: newUserId, inviteToken: rawToken } });
  } catch (err) { console.error('[POST /users]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// PATCH /users/:id — sp_UpdateUser handles validation + audit
usersRouter.patch('/:id', requireGlobalAdmin, async (req, res) => {
  const { globalRole, isActive } = req.body;
  try {
    const db = await getDb();
    const r = await db.request()
      .input('TargetUserId', sql.UniqueIdentifier, req.params.id)
      .input('GlobalRole',   sql.NVarChar,         globalRole ?? null)
      .input('IsActive',     sql.Bit,              isActive   ?? null)
      .input('ActorId',      sql.UniqueIdentifier, req.user!.sub)
      .output('ErrorCode',   sql.NVarChar(50))
      .execute('dbo.sp_UpdateUser');
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.json({ success: true, message: 'User updated' });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// GET /permissions/:userId — sp_GetUserPermissions
permissionsRouter.get('/:userId', requireGlobalAdmin, async (req, res) => {
  try {
    const db = await getDb();
    const r = await db.request()
      .input('UserId', sql.UniqueIdentifier, req.params.userId)
      .execute('dbo.sp_GetUserPermissions');
    return res.json({ success: true, data: r.recordset });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /permissions — sp_GrantPermission handles upsert + audit
permissionsRouter.post('/', requireGlobalAdmin, async (req, res) => {
  const { userId, appName, role } = req.body;
  if (!userId || !appName || !role) return res.status(400).json({ success: false, error: 'userId, appName, and role are required' });
  try {
    const db = await getDb();
    const r = await db.request()
      .input('UserId',    sql.UniqueIdentifier, userId)
      .input('AppName',   sql.NVarChar,         appName)
      .input('Role',      sql.NVarChar,         role)
      .input('GrantedBy', sql.UniqueIdentifier, req.user!.sub)
      .output('ErrorCode', sql.NVarChar(50))
      .execute('dbo.sp_GrantPermission');
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.status(201).json({ success: true, message: 'Permission granted' });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});

// DELETE /permissions/:userId/:appName — sp_RevokePermission
permissionsRouter.delete('/:userId/:appName', requireGlobalAdmin, async (req, res) => {
  try {
    const db = await getDb();
    const r = await db.request()
      .input('UserId',    sql.UniqueIdentifier, req.params.userId)
      .input('AppName',   sql.NVarChar,         req.params.appName)
      .input('RevokedBy', sql.UniqueIdentifier, req.user!.sub)
      .output('ErrorCode', sql.NVarChar(50))
      .execute('dbo.sp_RevokePermission');
    if (r.output.ErrorCode === 'PERMISSION_NOT_FOUND') return res.status(404).json({ success: false, error: 'Permission not found' });
    return res.json({ success: true, message: 'Permission revoked' });
  } catch (err) { return res.status(500).json({ success: false, error: 'Server error' }); }
});
