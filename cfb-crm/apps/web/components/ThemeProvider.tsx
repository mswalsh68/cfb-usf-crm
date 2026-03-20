'use client';

import { useEffect } from 'react';

// ─── Team config shape ────────────────────────────────────────
// In production this comes from your Global DB (teams table).
// For now it reads from environment variables + falls back to USF defaults.

export interface TeamConfig {
  name:          string;   // "USF Bulls"
  abbr:          string;   // "USF"
  logoUrl?:      string;   // URL to team logo image
  primaryColor:  string;   // hex — main brand color
  primaryDark:   string;   // hex — darker shade
  primaryLight:  string;   // hex — light surface
  accentColor:   string;   // hex — secondary brand color
  accentDark:    string;   // hex — darker accent
  accentLight:   string;   // hex — light accent surface
}

// ─── Default: USF Bulls ───────────────────────────────────────
export const DEFAULT_TEAM: TeamConfig = {
  name:         process.env.NEXT_PUBLIC_TEAM_NAME  ?? 'USF Bulls',
  abbr:         process.env.NEXT_PUBLIC_TEAM_ABBR  ?? 'USF',
  logoUrl:      process.env.NEXT_PUBLIC_TEAM_LOGO  ?? undefined,
  primaryColor: process.env.NEXT_PUBLIC_COLOR_PRIMARY      ?? '#006747',
  primaryDark:  process.env.NEXT_PUBLIC_COLOR_PRIMARY_DARK ?? '#005432',
  primaryLight: process.env.NEXT_PUBLIC_COLOR_PRIMARY_LIGHT?? '#E0F0EA',
  accentColor:  process.env.NEXT_PUBLIC_COLOR_ACCENT       ?? '#CFC493',
  accentDark:   process.env.NEXT_PUBLIC_COLOR_ACCENT_DARK  ?? '#A89C6A',
  accentLight:  process.env.NEXT_PUBLIC_COLOR_ACCENT_LIGHT ?? '#EDEBD1',
};

// ─── Apply team config to CSS variables ───────────────────────
export function applyTheme(config: TeamConfig) {
  const root = document.documentElement;
  root.style.setProperty('--color-primary',       config.primaryColor);
  root.style.setProperty('--color-primary-dark',  config.primaryDark);
  root.style.setProperty('--color-primary-light', config.primaryLight);
  root.style.setProperty('--color-accent',        config.accentColor);
  root.style.setProperty('--color-accent-dark',   config.accentDark);
  root.style.setProperty('--color-accent-light',  config.accentLight);
  root.style.setProperty('--color-success',       config.primaryColor);
  root.style.setProperty('--color-success-light', config.primaryLight);
}

// ─── ThemeProvider component ──────────────────────────────────
// Wrap your root layout with this.
// In production: fetch team config from your API here.

interface ThemeProviderProps {
  children:    React.ReactNode;
  teamConfig?: TeamConfig;
}

export default function ThemeProvider({ children, teamConfig }: ThemeProviderProps) {
  const config = teamConfig ?? DEFAULT_TEAM;

  useEffect(() => {
    applyTheme(config);
  }, [config]);

  return <>{children}</>;
}