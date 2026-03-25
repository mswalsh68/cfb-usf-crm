import type { TeamSummary } from '@cfb-crm/types';

const GLOBAL_API = process.env.NEXT_PUBLIC_GLOBAL_API_URL ?? 'http://localhost:3001';

// ─── Token storage ────────────────────────────────────────────────────────────

export function getAccessToken(): string | null {
  if (typeof window === 'undefined') return null;
  return localStorage.getItem('cfb_access_token');
}

export function setTokens(accessToken: string, refreshToken: string) {
  localStorage.setItem('cfb_access_token', accessToken);
  localStorage.setItem('cfb_refresh_token', refreshToken);
  // 7-day persistent cookie — matches refresh token lifetime
  document.cookie = 'cfb_access_token=1; path=/; SameSite=Strict; Max-Age=604800';
}

export function setAccessToken(accessToken: string) {
  localStorage.setItem('cfb_access_token', accessToken);
}

export function clearTokens() {
  localStorage.removeItem('cfb_access_token');
  localStorage.removeItem('cfb_refresh_token');
  document.cookie = 'cfb_access_token=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Strict';
}

// ─── Token decode ─────────────────────────────────────────────────────────────

export function getUser() {
  const token = getAccessToken();
  if (!token) return null;
  try {
    // JWTs use base64url (- and _ instead of + and /). atob() needs standard base64.
    const base64url = token.split('.')[1];
    const base64    = base64url.replace(/-/g, '+').replace(/_/g, '/');
    const padded    = base64.padEnd(base64.length + (4 - (base64.length % 4)) % 4, '=');
    return JSON.parse(atob(padded));
  } catch {
    return null;
  }
}

// ─── Auth state ───────────────────────────────────────────────────────────────

export function isLoggedIn(): boolean {
  const user = getUser();
  if (!user) return false;
  if (user.exp < Date.now() / 1000) {
    clearTokens();
    return false;
  }
  return true;
}

// ─── Role checks ──────────────────────────────────────────────────────────────

export function hasAppAccess(app: string): boolean {
  const user = getUser();
  if (!user) return false;
  if (user.globalRole === 'platform_owner') return true;
  if (user.globalRole === 'global_admin') return true;
  return user.appPermissions?.some((p: any) => p.app === app) ?? false;
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
export async function switchTeam(teamId: string): Promise<any | null> {
  const token = getAccessToken();
  if (!token) return null;
  try {
    const res = await fetch(`${GLOBAL_API}/auth/switch-team`, {
      method:  'POST',
      headers: {
        'Content-Type':  'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify({ teamId }),
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
