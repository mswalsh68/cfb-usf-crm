export function getAccessToken(): string | null {
  if (typeof window === 'undefined') return null;
  return localStorage.getItem('cfb_access_token');
}

export function setTokens(accessToken: string, refreshToken: string) {
  localStorage.setItem('cfb_access_token', accessToken);
  localStorage.setItem('cfb_refresh_token', refreshToken);
}

export function clearTokens() {
  localStorage.removeItem('cfb_access_token');
  localStorage.removeItem('cfb_refresh_token');
}

export function getUser() {
  const token = getAccessToken();
  if (!token) return null;
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return payload;
  } catch {
    return null;
  }
}

export function isLoggedIn(): boolean {
  const user = getUser();
  if (!user) return false;
  if (user.exp < Date.now() / 1000) {
    clearTokens();
    return false;
  }
  return true;
}

export function hasAppAccess(app: string): boolean {
  const user = getUser();
  if (!user) return false;
  if (user.globalRole === 'global_admin') return true;
  return user.appPermissions?.some((p: any) => p.app === app) ?? false;
}

export function isGlobalAdmin(): boolean {
  const user = getUser();
  return user?.globalRole === 'global_admin';
}