import jwt from 'jsonwebtoken';
import type { AuthTokenPayload, AppName, GlobalRole } from '@cfb-crm/types';

const ACCESS_TOKEN_EXPIRY = '15m';
const REFRESH_TOKEN_EXPIRY = '7d';

// ─── Token Generation ────────────────────────────────────────────────────────

export function signAccessToken(payload: Omit<AuthTokenPayload, 'iat' | 'exp'>): string {
  return jwt.sign(payload, process.env.JWT_ACCESS_SECRET!, {
    expiresIn: ACCESS_TOKEN_EXPIRY,
  });
}

export function signRefreshToken(userId: string): string {
  return jwt.sign({ sub: userId }, process.env.JWT_REFRESH_SECRET!, {
    expiresIn: REFRESH_TOKEN_EXPIRY,
  });
}

export function verifyAccessToken(token: string): AuthTokenPayload {
  return jwt.verify(token, process.env.JWT_ACCESS_SECRET!) as AuthTokenPayload;
}

export function verifyRefreshToken(token: string): { sub: string } {
  return jwt.verify(token, process.env.JWT_REFRESH_SECRET!) as { sub: string };
}

// ─── Permission Helpers ───────────────────────────────────────────────────────

export function hasAppAccess(payload: AuthTokenPayload, app: AppName): boolean {
  if (payload.globalRole === 'global_admin') return true;
  return payload.appPermissions.some((p) => p.app === app);
}

export function getAppRole(payload: AuthTokenPayload, app: AppName): GlobalRole | null {
  if (payload.globalRole === 'global_admin') return 'global_admin';
  const perm = payload.appPermissions.find((p) => p.app === app);
  return perm?.role ?? null;
}

export function canWrite(role: GlobalRole | null): boolean {
  if (!role) return false;
  return ['global_admin', 'app_admin', 'coach_staff'].includes(role);
}

export function isAdmin(role: GlobalRole | null): boolean {
  if (!role) return false;
  return ['global_admin', 'app_admin'].includes(role);
}

export function isGlobalAdmin(role: GlobalRole | null): boolean {
  return role === 'global_admin';
}

// ─── Token Extraction ─────────────────────────────────────────────────────────

export function extractBearerToken(authHeader?: string): string | null {
  if (!authHeader?.startsWith('Bearer ')) return null;
  return authHeader.slice(7);
}
