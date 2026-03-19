import axios from 'axios';

const GLOBAL_API  = process.env.NEXT_PUBLIC_GLOBAL_API_URL  ?? 'http://localhost:3001';
const ROSTER_API  = process.env.NEXT_PUBLIC_ROSTER_API_URL  ?? 'http://localhost:3002';
const ALUMNI_API  = process.env.NEXT_PUBLIC_ALUMNI_API_URL  ?? 'http://localhost:3003';

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
      if (error.response?.status === 401) {
        localStorage.removeItem('cfb_access_token');
        localStorage.removeItem('cfb_refresh_token');
        window.location.href = '/login';
      }
      return Promise.reject(error);
    }
  );

  return client;
}

export const globalApi = createClient(GLOBAL_API);
export const rosterApi = createClient(ROSTER_API);
export const alumniApi = createClient(ALUMNI_API);