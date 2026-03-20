'use client';

import React, { createContext, useContext, ReactNode } from 'react';

export interface AcademicYear {
  value: string;
  label: string;
}

export interface TeamConfig {
  // Identity
  teamName:  string;
  teamAbbr:  string;
  logoUrl?:  string;
  sport:     string;
  level:     string; // 'college' | 'high_school' | 'club'

  // Colors
  colorPrimary:      string;
  colorPrimaryDark:  string;
  colorPrimaryLight: string;
  colorAccent:       string;
  colorAccentDark:   string;
  colorAccentLight:  string;

  // Dynamic sport-agnostic lists
  positions:     string[];
  academicYears: AcademicYear[];

  // Configurable terminology
  alumniLabel: string;
  rosterLabel: string;
  classLabel:  string;
}

export const DEFAULT_CONFIG: TeamConfig = {
  teamName:          process.env.NEXT_PUBLIC_TEAM_NAME         ?? 'Team Portal',
  teamAbbr:          process.env.NEXT_PUBLIC_TEAM_ABBR         ?? 'TEAM',
  sport:             'football',
  level:             'college',
  colorPrimary:      process.env.NEXT_PUBLIC_COLOR_PRIMARY       ?? '#006747',
  colorPrimaryDark:  process.env.NEXT_PUBLIC_COLOR_PRIMARY_DARK  ?? '#005432',
  colorPrimaryLight: process.env.NEXT_PUBLIC_COLOR_PRIMARY_LIGHT ?? '#E0F0EA',
  colorAccent:       process.env.NEXT_PUBLIC_COLOR_ACCENT        ?? '#CFC493',
  colorAccentDark:   process.env.NEXT_PUBLIC_COLOR_ACCENT_DARK   ?? '#A89C6A',
  colorAccentLight:  process.env.NEXT_PUBLIC_COLOR_ACCENT_LIGHT  ?? '#EDEBD1',
  positions:     ['QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH'],
  academicYears: [
    { value: 'freshman',  label: 'Freshman'  },
    { value: 'sophomore', label: 'Sophomore' },
    { value: 'junior',    label: 'Junior'    },
    { value: 'senior',    label: 'Senior'    },
    { value: 'graduate',  label: 'Graduate'  },
  ],
  alumniLabel: 'Alumni',
  rosterLabel: 'Roster',
  classLabel:  'Recruiting Class',
};

const TeamConfigContext = createContext<TeamConfig>(DEFAULT_CONFIG);

export function useTeamConfig(): TeamConfig {
  return useContext(TeamConfigContext);
}

export function TeamConfigProvider({ children, value }: { children: ReactNode; value: TeamConfig }) {
  return (
    <TeamConfigContext.Provider value={value}>
      {children}
    </TeamConfigContext.Provider>
  );
}
