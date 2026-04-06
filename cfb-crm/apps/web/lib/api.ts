import axios from 'axios';
import { setAccessToken, clearTokens } from './auth';

const GLOBAL_API  = process.env.NEXT_PUBLIC_GLOBAL_API_URL  ?? 'http://localhost:3001';
const APP_API     = process.env.NEXT_PUBLIC_APP_API_URL     ?? 'http://localhost:3002';

async function tryRefresh(): Promise<boolean> {
  // Preserve the user's active team across token refresh
  let currentTeamId: string | null = null;
  try {
    const raw = typeof window !== 'undefined' ? localStorage.getItem('cfb_user') : null;
    if (raw) currentTeamId = JSON.parse(raw).currentTeamId ?? null;
  } catch { /* ignore */ }

  try {
    // Refresh token is in httpOnly cookie — no need to send it in the body.
    // Server sets new httpOnly cookies on success and returns the new access token
    // so we can update the local user profile.
    const res = await axios.post(
      `${GLOBAL_API}/auth/refresh`,
      { currentTeamId },
      { withCredentials: true },
    );
    const { accessToken } = res.data.data;
    if (accessToken) setAccessToken(accessToken);
    return true;
  } catch {
    return false;
  }
}

function createClient(baseURL: string) {
  const client = axios.create({
    baseURL,
    headers:         { 'Content-Type': 'application/json' },
    withCredentials: true,  // Send httpOnly auth cookies on every request
  });

  // Per-client refresh state — prevents thundering herd on concurrent 401s
  let isRefreshing = false;
  let refreshQueue: Array<() => void> = [];

  client.interceptors.response.use(
    (res) => res,
    async (error) => {
      const original = error.config;
      if (error.response?.status === 401 && !original._retry) {
        original._retry = true;
        if (isRefreshing) {
          return new Promise<void>((resolve) => {
            refreshQueue.push(resolve);
          }).then(() => client(original));
        }
        isRefreshing = true;
        const ok = await tryRefresh();
        isRefreshing = false;
        if (ok) {
          refreshQueue.forEach((cb) => cb());
          refreshQueue = [];
          return client(original);
        }
        refreshQueue = [];
        clearTokens();
        window.location.href = '/';
      }
      return Promise.reject(error);
    }
  );

  return client;
}

export const globalApi = createClient(GLOBAL_API);
export const appApi   = createClient(APP_API);

/** Extracts the API error message from an axios error, falling back to a default. */
export function getApiError(err: unknown, fallback: string): string {
  if (axios.isAxiosError(err)) {
    const msg = (err.response?.data as { error?: string } | undefined)?.error;
    if (msg) return msg;
  }
  return fallback;
}
