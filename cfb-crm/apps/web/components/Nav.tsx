'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { clearTokens, getCurrentTeamId, getUserTeams, isGlobalAdmin, isPlatformOwner, switchTeam } from '@/lib/auth';
import { useTeamConfig } from '@/lib/teamConfig';
import { triggerThemeRefresh } from './ThemeProvider';
import type { TeamSummary } from '@cfb-crm/types';

interface NavProps {
  currentPage?: string;
}

export default function Nav({ currentPage }: NavProps) {
  const router = useRouter();
  const { teamName, teamAbbr, logoUrl } = useTeamConfig();

  // Client-only state (avoids hydration mismatch — reads from localStorage)
  const [teams,         setTeams]         = useState<TeamSummary[]>([]);
  const [currentTeamId, setCurrentTeamId] = useState<string | null>(null);
  const [isOwner,       setIsOwner]       = useState(false);
  const [isAdmin,       setIsAdmin]       = useState(false);
  const [switching,     setSwitching]     = useState(false);
  const [switchError,   setSwitchError]   = useState('');
  const [dropdownOpen,  setDropdownOpen]  = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setTeams(getUserTeams());
    setCurrentTeamId(getCurrentTeamId());
    setIsOwner(isPlatformOwner());
    setIsAdmin(isGlobalAdmin());
  }, []);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setDropdownOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  const handleLogout = () => {
    clearTokens();
    router.push('/');
  };

  const handleSwitch = async (teamId: string) => {
    if (teamId === currentTeamId || switching) return;
    setSwitching(true);
    setSwitchError('');
    setDropdownOpen(false);
    try {
      const newConfig = await switchTeam(teamId);
      if (!newConfig) {
        setSwitchError('Failed to switch team. Please try again.');
        return;
      }
      // Hard reload to /dashboard so all pages re-fetch with the new team context
      window.location.href = '/dashboard';
    } catch {
      setSwitchError('Failed to switch team. Please try again.');
    } finally {
      setSwitching(false);
    }
  };

  const showSwitcher = teams.length > 1 || isOwner;
  const currentTeamSummary = teams.find(t => t.teamId === currentTeamId);

  return (
    <>
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
        {/* Left: logo + breadcrumb + team switcher */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <button
            onClick={() => router.push('/dashboard')}
            style={{ display: 'flex', alignItems: 'center', gap: 10, background: 'none', border: 'none', cursor: 'pointer', padding: 0 }}
          >
            <div style={{
              width: 36, height: 36, borderRadius: 8,
              backgroundColor: 'var(--color-accent)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0, overflow: 'hidden',
            }}>
              {logoUrl ? (
                <img src={logoUrl} alt={teamAbbr} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              ) : (
                <span style={{ fontSize: 11, fontWeight: 700, color: 'var(--color-primary)' }}>{teamAbbr}</span>
              )}
            </div>
            <span style={{ fontSize: 16, fontWeight: 600, color: '#ffffff' }}>{teamName}</span>
          </button>

          {/* Team switcher dropdown */}
          {showSwitcher && (
            <div ref={dropdownRef} style={{ position: 'relative' }}>
              <button
                onClick={() => setDropdownOpen(v => !v)}
                disabled={switching}
                style={{
                  background: 'rgba(255,255,255,0.15)',
                  border: 'none',
                  borderRadius: 6,
                  color: '#fff',
                  fontSize: 13,
                  fontWeight: 500,
                  padding: '4px 10px',
                  cursor: switching ? 'wait' : 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 4,
                  transition: 'background 0.15s',
                }}
                onMouseEnter={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.25)')}
                onMouseLeave={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.15)')}
              >
                {switching ? '...' : '▾'}
              </button>

              {dropdownOpen && (
                <div style={{
                  position: 'absolute',
                  top: '110%',
                  left: 0,
                  minWidth: 260,
                  background: '#fff',
                  borderRadius: 10,
                  boxShadow: '0 8px 24px rgba(0,0,0,0.18)',
                  border: '1px solid #e5e7eb',
                  zIndex: 200,
                  overflow: 'hidden',
                }}>
                  <div style={{ padding: '8px 16px 6px', fontSize: 11, fontWeight: 700, color: '#9ca3af', letterSpacing: '0.5px', textTransform: 'uppercase' }}>
                    Switch Team
                  </div>

                  {teams.map(t => (
                    <button
                      key={t.teamId}
                      onClick={() => handleSwitch(t.teamId)}
                      style={{
                        width: '100%',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        padding: '10px 16px',
                        background: t.teamId === currentTeamId ? '#f0fdf4' : 'transparent',
                        border: 'none',
                        cursor: 'pointer',
                        textAlign: 'left',
                        fontSize: 14,
                        color: '#111827',
                        transition: 'background 0.1s',
                      }}
                      onMouseEnter={e => { if (t.teamId !== currentTeamId) e.currentTarget.style.background = '#f9fafb'; }}
                      onMouseLeave={e => { e.currentTarget.style.background = t.teamId === currentTeamId ? '#f0fdf4' : 'transparent'; }}
                    >
                      <span style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        {/* Colour swatch */}
                        <span style={{
                          width: 10, height: 10, borderRadius: '50%',
                          background: t.colorPrimary,
                          display: 'inline-block', flexShrink: 0,
                          border: '1px solid rgba(0,0,0,0.1)',
                        }} />
                        <span>
                          <strong style={{ display: 'block', fontSize: 14 }}>{t.abbr}</strong>
                          <span style={{ fontSize: 12, color: '#6b7280' }}>{t.name}</span>
                        </span>
                      </span>
                      <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                        <span style={{ fontSize: 11, color: '#9ca3af' }}>{t.role}</span>
                        {t.teamId === currentTeamId && <span style={{ color: 'var(--color-primary)', fontSize: 16 }}>✓</span>}
                      </span>
                    </button>
                  ))}

                  {isOwner && (
                    <>
                      <div style={{ height: 1, background: '#e5e7eb', margin: '4px 0' }} />
                      <button
                        onClick={() => { setDropdownOpen(false); router.push('/platform-admin'); }}
                        style={{
                          width: '100%',
                          padding: '10px 16px',
                          background: 'transparent',
                          border: 'none',
                          cursor: 'pointer',
                          textAlign: 'left',
                          fontSize: 13,
                          color: '#6366f1',
                          fontWeight: 600,
                        }}
                        onMouseEnter={e => (e.currentTarget.style.background = '#eef2ff')}
                        onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
                      >
                        ⚙ Platform Admin
                      </button>
                    </>
                  )}
                </div>
              )}
            </div>
          )}

          {currentPage && (
            <>
              <span style={{ color: 'rgba(255,255,255,0.35)', fontSize: 18 }}>/</span>
              <span style={{ fontSize: 15, fontWeight: 500, color: 'rgba(255,255,255,0.85)' }}>
                {currentPage}
              </span>
            </>
          )}
        </div>

        {/* Center: primary nav links */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          {[
            { label: 'Feed',    href: '/feed'      },
            { label: 'Roster',  href: '/roster'    },
            { label: 'Alumni',  href: '/alumni'    },
          ].map(link => (
            <button
              key={link.href}
              onClick={() => router.push(link.href)}
              style={{
                background:   'rgba(255,255,255,0.1)',
                border:       'none',
                borderRadius: 6,
                color:        'rgba(255,255,255,0.85)',
                fontSize:     13,
                fontWeight:   500,
                padding:      '5px 14px',
                cursor:       'pointer',
                transition:   'background 0.15s',
              }}
              onMouseEnter={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.2)')}
              onMouseLeave={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.1)')}
            >
              {link.label}
            </button>
          ))}
        </div>

        {/* Right: admin link + error + sign out */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          {switchError && (
            <span style={{ fontSize: 12, color: '#fca5a5' }}>{switchError}</span>
          )}
          {isAdmin && !isOwner && (
            <button
              onClick={() => router.push('/admin')}
              style={{
                backgroundColor: 'rgba(255,255,255,0.12)',
                color:           'rgba(255,255,255,0.8)',
                border:          '1px solid rgba(255,255,255,0.2)',
                borderRadius:    8,
                padding:         '5px 14px',
                fontSize:        12,
                fontWeight:      600,
                cursor:          'pointer',
                letterSpacing:   '0.3px',
                transition:      'background-color 0.15s',
              }}
              onMouseEnter={e => (e.currentTarget.style.backgroundColor = 'rgba(255,255,255,0.22)')}
              onMouseLeave={e => (e.currentTarget.style.backgroundColor = 'rgba(255,255,255,0.12)')}
            >
              Admin
            </button>
          )}
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
        </div>
      </nav>

      {/* Platform owner banner — shown when viewing a client team */}
      {isOwner && currentTeamSummary && (
        <div style={{
          backgroundColor: '#1e1b4b',
          color:           '#c7d2fe',
          padding:         '6px 24px',
          fontSize:        12,
          fontWeight:      500,
          display:         'flex',
          alignItems:      'center',
          justifyContent:  'space-between',
        }}>
          <span>👁 Platform Owner Mode — viewing as <strong style={{ color: '#a5b4fc' }}>{currentTeamSummary.name}</strong></span>
          <button
            onClick={() => router.push('/platform-admin')}
            style={{
              background:   'rgba(165,180,252,0.15)',
              border:       '1px solid rgba(165,180,252,0.3)',
              borderRadius: 6,
              color:        '#a5b4fc',
              fontSize:     11,
              fontWeight:   600,
              padding:      '3px 10px',
              cursor:       'pointer',
            }}
          >
            Return to Platform Admin
          </button>
        </div>
      )}
    </>
  );
}
