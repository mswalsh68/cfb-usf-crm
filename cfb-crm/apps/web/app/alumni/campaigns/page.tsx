'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { appApi } from '@/lib/api';
import { isGlobalAdmin } from '@/lib/auth';
import { theme } from '@/lib/theme';
import { Alert, Badge, Button, PageLayout } from '@/components';

interface Campaign {
  id:             string;
  name:           string;
  description:    string | null;
  targetAudience: string;
  status:         string;
  campaignType:   string;
  subjectLine:    string | null;
  scheduledAt:    string | null;
  completedAt:    string | null;
  createdAt:      string;
  totalQueued:    number;
  totalSent:      number;
  totalOpened:    number;
  openRatePct:    number;
}

const STATUS_BADGE: Record<string, 'green' | 'gold' | 'gray' | 'danger'> = {
  draft:     'gray',
  scheduled: 'gold',
  active:    'green',
  completed: 'green',
  cancelled: 'danger',
};

const AUDIENCE_LABEL: Record<string, string> = {
  all:          'All',
  players_only: 'Players',
  alumni_only:  'Alumni',
  byClass:      'By Class',
  byPosition:   'By Position',
  byGradYear:   'By Grad Year',
  custom:       'Custom',
};

export default function CampaignsPage() {
  const router    = useRouter();
  const [campaigns, setCampaigns] = useState<Campaign[]>([]);
  const [loading,   setLoading]   = useState(true);
  const [error,     setError]     = useState('');
  const [isAdmin,   setIsAdmin]   = useState(false);

  useEffect(() => { setIsAdmin(isGlobalAdmin()); }, []);

  useEffect(() => {
    const fetch = async () => {
      setLoading(true);
      try {
        const { data } = await appApi.get('/campaigns');
        setCampaigns(data.data ?? []);
      } catch {
        setError('Failed to load campaigns.');
      } finally {
        setLoading(false);
      }
    };
    fetch();
  }, []);

  return (
    <PageLayout currentPage="Campaigns">
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>Email Campaigns</h1>
          <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>{campaigns.length} campaigns</p>
        </div>
        {isAdmin && (
          <Button label="+ New Campaign" onClick={() => router.push('/alumni/campaigns/new')} />
        )}
      </div>

      {error && <Alert message={error} variant="error" onClose={() => setError('')} />}

      <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ backgroundColor: theme.gray50, borderBottom: `1px solid ${theme.gray200}` }}>
              {['Name', 'Audience', 'Status', 'Sent', 'Opened', 'Open Rate', 'Date', ''].map(h => (
                <th key={h} style={{ textAlign: 'left', padding: '12px 20px', fontSize: 11, fontWeight: 600, color: theme.gray500, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={8} style={{ textAlign: 'center', padding: 48, color: theme.gray400 }}>Loading...</td></tr>
            ) : campaigns.length === 0 ? (
              <tr><td colSpan={8} style={{ textAlign: 'center', padding: 48, color: theme.gray400 }}>No campaigns yet</td></tr>
            ) : campaigns.map((c, i) => (
              <tr
                key={c.id}
                style={{
                  borderBottom: i < campaigns.length - 1 ? `1px solid ${theme.gray100}` : 'none',
                  cursor: 'pointer',
                }}
                onClick={() => router.push(`/alumni/campaigns/${c.id}`)}
                onMouseEnter={e => { (e.currentTarget as HTMLElement).style.backgroundColor = theme.gray50; }}
                onMouseLeave={e => { (e.currentTarget as HTMLElement).style.backgroundColor = 'transparent'; }}
              >
                <td style={{ padding: '14px 20px' }}>
                  <div style={{ fontSize: 14, fontWeight: 600, color: theme.gray900 }}>{c.name}</div>
                  {c.subjectLine && <div style={{ fontSize: 12, color: theme.gray500, marginTop: 2 }}>{c.subjectLine}</div>}
                </td>
                <td style={{ padding: '14px 20px', fontSize: 13, color: theme.gray700 }}>
                  {AUDIENCE_LABEL[c.targetAudience] ?? c.targetAudience}
                </td>
                <td style={{ padding: '14px 20px' }}>
                  <Badge label={c.status} variant={STATUS_BADGE[c.status] ?? 'gray'} />
                </td>
                <td style={{ padding: '14px 20px', fontSize: 13, color: theme.gray700 }}>{c.totalSent ?? 0}</td>
                <td style={{ padding: '14px 20px', fontSize: 13, color: theme.gray700 }}>{c.totalOpened ?? 0}</td>
                <td style={{ padding: '14px 20px', fontSize: 13, color: theme.gray700 }}>
                  {c.openRatePct != null ? `${c.openRatePct}%` : '—'}
                </td>
                <td style={{ padding: '14px 20px', fontSize: 12, color: theme.gray400 }}>
                  {new Date(c.createdAt).toLocaleDateString()}
                </td>
                <td style={{ padding: '14px 20px', textAlign: 'right' }}>
                  <span style={{ fontSize: 13, color: theme.primary, fontWeight: 600 }}>View →</span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </PageLayout>
  );
}
