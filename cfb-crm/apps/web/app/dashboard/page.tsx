'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { isLoggedIn, getUser, hasAppAccess, isGlobalAdmin } from '@/lib/auth';
import { USF } from '@/lib/theme';
import { PageLayout } from '@/components';

export default function DashboardPage() {
  const router = useRouter();
  const [user, setUser] = useState<any>(null);

  useEffect(() => {
    if (!isLoggedIn()) { router.push('/'); return; }
    setUser(getUser());
  }, []);

  if (!user) return null;

  return (
    <PageLayout>
      <h1 style={{ fontSize: 24, fontWeight: 700, color: USF.gray900, margin: 0 }}>
        Welcome back, {user.firstName ?? user.email}
      </h1>
      <p style={{ fontSize: 14, color: USF.gray500, marginTop: 4, marginBottom: 32 }}>
        {user.globalRole === 'global_admin' ? 'Global Administrator' : user.globalRole}
      </p>

      {/* Module cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: 24 }}>

        {(isGlobalAdmin() || hasAppAccess('roster')) && (
          <button
            onClick={() => router.push('/roster')}
            style={{ backgroundColor: USF.white, border: `1px solid ${USF.cardBorder}`, borderRadius: 16, padding: 24, textAlign: 'left', cursor: 'pointer', boxShadow: '0 1px 3px rgba(0,0,0,0.06)', transition: 'border-color 0.15s' }}
            onMouseEnter={e => (e.currentTarget.style.borderColor = USF.green)}
            onMouseLeave={e => (e.currentTarget.style.borderColor = USF.cardBorder)}
          >
            <div style={{ width: 48, height: 48, borderRadius: 12, backgroundColor: USF.greenLight, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24, marginBottom: 16 }}>🏈</div>
            <h2 style={{ fontSize: 17, fontWeight: 600, color: USF.gray900, margin: 0 }}>Roster CRM</h2>
            <p style={{ fontSize: 13, color: USF.gray500, marginTop: 6 }}>Manage current players, stats, and eligibility</p>
          </button>
        )}

        {(isGlobalAdmin() || hasAppAccess('alumni')) && (
          <button
            onClick={() => router.push('/alumni')}
            style={{ backgroundColor: USF.white, border: `1px solid ${USF.cardBorder}`, borderRadius: 16, padding: 24, textAlign: 'left', cursor: 'pointer', boxShadow: '0 1px 3px rgba(0,0,0,0.06)', transition: 'border-color 0.15s' }}
            onMouseEnter={e => (e.currentTarget.style.borderColor = USF.evergreen)}
            onMouseLeave={e => (e.currentTarget.style.borderColor = USF.cardBorder)}
          >
            <div style={{ width: 48, height: 48, borderRadius: 12, backgroundColor: USF.sand, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24, marginBottom: 16 }}>🎓</div>
            <h2 style={{ fontSize: 17, fontWeight: 600, color: USF.gray900, margin: 0 }}>Alumni CRM</h2>
            <p style={{ fontSize: 13, color: USF.gray500, marginTop: 6 }}>Track alumni, manage outreach and engagement</p>
          </button>
        )}

        {isGlobalAdmin() && (
          <button
            onClick={() => router.push('/admin')}
            style={{ backgroundColor: USF.white, border: `1px solid ${USF.cardBorder}`, borderRadius: 16, padding: 24, textAlign: 'left', cursor: 'pointer', boxShadow: '0 1px 3px rgba(0,0,0,0.06)', transition: 'border-color 0.15s' }}
            onMouseEnter={e => (e.currentTarget.style.borderColor = USF.green)}
            onMouseLeave={e => (e.currentTarget.style.borderColor = USF.cardBorder)}
          >
            <div style={{ width: 48, height: 48, borderRadius: 12, backgroundColor: USF.greenLight, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24, marginBottom: 16 }}>⚙️</div>
            <h2 style={{ fontSize: 17, fontWeight: 600, color: USF.gray900, margin: 0 }}>Global Admin</h2>
            <p style={{ fontSize: 13, color: USF.gray500, marginTop: 6 }}>Manage users, roles, and permissions</p>
          </button>
        )}

      </div>
    </PageLayout>
  );
}