'use client';

import { useEffect, useState } from 'react';
import { TeamConfigProvider, DEFAULT_CONFIG, TeamConfig } from '@/lib/teamConfig';

export type { TeamConfig };

const GLOBAL_API = process.env.NEXT_PUBLIC_GLOBAL_API_URL ?? 'http://localhost:3001';

function applyTheme(config: TeamConfig) {
  if (typeof document === 'undefined') return;
  const root = document.documentElement;
  root.style.setProperty('--color-primary',       config.colorPrimary);
  root.style.setProperty('--color-primary-dark',  config.colorPrimaryDark);
  root.style.setProperty('--color-primary-light', config.colorPrimaryLight);
  root.style.setProperty('--color-primary-hover', config.colorPrimary);
  root.style.setProperty('--color-accent',        config.colorAccent);
  root.style.setProperty('--color-accent-dark',   config.colorAccentDark);
  root.style.setProperty('--color-accent-light',  config.colorAccentLight);
  root.style.setProperty('--color-success',       config.colorPrimary);
  root.style.setProperty('--color-success-light', config.colorPrimaryLight);
  root.style.setProperty('--color-info',          config.colorPrimaryDark);
  root.style.setProperty('--color-info-light',    config.colorPrimaryLight);
}

export default function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [config, setConfig] = useState<TeamConfig>(DEFAULT_CONFIG);

  useEffect(() => {
    // Apply env-var defaults immediately for fast paint
    applyTheme(DEFAULT_CONFIG);

    // Fetch real config from global API (no auth required)
    fetch(`${GLOBAL_API}/config`)
      .then(r => r.json())
      .then(({ data }) => {
        if (data) {
          const merged: TeamConfig = { ...DEFAULT_CONFIG, ...data };
          setConfig(merged);
          applyTheme(merged);
        }
      })
      .catch(() => {
        // Fall back to defaults silently — API may not be running in dev
      });
  }, []);

  return (
    <TeamConfigProvider value={config}>
      {children}
    </TeamConfigProvider>
  );
}
