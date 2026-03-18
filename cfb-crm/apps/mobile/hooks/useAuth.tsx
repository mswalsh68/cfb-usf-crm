import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { useRouter, useSegments } from 'expo-router';
import { globalApi, TokenStore } from '../hooks/useApiClient';
import type { User, AppName, GlobalRole } from '@cfb-crm/types';

// ─── Types ────────────────────────────────────────────────────

interface AuthState {
  user:        User | null;
  isLoading:   boolean;
  isSignedIn:  boolean;
}

interface AuthContextValue extends AuthState {
  signIn:          (email: string, password: string) => Promise<void>;
  signOut:         () => Promise<void>;
  hasAppAccess:    (app: AppName) => boolean;
  getAppRole:      (app: AppName) => GlobalRole | null;
  canWrite:        (app: AppName) => boolean;
  isGlobalAdmin:   () => boolean;
  isAppAdmin:      (app: AppName) => boolean;
}

const AuthContext = createContext<AuthContextValue | null>(null);

// ─── Provider ─────────────────────────────────────────────────

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user,      setUser]      = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const router   = useRouter();
  const segments = useSegments();

  // On mount: check if we have a stored access token and try to restore session
  useEffect(() => {
    (async () => {
      try {
        const token = await TokenStore.getAccess();
        if (token) {
          const { data } = await globalApi.get('/auth/me');
          setUser(data.data);
        }
      } catch {
        await TokenStore.clear();
      } finally {
        setIsLoading(false);
      }
    })();
  }, []);

  // Route guard — redirect based on auth state
  useEffect(() => {
    if (isLoading) return;
    const inAuthGroup = segments[0] === '(auth)';
    if (!user && !inAuthGroup) {
      router.replace('/(auth)/login');
    } else if (user && inAuthGroup) {
      router.replace('/');
    }
  }, [user, segments, isLoading]);

  const signIn = useCallback(async (email: string, password: string) => {
    const { data } = await globalApi.post('/auth/login', { email, password });
    const { accessToken, refreshToken, user: userData } = data.data;
    await TokenStore.setTokens(accessToken, refreshToken);
    setUser(userData);
  }, []);

  const signOut = useCallback(async () => {
    try {
      const refreshToken = await TokenStore.getRefresh();
      await globalApi.post('/auth/logout', { refreshToken });
    } catch { /* best effort */ }
    await TokenStore.clear();
    setUser(null);
  }, []);

  // ─── Permission helpers ──────────────────────────────────
  const isGlobalAdmin = useCallback(() =>
    user?.globalRole === 'global_admin', [user]);

  const hasAppAccess = useCallback((app: AppName): boolean => {
    if (!user) return false;
    if (user.globalRole === 'global_admin') return true;
    return user.appPermissions.some((p) => p.app === app);
  }, [user]);

  const getAppRole = useCallback((app: AppName): GlobalRole | null => {
    if (!user) return null;
    if (user.globalRole === 'global_admin') return 'global_admin';
    return user.appPermissions.find((p) => p.app === app)?.role ?? null;
  }, [user]);

  const canWrite = useCallback((app: AppName): boolean => {
    const role = getAppRole(app);
    return ['global_admin', 'app_admin', 'coach_staff'].includes(role ?? '');
  }, [getAppRole]);

  const isAppAdmin = useCallback((app: AppName): boolean => {
    const role = getAppRole(app);
    return ['global_admin', 'app_admin'].includes(role ?? '');
  }, [getAppRole]);

  return (
    <AuthContext.Provider value={{
      user, isLoading, isSignedIn: !!user,
      signIn, signOut,
      hasAppAccess, getAppRole, canWrite, isGlobalAdmin, isAppAdmin,
    }}>
      {children}
    </AuthContext.Provider>
  );
}

// ─── Hook ─────────────────────────────────────────────────────

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
}
