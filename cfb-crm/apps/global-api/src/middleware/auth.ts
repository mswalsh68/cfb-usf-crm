import type { Request, Response, NextFunction } from 'express';
import {
  verifyAccessToken,
  extractBearerToken,
  hasAppAccess,
  getAppRole,
  isAdmin,
  isGlobalAdmin,
} from '@cfb-crm/auth';
import type { AuthTokenPayload, AppName, GlobalRole } from '@cfb-crm/types';

// Extend Express Request to carry the decoded token
declare global {
  namespace Express {
    interface Request {
      user?: AuthTokenPayload;
    }
  }
}

// ─── Base Auth Middleware ────────────────────────────────────
// Validates JWT and attaches decoded payload to req.user
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

// ─── App Access Guard ────────────────────────────────────────
// Verifies the user has permission to access a specific app module
export function requireAppAccess(app: AppName) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) return res.status(401).json({ success: false, error: 'Not authenticated' });
    if (!hasAppAccess(req.user, app)) {
      return res.status(403).json({ success: false, error: `Access to ${app} not permitted` });
    }
    next();
  };
}

// ─── Role Guards ─────────────────────────────────────────────
export function requireGlobalAdmin(req: Request, res: Response, next: NextFunction) {
  if (!req.user || !isGlobalAdmin(req.user.globalRole)) {
    return res.status(403).json({ success: false, error: 'Global admin access required' });
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
    const canWrite = role && ['global_admin', 'app_admin', 'coach_staff'].includes(role);
    if (!canWrite) {
      return res.status(403).json({ success: false, error: 'Write access required' });
    }
    next();
  };
}
