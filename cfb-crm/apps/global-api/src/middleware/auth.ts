import type { Request, Response, NextFunction } from 'express';
import {
  verifyAccessToken,
  extractBearerToken,
  hasAppAccess,
  getAppRole,
  isAdmin,
  isGlobalAdmin,
  isPlatformOwner,
} from '@cfb-crm/auth';
import type { AuthTokenPayload, AppName, GlobalRole } from '@cfb-crm/types';
import { getDb, sql } from '../db';

// Extend Express Request to carry the decoded token
declare global {
  namespace Express {
    interface Request {
      user?: AuthTokenPayload;
    }
  }
}

// ─── Base Auth Middleware ─────────────────────────────────────────────────────
export function requireAuth(req: Request, res: Response, next: NextFunction) {
  const token = extractBearerToken(req.headers.authorization);
  if (!token) {
    return res.status(401).json({ success: false, error: 'Authentication required' });
  }
  try {
    req.user = verifyAccessToken(token);
    next();
  } catch {
    return res.status(401).json({ success: false, error: 'Invalid or expired token' });
  }
}

// ─── Team Active Check ────────────────────────────────────────────────────────
// Ensures the user's current team hasn't been deactivated (subscription kill switch).
export function requireActiveTeam(req: Request, res: Response, next: NextFunction): void {
  if (!req.user) { res.status(401).json({ success: false, error: 'Not authenticated' }); return; }

  // platform_owner viewing platform admin — no currentTeamId required
  if (isPlatformOwner(req.user.globalRole) && !req.user.currentTeamId) {
    next(); return;
  }

  if (!req.user.currentTeamId) { next(); return; }

  getDb()
    .then(db =>
      db.request()
        .input('TeamId', sql.UniqueIdentifier, req.user!.currentTeamId)
        .query('SELECT is_active FROM dbo.teams WHERE id = @TeamId')
    )
    .then(result => {
      const row = result.recordset[0];
      if (!row || row.is_active === false || row.is_active === 0) {
        res.status(403).json({
          success: false,
          error: 'Your subscription is inactive. Please contact LegacyLink support at support@legacylinkhq.com',
        });
        return;
      }
      next();
    })
    .catch(() => next()); // fail open on DB error — don't block users on infra issues
}

// ─── App Access Guard ─────────────────────────────────────────────────────────
export function requireAppAccess(app: AppName) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) return res.status(401).json({ success: false, error: 'Not authenticated' });
    if (!hasAppAccess(req.user, app)) {
      return res.status(403).json({ success: false, error: `Access to ${app} not permitted` });
    }
    next();
  };
}

// ─── Role Guards ──────────────────────────────────────────────────────────────
export function requireGlobalAdmin(req: Request, res: Response, next: NextFunction) {
  if (!req.user || !isGlobalAdmin(req.user.globalRole)) {
    return res.status(403).json({ success: false, error: 'Global admin access required' });
  }
  next();
}

export function requirePlatformOwner(req: Request, res: Response, next: NextFunction) {
  if (!req.user || !isPlatformOwner(req.user.globalRole)) {
    return res.status(403).json({ success: false, error: 'Platform owner access required' });
  }
  next();
}

export function requireAdminInApp(app: AppName) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) return res.status(401).json({ success: false, error: 'Not authenticated' });
    const role = getAppRole(req.user, app);
    if (!isAdmin(role)) {
      return res.status(403).json({ success: false, error: 'Admin access required' });
    }
    next();
  };
}

export function requireWriteInApp(app: AppName) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) return res.status(401).json({ success: false, error: 'Not authenticated' });
    const role = getAppRole(req.user, app);
    const canWrite = role && ['platform_owner', 'global_admin', 'app_admin', 'coach_staff'].includes(role);
    if (!canWrite) {
      return res.status(403).json({ success: false, error: 'Write access required' });
    }
    next();
  };
}
