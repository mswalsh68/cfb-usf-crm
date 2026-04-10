import React, { createContext, useContext, ReactNode } from 'react';

export interface AcademicYearOption {
  value: string;
  label: string;
}

export interface TeamConfig {
  teamName:          string;
  teamAbbr:          string;
  sport:             string;
  level:             string; // 'college' | 'high_school' | 'club'
  positions:         string[];
  academicYears:     AcademicYearOption[];
  alumniLabel:       string;
  rosterLabel:       string;
  classLabel:        string;
}

export const DEFAULT_TEAM_CONFIG: TeamConfig = {
  teamName:      'Team',
  teamAbbr:      'TEAM',
  sport:         'football',
  level:         'college',
  positions:     ['QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH'],
  academicYears: [
    { value: 'freshman',          label: 'Freshman'          },
    { value: 'rs-freshman',       label: 'RS Freshman'       },
    { value: 'sophomore',         label: 'Sophomore'         },
    { value: 'rs-sophomore',      label: 'RS Sophomore'      },
    { value: 'junior',            label: 'Junior'            },
    { value: 'rs-junior',         label: 'RS Junior'         },
    { value: 'senior',            label: 'Senior'            },
    { value: 'rs-senior',         label: 'RS Senior'         },
    { value: 'graduate',          label: 'Graduate'          },
    { value: 'graduate-transfer', label: 'Graduate Transfer' },
  ],
  alumniLabel:   'Alumni',
  rosterLabel:   'Roster',
  classLabel:    'Recruiting Class',
};

const TeamConfigContext = createContext<TeamConfig>(DEFAULT_TEAM_CONFIG);

export function useTeamConfig(): TeamConfig {
  return useContext(TeamConfigContext);
}

export function TeamConfigProvider({
  children,
  value,
}: {
  children: ReactNode;
  value?: TeamConfig;
}) {
  return (
    <TeamConfigContext.Provider value={value ?? DEFAULT_TEAM_CONFIG}>
      {children}
    </TeamConfigContext.Provider>
  );
}
