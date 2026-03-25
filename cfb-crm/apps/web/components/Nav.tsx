'use client';

import { useRouter } from 'next/navigation';
import { clearTokens } from '@/lib/auth';
import { useTeamConfig } from '@/lib/teamConfig';

interface NavProps {
  currentPage?: string;
}

export default function Nav({ currentPage }: NavProps) {
  const router = useRouter();
  const { teamName, teamAbbr, logoUrl } = useTeamConfig();

  const handleLogout = () => {
    clearTokens();
    router.push('/');
  };

  return (
    <nav style={{
      backgroundColor: 'var(--color-primary)',
      padding:         '0 24px',
      height:          56,
      display:         'flex',
      alignItems:      'center',
      justifyContent:  'space-between',
      position:        'sticky',
      top:             0,
      zIndex:          100,
      boxShadow:       '0 1px 4px rgba(0,0,0,0.15)',
    }}>
      {/* Left: logo + breadcrumb */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <button
          onClick={() => router.push('/dashboard')}
          style={{ display: 'flex', alignItems: 'center', gap: 10, background: 'none', border: 'none', cursor: 'pointer', padding: 0 }}
        >
          {/* Team logo or abbr badge */}
          <div style={{
            width:           36,
            height:          36,
            borderRadius:    8,
            backgroundColor: 'var(--color-accent)',
            display:         'flex',
            alignItems:      'center',
            justifyContent:  'center',
            flexShrink:      0,
            overflow:        'hidden',
          }}>
            {logoUrl ? (
              <img src={logoUrl} alt={teamAbbr} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
            ) : (
              <span style={{ fontSize: 11, fontWeight: 700, color: 'var(--color-primary)' }}>
                {teamAbbr}
              </span>
            )}
          </div>
          <span style={{ fontSize: 16, fontWeight: 600, color: '#ffffff' }}>{teamName}</span>
        </button>

        {currentPage && (
          <>
            <span style={{ color: 'rgba(255,255,255,0.35)', fontSize: 18 }}>/</span>
            <span style={{ fontSize: 15, fontWeight: 500, color: 'rgba(255,255,255,0.85)' }}>
              {currentPage}
            </span>
          </>
        )}
      </div>

      {/* Right: sign out */}
      <button
        onClick={handleLogout}
        style={{
          backgroundColor: 'rgba(255,255,255,0.15)',
          color:           '#ffffff',
          border:          'none',
          borderRadius:    8,
          padding:         '6px 16px',
          fontSize:        13,
          fontWeight:      500,
          cursor:          'pointer',
          transition:      'background-color 0.15s',
        }}
        onMouseEnter={e => (e.currentTarget.style.backgroundColor = 'rgba(255,255,255,0.25)')}
        onMouseLeave={e => (e.currentTarget.style.backgroundColor = 'rgba(255,255,255,0.15)')}
      >
        Sign Out
      </button>
    </nav>
  );
}
