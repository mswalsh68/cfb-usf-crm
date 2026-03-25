import axios from 'axios';

const GLOBAL_API  = process.env.NEXT_PUBLIC_GLOBAL_API_URL  ?? 'http://localhost:3001';
const ROSTER_API  = process.env.NEXT_PUBLIC_ROSTER_API_URL  ?? 'http://localhost:3002';
const ALUMNI_API  = process.env.NEXT_PUBLIC_ALUMNI_API_URL  ?? 'http://localhost:3003';

let isRefreshing = false;
let refreshQueue: Array<(token: string) => void> = [];

async function tryRefresh(): Promise<string | null> {
  const refreshToken = typeof window !== 'undefined' ? localStorage.getItem('cfb_refresh_token') : null;
  if (!refreshToken) return null;
  try {
    const res = await axios.post(`${GLOBAL_API}/auth/refresh`, { refreshToken });
    const { accessToken, refreshToken: newRefresh } = res.data.data;
    localStorage.setItem('cfb_access_token', accessToken);
    localStorage.setItem('cfb_refresh_token', newRefresh);
    return accessToken;
  } catch {
    return null;
  }
}

function createClient(baseURL: string) {
  const client = axios.create({ baseURL, headers: { 'Content-Type': 'application/json' } });

  client.interceptors.request.use((config) => {
    const token = typeof window !== 'undefined' ? localStorage.getItem('cfb_access_token') : null;
    if (token) config.headers.Authorization = `Bearer ${token}`;
    return config;
  });

  client.interceptors.response.use(
    (res) => res,
    async (error) => {
      const original = error.config;
      if (error.response?.status === 401 && !original._retry) {
        original._retry = true;
        if (isRefreshing) {
          return new Promise((resolve, reject) => {
            refreshQueue.push((token) => {
              original.headers.Authorization = `Bearer ${token}`;
              resolve(client(original));
            });
          });
        }
        isRefreshing = true;
        const newToken = await tryRefresh();
        isRefreshing = false;
        if (newToken) {
          refreshQueue.forEach((cb) => cb(newToken));
          refreshQueue = [];
          original.headers.Authorization = `Bearer ${newToken}`;
          return client(original);
        }
        refreshQueue = [];
        localStorage.removeItem('cfb_access_token');
        localStorage.removeItem('cfb_refresh_token');
        window.location.href = '/';
      }
      return Promise.reject(error);
    }
  );

  return client;
}

export const globalApi = createClient(GLOBAL_API);
export const rosterApi = createClient(ROSTER_API);
export const alumniApi = createClient(ALUMNI_API);