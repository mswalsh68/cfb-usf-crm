import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { requireAuth, requireGlobalAdmin } from '../middleware/auth';
import { getDb, sql } from '../db';

export const usersRouter      = Router();
export const permissionsRouter = Router();
usersRouter.use(requireAuth);
permissionsRouter.use(requireAuth);

// GET /users — sp_GetUsers handles filtering, pagination, counts
usersRouter.get('/', requireGlobalAdmin, async (req, res) => {
  const { search, role, page = '1', pageSize = '50' } = req.query as Record<string, string>;
  try {
    const db = await getDb();
    const r = await db.request()
      .input('Search',     sql.NVarChar, search    || null)
      .input('GlobalRole', sql.NVarChar, role      || null)
      .input('Page',       sql.Int,      parseInt(page))
      .input('PageSize',   sql.Int,      Math.min(parseInt(pageSize) || 50, 200))
      .output('TotalCount', sql.Int)
      .execute('dbo.sp_GetUsers');
    return res.json({ success: true, data: r.recordset, total: r.output.TotalCount, page: parseInt(page), pageSize: parseInt(pageSize) });
  } catch (err) { console.error('[GET /users]', err); return res.status(500).json({ success: false, error: 'Server error' }); }
});

// POST /users — hash password in code, sp_CreateUser handles everything else
const createSchema = z.object({
  email: z.string().email(), password: z.string().min(10),
  firstName: z.string().min(1), lastName: z.string().min(1),
  globalRole: z.enum(['global_admin','app_admin','coach_staff','player','readonly']),
  grantAppName: z.enum(['roster','alumni','global-admin']).optional(),
  grantAppRole: z.enum(['global_admin','app_admin','coach_staff','player','readonly']).optional(),
});
usersRouter.post('/', requireGlobalAdmin, async (req, res) => {
  const p = createSchema.safeParse(req.body);
  if (!p.success) return res.status(400).json({ success: false, error: p.error.flatten() });
  const { email, password, firstName, lastName, globalRole, grantAppName, grantAppRole } = p.data;
  try {
    const db           = await getDb();
    const passwordHash = await bcrypt.hash(password, 12); // hashing stays in code
    const r = await db.request()
      .input('Email',        sql.NVarChar,         email)
      .input('PasswordHash', sql.NVarChar,         passwordHash)
      .input('FirstName',    sql.NVarChar,         firstName)
      .input('LastName',     sql.NVarChar,         lastName)
      .input('GlobalRole',   sql.NVarChar,         globalRole)
      .input('CreatedBy',    sql.UniqueIdentifier, req.user!.sub)
      .input('GrantAppName', sql.NVarChar,         grantAppName || null)
      .input('GrantAppRole', sql.NVarChar,         grantAppRole || null)
      .output('NewUserId',   sql.UniqueIdentifier)
      .output('ErrorCode',   sql.NVarChar(50))
      .execute('dbo.sp_CreateUser');
    if (r.output.ErrorCode === 'EMAIL_ALREADY_EXISTS') return res.status(409).json({ success: false, error: 'Email already in use' });
    if (r.output.ErrorCode) return res.status(400).json({ success: false, error: r.output.ErrorCode });
    return res.status(201).json({ success: true, data: { id: r.output.NewUserId } });
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
