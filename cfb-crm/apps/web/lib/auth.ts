import type { TeamSummary, AppPermission } from '@cfb-crm/types';
import type { TeamConfig } from './teamConfig';

const GLOBAL_API = process.env.NEXT_PUBLIC_GLOBAL_API_URL ?? 'http://localhost:3001';

// ─── User info storage ────────────────────────────────────────────────────────
// Auth tokens are stored in httpOnly cookies by the server (not readable by JS).
// We store only the decoded user profile here for UI/routing use.

export function getUser() {
  if (typeof window === 'undefined') return null;
  try {
    const raw = localStorage.getItem('cfb_user');
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function storeUserFromToken(accessToken: string) {
  try {
    const base64url = accessToken.split('.')[1];
    const base64    = base64url.replace(/-/g, '+').replace(/_/g, '/');
    const padded    = base64.padEnd(base64.length + (4 - (base64.length % 4)) % 4, '=');
    localStorage.setItem('cfb_user', JSON.stringify(JSON.parse(atob(padded))));
  } catch { /* ignore */ }
}

export function setTokens(accessToken: string, _refreshToken: string) {
  storeUserFromToken(accessToken);
}

export function setAccessToken(accessToken: string) {
  storeUserFromToken(accessToken);
}

export function clearTokens() {
  localStorage.removeItem('cfb_user');
}

// ─── Auth state ───────────────────────────────────────────────────────────────

export function isLoggedIn(): boolean {
  return getUser() !== null;
}

// ─── Role checks ──────────────────────────────────────────────────────────────

export function hasAppAccess(app: string): boolean {
  const user = getUser();
  if (!user) return false;
  if (user.globalRole === 'platform_owner') return true;
  if (user.globalRole === 'global_admin') return true;
  return user.appPermissions?.some((p: AppPermission) => p.app === app) ?? false;
}

export function isGlobalAdmin(): boolean {
  const user = getUser();
  return user?.globalRole === 'global_admin' || user?.globalRole === 'platform_owner';
}

export function isPlatformOwner(): boolean {
  const user = getUser();
  return user?.globalRole === 'platform_owner';
}

// ─── Multi-team helpers ───────────────────────────────────────────────────────

export function getCurrentTeamId(): string | null {
  const user = getUser();
  return user?.currentTeamId ?? null;
}

export function getUserTeams(): TeamSummary[] {
  const user = getUser();
  return user?.teams ?? [];
}

export function hasTeamAccess(teamId: string): boolean {
  const user = getUser();
  if (!user) return false;
  if (user.globalRole === 'platform_owner') return true;
  return (user.teams ?? []).some((t: TeamSummary) => t.teamId === teamId);
}

// ─── Team switching ───────────────────────────────────────────────────────────

/**
 * Calls POST /auth/switch-team, stores the new access token,
 * and returns the new team's config for ThemeProvider to apply.
 * Returns null on failure.
 */
export async function switchTeam(teamId: string): Promise<TeamConfig | null> {
  if (!isLoggedIn()) return null;
  try {
    const res = await fetch(`${GLOBAL_API}/auth/switch-team`, {
      method:      'POST',
      headers:     { 'Content-Type': 'application/json' },
      credentials: 'include',
      body:        JSON.stringify({ teamId }),
    });
    if (!res.ok) return null;
    const { data } = await res.json();
    if (!data?.accessToken) return null;
    setAccessToken(data.accessToken);
    return data.teamConfig ?? null;
  } catch {
    return null;
  }
}
