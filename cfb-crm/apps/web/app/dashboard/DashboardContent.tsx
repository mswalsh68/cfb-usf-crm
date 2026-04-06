'use client';

import  {useEffect} from 'react';
import {useRouter}  from 'next/navigation';
import { isLoggedIn, getUser, hasAppAccess, isGlobalAdmin } from '@/lib/auth';
import { theme } from '@/lib/theme';
import { PageLayout } from '@/components';


export default function DashboardContent() {
    const router = useRouter();
    const user = getUser();

  useEffect(() => {
    if (!isLoggedIn()) router.push('/');
  }, []);

  if (!user) return null;
  return (
    <>
      <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>
        Welcome back, {user.firstName ?? user.email}
      </h1>
      <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4, marginBottom: 32 }}>
        {user.globalRole === 'global_admin' ? 'Global Administrator' : user.globalRole}
      </p>

      {/* Module cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: 24 }}>

        {(isGlobalAdmin() || hasAppAccess('roster')) && (
          <button
            onClick={() => router.push('/roster')}
            style={{ backgroundColor: theme.white, border: `1px solid ${theme.cardBorder}`, borderRadius: 16, padding: 24, textAlign: 'left', cursor: 'pointer', boxShadow: '0 1px 3px rgba(0,0,0,0.06)', transition: 'border-color 0.15s' }}
            onMouseEnter={e => (e.currentTarget.style.borderColor = theme.primary)}
            onMouseLeave={e => (e.currentTarget.style.borderColor = theme.cardBorder)}
          >
            <div style={{ width: 48, height: 48, borderRadius: 12, backgroundColor: theme.primaryLight, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24, marginBottom: 16 }}>🏈</div>
            <h2 style={{ fontSize: 17, fontWeight: 600, color: theme.gray900, margin: 0 }}>Active Roster</h2>
            <p style={{ fontSize: 13, color: theme.gray500, marginTop: 6 }}>Manage current players</p>
          </button>
        )}

        {(isGlobalAdmin() || hasAppAccess('alumni')) && (
          <button
            onClick={() => router.push('/alumni')}
            style={{ backgroundColor: theme.white, border: `1px solid ${theme.cardBorder}`, borderRadius: 16, padding: 24, textAlign: 'left', cursor: 'pointer', boxShadow: '0 1px 3px rgba(0,0,0,0.06)', transition: 'border-color 0.15s' }}
            onMouseEnter={e => (e.currentTarget.style.borderColor = theme.primaryDark)}
            onMouseLeave={e => (e.currentTarget.style.borderColor = theme.cardBorder)}
          >
            <div style={{ width: 48, height: 48, borderRadius: 12, backgroundColor: theme.accentLight, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24, marginBottom: 16 }}>🎓</div>
            <h2 style={{ fontSize: 17, fontWeight: 600, color: theme.gray900, margin: 0 }}>Alumni</h2>
            <p style={{ fontSize: 13, color: theme.gray500, marginTop: 6 }}>Track alumni, manage outreach and engagement</p>
          </button>
        )}

        {isGlobalAdmin() && (
          <button
            onClick={() => router.push('/admin/settings')}
            style={{ backgroundColor: theme.white, border: `1px solid ${theme.cardBorder}`, borderRadius: 16, padding: 24, textAlign: 'left', cursor: 'pointer', boxShadow: '0 1px 3px rgba(0,0,0,0.06)', transition: 'border-color 0.15s' }}
            onMouseEnter={e => (e.currentTarget.style.borderColor = theme.accent)}
            onMouseLeave={e => (e.currentTarget.style.borderColor = theme.cardBorder)}
          >
            <div style={{ width: 48, height: 48, borderRadius: 12, backgroundColor: theme.accentLight, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24, marginBottom: 16 }}>⚙️</div>
            <h2 style={{ fontSize: 17, fontWeight: 600, color: theme.gray900, margin: 0 }}>Team Settings</h2>
            <p style={{ fontSize: 13, color: theme.gray500, marginTop: 6 }}>Branding, positions, labels, and sport config</p>
          </button>
        )}

      </div>
    </>
  )
}
