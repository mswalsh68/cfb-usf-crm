'use client';

import React, { useEffect, useState } from 'react';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import { appApi } from '@/lib/api';
import { isGlobalAdmin } from '@/lib/auth';
import { theme } from '@/lib/theme';
import { Alert, Badge, Button, PageLayout } from '@/components';

interface CampaignDetail {
  id:             string;
  name:           string;
  description:    string | null;
  targetAudience: string;
  audienceFilters: string | null;
  status:         string;
  campaignType:   string;
  subjectLine:    string | null;
  scheduledAt:    string | null;
  startedAt:      string | null;
  completedAt:    string | null;
  createdAt:      string;
  totalQueued:    number;
  totalSent:      number;
  totalOpened:    number;
  unsubscribeCount: number;
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

export default function CampaignDetailPage() {
  const { id }        = useParams<{ id: string }>();
  const router        = useRouter();
  const searchParams  = useSearchParams();
  const [campaign,   setCampaign]   = useState<CampaignDetail | null>(null);
  const [loading,    setLoading]    = useState(true);
  const [error,      setError]      = useState('');
  const [actionMsg,  setActionMsg]  = useState('');
  const [dispatching,setDispatching]= useState(false);
  const [cancelling, setCancelling] = useState(false);
  const [isAdmin,    setIsAdmin]    = useState(false);

  useEffect(() => { setIsAdmin(isGlobalAdmin()); }, []);
  useEffect(() => {
    if (searchParams.get('dispatchError')) setError('Campaign saved but email dispatch failed. Retry below.');
  }, [searchParams]);

  const load = async () => {
    setLoading(true);
    try {
      const { data } = await appApi.get(`/campaigns/${id}`);
      if (!data.success) { setError('Campaign not found.'); return; }
      setCampaign(data.data);
    } catch {
      setError('Failed to load campaign.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, [id]);

  const handleDispatch = async () => {
    if (!confirm('Send this campaign to all eligible recipients now?')) return;
    setDispatching(true);
    setError('');
    try {
      const { data } = await appApi.post(`/campaigns/${id}/dispatch`);
      if (!data.success) throw new Error(data.error);
      setActionMsg('Campaign dispatched successfully.');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Dispatch failed');
    } finally {
      setDispatching(false);
    }
  };

  const handleCancel = async () => {
    if (!confirm('Cancel this campaign? This cannot be undone.')) return;
    setCancelling(true);
    setError('');
    try {
      await appApi.post(`/campaigns/${id}/cancel`);
      setActionMsg('Campaign cancelled.');
      load();
    } catch {
      setError('Failed to cancel campaign.');
    } finally {
      setCancelling(false);
    }
  };

  if (loading) {
    return <PageLayout currentPage="Campaign"><div style={{ padding: 60, textAlign: 'center', color: theme.gray400 }}>Loading...</div></PageLayout>;
  }
  if (!campaign) {
    return (
      <PageLayout currentPage="Campaign">
        <Alert message={error || 'Campaign not found.'} variant="error" />
        <div style={{ marginTop: 16 }}><Button label="Back to Campaigns" variant="outline" onClick={() => router.push('/alumni/campaigns')} /></div>
      </PageLayout>
    );
  }

  const canDispatch = isAdmin && ['draft', 'scheduled'].includes(campaign.status);
  const canCancel   = isAdmin && ['draft', 'scheduled'].includes(campaign.status);

  const stats = [
    { label: 'Recipients',    value: campaign.totalQueued ?? 0 },
    { label: 'Sent',          value: campaign.totalSent ?? 0 },
    { label: 'Opened',        value: campaign.totalOpened ?? 0 },
    { label: 'Unsubscribed',  value: campaign.unsubscribeCount ?? 0 },
    { label: 'Open Rate',     value: campaign.openRatePct != null ? `${campaign.openRatePct}%` : '—' },
  ];

  return (
    <PageLayout currentPage="Campaign">
      <div style={{ maxWidth: 780, margin: '0 auto' }}>
        {/* Back */}
        <button
          onClick={() => router.push('/alumni/campaigns')}
          style={{ background: 'none', border: 'none', color: theme.primary, fontSize: 13, fontWeight: 600, cursor: 'pointer', padding: '0 0 16px 0' }}
        >
          ← Campaigns
        </button>

        {error      && <Alert message={error}     variant="error"   onClose={() => setError('')}     />}
        {actionMsg  && <Alert message={actionMsg} variant="success" onClose={() => setActionMsg('')} />}

        {/* Header */}
        <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 20, gap: 16 }}>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 6 }}>
              <h1 style={{ fontSize: 22, fontWeight: 700, color: theme.gray900, margin: 0 }}>{campaign.name}</h1>
              <Badge label={campaign.status} variant={STATUS_BADGE[campaign.status] ?? 'gray'} />
            </div>
            {campaign.subjectLine && (
              <p style={{ fontSize: 14, color: theme.gray500, margin: 0 }}>Subject: {campaign.subjectLine}</p>
            )}
          </div>
          {isAdmin && (
            <div style={{ display: 'flex', gap: 10, flexShrink: 0 }}>
              {canDispatch && (
                <Button label={dispatching ? 'Sending...' : 'Send Now'} loading={dispatching} onClick={handleDispatch} />
              )}
              {canCancel && (
                <Button label={cancelling ? 'Cancelling...' : 'Cancel Campaign'} variant="danger" loading={cancelling} onClick={handleCancel} />
              )}
            </div>
          )}
        </div>

        {/* Stats grid */}
        <div style={{
          display:         'grid',
          gridTemplateColumns: `repeat(${stats.length}, 1fr)`,
          gap:             12,
          marginBottom:    20,
        }}>
          {stats.map(s => (
            <div key={s.label} style={{
              backgroundColor: theme.cardBg,
              border:          `1px solid ${theme.cardBorder}`,
              borderRadius:    'var(--radius-lg)',
              padding:         '18px 20px',
              textAlign:       'center',
            }}>
              <div style={{ fontSize: 26, fontWeight: 700, color: theme.primary }}>{s.value}</div>
              <div style={{ fontSize: 12, color: theme.gray500, marginTop: 2 }}>{s.label}</div>
            </div>
          ))}
        </div>

        {/* Details */}
        <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: '20px 24px' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 14 }}>
            <tbody>
              {[
                { label: 'Audience',   value: AUDIENCE_LABEL[campaign.targetAudience] ?? campaign.targetAudience },
                { label: 'Created',    value: new Date(campaign.createdAt).toLocaleString() },
                { label: 'Started',    value: campaign.startedAt   ? new Date(campaign.startedAt).toLocaleString()   : '—' },
                { label: 'Completed',  value: campaign.completedAt ? new Date(campaign.completedAt).toLocaleString() : '—' },
                { label: 'Scheduled',  value: campaign.scheduledAt ? new Date(campaign.scheduledAt).toLocaleString() : '—' },
              ].map(row => (
                <tr key={row.label} style={{ borderBottom: `1px solid ${theme.gray100}` }}>
                  <td style={{ padding: '10px 0', color: theme.gray500, fontWeight: 600, width: 120 }}>{row.label}</td>
                  <td style={{ padding: '10px 0', color: theme.gray800 }}>{row.value}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </PageLayout>
  );
}
