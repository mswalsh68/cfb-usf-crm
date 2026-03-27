'use client';

import { useEffect, useState } from 'react';
import { TeamConfigProvider, DEFAULT_CONFIG, TeamConfig } from '@/lib/teamConfig';

export type { TeamConfig };

const GLOBAL_API = process.env.NEXT_PUBLIC_GLOBAL_API_URL ?? 'http://localhost:3001';

// Exported so Nav can call it directly after a team switch
export function applyTheme(config: Partial<TeamConfig>) {
  if (typeof document === 'undefined') return;
  const root = document.documentElement;
  if (config.colorPrimary)      root.style.setProperty('--color-primary',       config.colorPrimary);
  if (config.colorPrimaryDark)  root.style.setProperty('--color-primary-dark',  config.colorPrimaryDark);
  if (config.colorPrimaryLight) root.style.setProperty('--color-primary-light', config.colorPrimaryLight);
  if (config.colorPrimary)      root.style.setProperty('--color-primary-hover', config.colorPrimary);
  if (config.colorAccent)       root.style.setProperty('--color-accent',        config.colorAccent);
  if (config.colorAccentDark)   root.style.setProperty('--color-accent-dark',   config.colorAccentDark);
  if (config.colorAccentLight)  root.style.setProperty('--color-accent-light',  config.colorAccentLight);
  if (config.colorPrimary)      root.style.setProperty('--color-success',       config.colorPrimary);
  if (config.colorPrimaryLight) root.style.setProperty('--color-success-light', config.colorPrimaryLight);
  if (config.colorPrimaryDark)  root.style.setProperty('--color-info',          config.colorPrimaryDark);
  if (config.colorPrimaryLight) root.style.setProperty('--color-info-light',    config.colorPrimaryLight);
}

// Dispatches a custom event that ThemeProvider listens for.
// Nav calls this after a successful team switch.
export function triggerThemeRefresh(newConfig: Partial<TeamConfig>) {
  if (typeof window === 'undefined') return;
  window.dispatchEvent(new CustomEvent('team-config-changed', { detail: newConfig }));
}

export default function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [config, setConfig] = useState<TeamConfig>(DEFAULT_CONFIG);

  useEffect(() => {
    // Apply env-var defaults immediately for fast paint
    applyTheme(DEFAULT_CONFIG);

    const CACHE_KEY = 'cfb_team_config';
    const CACHE_TTL = 5 * 60 * 1000; // 5 minutes

    const applyData = (data: Partial<TeamConfig>) => {
      const merged: TeamConfig = { ...DEFAULT_CONFIG, ...data };
      setConfig(merged);
      applyTheme(merged);
    };

    // Serve from sessionStorage if fresh
    try {
      const raw = sessionStorage.getItem(CACHE_KEY);
      if (raw) {
        const { data: cached, ts } = JSON.parse(raw) as { data: Partial<TeamConfig>; ts: number };
        if (Date.now() - ts < CACHE_TTL) {
          applyData(cached);
        }
      }
    } catch { /* ignore parse errors */ }

    // Fetch real config from global API (no auth required)
    fetch(`${GLOBAL_API}/config`, {
      headers: localStorage.getItem('cfb_access_token')
        ? { Authorization: `Bearer ${localStorage.getItem('cfb_access_token')}` }
        : {},
    })
      .then(r => r.json())
      .then(({ data }) => {
        if (data) {
          applyData(data);
          try { sessionStorage.setItem(CACHE_KEY, JSON.stringify({ data, ts: Date.now() })); } catch { /* quota exceeded */ }
        }
      })
      .catch(() => {
        // Fall back to defaults silently — API may not be running in dev
      });

    // Listen for team switches triggered by Nav — also bust the cache
    const handleTeamChange = (e: Event) => {
      const newConfig = (e as CustomEvent<Partial<TeamConfig>>).detail;
      try { sessionStorage.removeItem(CACHE_KEY); } catch { /* ignore */ }
      setConfig(prev => {
        const merged = { ...prev, ...newConfig };
        applyTheme(merged);
        return merged;
      });
    };

    window.addEventListener('team-config-changed', handleTeamChange);
    return () => window.removeEventListener('team-config-changed', handleTeamChange);
  }, []);

  return (
    <TeamConfigProvider value={config}>
      {children}
    </TeamConfigProvider>
  );
}
