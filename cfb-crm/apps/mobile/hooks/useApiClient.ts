import axios, { AxiosInstance, InternalAxiosRequestConfig } from 'axios';
import * as SecureStore from 'expo-secure-store';

// ─── Base URLs (set in .env) ─────────────────────────────────
const GLOBAL_API  = process.env.EXPO_PUBLIC_GLOBAL_API_URL  ?? 'http://localhost:3001';
const APP_API     = process.env.EXPO_PUBLIC_APP_API_URL     ?? 'http://localhost:3002';

const SECURE_KEYS = {
  accessToken:  'cfb_access_token',
  refreshToken: 'cfb_refresh_token',
};

// ─── Token Storage ────────────────────────────────────────────

export const TokenStore = {
  async getAccess():  Promise<string | null> { return SecureStore.getItemAsync(SECURE_KEYS.accessToken); },
  async getRefresh(): Promise<string | null> { return SecureStore.getItemAsync(SECURE_KEYS.refreshToken); },
  async setTokens(access: string, refresh: string): Promise<void> {
    await Promise.all([
      SecureStore.setItemAsync(SECURE_KEYS.accessToken,  access),
      SecureStore.setItemAsync(SECURE_KEYS.refreshToken, refresh),
    ]);
  },
  async clear(): Promise<void> {
    await Promise.all([
      SecureStore.deleteItemAsync(SECURE_KEYS.accessToken),
      SecureStore.deleteItemAsync(SECURE_KEYS.refreshToken),
    ]);
  },
};

// ─── Create authenticated Axios instance ─────────────────────

function createApiClient(baseURL: string): AxiosInstance {
  const client = axios.create({
    baseURL,
    timeout: 15000,
    headers: { 'Content-Type': 'application/json' },
  });

  // Inject access token on every request
  client.interceptors.request.use(async (config: InternalAxiosRequestConfig) => {
    const token = await TokenStore.getAccess();
    if (token) config.headers.Authorization = `Bearer ${token}`;
    return config;
  });

  // Auto-refresh on 401
  let isRefreshing = false;
  let failedQueue: Array<{ resolve: (v: string) => void; reject: (e: unknown) => void }> = [];

  const processQueue = (error: unknown, token: string | null = null) => {
    failedQueue.forEach((p) => error ? p.reject(error) : p.resolve(token!));
    failedQueue = [];
  };

  client.interceptors.response.use(
    (res) => res,
    async (error) => {
      const originalRequest = error.config;
      if (error.response?.status !== 401 || originalRequest._retry) return Promise.reject(error);

      if (isRefreshing) {
        return new Promise((resolve, reject) => {
          failedQueue.push({ resolve, reject });
        }).then((token) => {
          originalRequest.headers.Authorization = `Bearer ${token}`;
          return client(originalRequest);
        });
      }

      originalRequest._retry = true;
      isRefreshing = true;

      try {
        const refreshToken = await TokenStore.getRefresh();
        if (!refreshToken) throw new Error('No refresh token');

        const { data } = await axios.post(`${GLOBAL_API}/auth/refresh`, { refreshToken });
        const { accessToken, refreshToken: newRefresh } = data.data;

        await TokenStore.setTokens(accessToken, newRefresh);
        processQueue(null, accessToken);

        originalRequest.headers.Authorization = `Bearer ${accessToken}`;
        return client(originalRequest);
      } catch (err) {
        processQueue(err, null);
        await TokenStore.clear();
        // Redirect to login — handled by AuthContext listener
        return Promise.reject(err);
      } finally {
        isRefreshing = false;
      }
    }
  );

  return client;
}

export const globalApi = createApiClient(GLOBAL_API);
export const appApi   = createApiClient(APP_API);
