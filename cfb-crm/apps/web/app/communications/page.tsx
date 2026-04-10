'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { appApi } from '@/lib/api';
import { hasAppAccess, isGlobalAdmin } from '@/lib/auth';
import { theme } from '@/lib/theme';
import { useTeamConfig } from '@/lib/teamConfig';
import { Alert, Badge, Button, PageLayout } from '@/components';

// ─── Types ────────────────────────────────────────────────────────────────────

interface Campaign {
  id:              string;
  name:            string;
  targetAudience:  string;
  status:          string;
  sentCount:       number;
  respondedCount:  number;
  responseRatePct: number;
  createdAt:       string;
  subjectLine?:    string;
}

interface FeedPost {
  id:          string;
  title:       string | null;
  audience:    string;
  publishedAt: string;
  readCount?:  number;
}

interface Stats {
  totalEmailsSent: number;
  avgOpenRate:     number;
  totalPosts:      number;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const AUDIENCE_LABEL: Record<string, string> = {
  all:          'Everyone',
  players_only: 'Players',
  alumni_only:  'Alumni',
  byGradYear:   'By Grad Year',
  byPosition:   'By Position',
  custom:       'Custom',
};

const STATUS_COLOR: Record<string, string> = {
  draft:     theme.gray400,
  active:    theme.primary,
  completed: theme.accent,
  cancelled: theme.gray400,
};

function fmt(iso: string) {
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

// ─── Create Email Modal ───────────────────────────────────────────────────────

interface ModalProps {
  positions:    string[];
  gradYears:    number[];
  onClose:      () => void;
  onSent:       () => void;
}

function CreateEmailModal({ positions, gradYears, onClose, onSent }: ModalProps) {
  const [subject,       setSubject]       = useState('');
  const [body,          setBody]          = useState('');
  const [audiences,     setAudiences]     = useState<Set<string>>(new Set(['alumni_only']));
  const [postToFeed,    setPostToFeed]    = useState(true);
  const [submitting,    setSubmitting]    = useState(false);
  const [error,         setError]         = useState<string | null>(null);

  const toggleAudience = (val: string) => {
    setAudiences(prev => {
      const next = new Set(prev);
      if (next.has(val)) { next.delete(val); } else { next.add(val); }
      return next;
    });
  };

  // Map chip selection to audience string
  const resolveAudience = (): string => {
    const hasPlayers = audiences.has('players_only');
    const hasAlumni  = audiences.has('alumni_only');
    if (hasPlayers && hasAlumni) return 'all';
    if (hasPlayers) return 'players_only';
    if (hasAlumni)  return 'alumni_only';
    return 'all';
  };

  const handleSend = async () => {
    if (!subject.trim()) { setError('Subject is required'); return; }
    if (!body.trim())    { setError('Email body is required'); return; }
    if (audiences.size === 0) { setError('Select at least one audience'); return; }

    setSubmitting(true);
    setError(null);
    try {
      const audience = resolveAudience();

      if (postToFeed) {
        // Single call: creates feed post + dispatches email
        await appApi.post('/feed', {
          title:        subject,
          bodyHtml:     body,
          audience,
          alsoEmail:    true,
          emailSubject: subject,
        });
      } else {
        // Email only — create campaign then dispatch
        const { data: created } = await appApi.post('/campaigns', {
          name:           subject,
          targetAudience: audience,
          subjectLine:    subject,
          bodyHtml:       body,
        });
        await appApi.post(`/campaigns/${created.data.id}/dispatch`);
      }

      onSent();
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { error?: string } } })?.response?.data?.error;
      setError(msg ?? 'Failed to send');
    } finally {
      setSubmitting(false);
    }
  };

  const chip = (label: string, val: string) => (
    <button
      key={val}
      onClick={() => toggleAudience(val)}
      style={{
        padding: '6px 14px', borderRadius: 20, fontSize: 13, fontWeight: 500,
        cursor: 'pointer', border: `1px solid ${audiences.has(val) ? theme.primary : theme.cardBorder}`,
        backgroundColor: audiences.has(val) ? theme.primaryLight : theme.white,
        color: audiences.has(val) ? theme.primaryDark : theme.gray600,
        transition: 'all 0.15s',
      }}
    >{label}</button>
  );

  return (
    <div style={{ position: 'fixed', inset: 0, backgroundColor: 'rgba(0,0,0,0.5)', zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
      <div style={{ backgroundColor: theme.white, borderRadius: 16, padding: 32, width: '100%', maxWidth: 560, maxHeight: '90vh', overflowY: 'auto', boxShadow: '0 20px 60px rgba(0,0,0,0.2)' }}>
        <h2 style={{ fontSize: 20, fontWeight: 700, color: theme.gray900, margin: '0 0 24px 0' }}>Create Email</h2>

        {error && <div style={{ marginBottom: 16 }}><Alert variant="error" message={error} /></div>}

        {/* Audience chips */}
        <div style={{ marginBottom: 20 }}>
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, color: theme.gray700, marginBottom: 8 }}>Send To</label>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {chip('Players', 'players_only')}
            {chip('Alumni',  'alumni_only')}
          </div>
          <p style={{ fontSize: 12, color: theme.gray400, marginTop: 6 }}>
            {audiences.size === 0 ? 'Select at least one' : `Sending to: ${AUDIENCE_LABEL[resolveAudience()]}`}
          </p>
        </div>

        {/* Subject */}
        <div style={{ marginBottom: 16 }}>
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, color: theme.gray700, marginBottom: 6 }}>Subject</label>
          <input
            value={subject}
            onChange={e => setSubject(e.target.value)}
            placeholder="Email subject line"
            style={{ width: '100%', padding: '10px 12px', borderRadius: 8, border: `1px solid ${theme.cardBorder}`, fontSize: 14, color: theme.gray900, boxSizing: 'border-box' }}
          />
        </div>

        {/* Body */}
        <div style={{ marginBottom: 20 }}>
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, color: theme.gray700, marginBottom: 6 }}>
            Message <span style={{ fontWeight: 400, color: theme.gray400 }}>(HTML supported)</span>
          </label>
          <textarea
            value={body}
            onChange={e => setBody(e.target.value)}
            placeholder="<p>Hello {firstName},</p><p>...</p>"
            rows={10}
            style={{ width: '100%', padding: '10px 12px', borderRadius: 8, border: `1px solid ${theme.cardBorder}`, fontSize: 13, color: theme.gray900, resize: 'vertical', fontFamily: 'monospace', boxSizing: 'border-box' }}
          />
        </div>

        {/* Post to feed toggle */}
        <label style={{ display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer', marginBottom: 24 }}>
          <input
            type="checkbox"
            checked={postToFeed}
            onChange={e => setPostToFeed(e.target.checked)}
            style={{ width: 16, height: 16, accentColor: theme.primary }}
          />
          <span style={{ fontSize: 14, color: theme.gray700 }}>Also post to newsfeed</span>
          <span style={{ fontSize: 12, color: theme.gray400 }}>(recipients will also see it in the app)</span>
        </label>

        {/* Actions */}
        <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end' }}>
          <Button label="Cancel" variant="secondary" onClick={onClose} disabled={submitting} />
          <Button label={submitting ? 'Sending…' : 'Send Email'} onClick={handleSend} disabled={submitting || audiences.size === 0} />
        </div>
      </div>
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function CommunicationsPage() {
  const router   = useRouter();
  const { positions, academicYears } = useTeamConfig();

  const [campaigns,      setCampaigns]      = useState<Campaign[]>([]);
  const [posts,          setPosts]          = useState<FeedPost[]>([]);
  const [stats,          setStats]          = useState<Stats>({ totalEmailsSent: 0, avgOpenRate: 0, totalPosts: 0 });
  const [loading,        setLoading]        = useState(true);
  const [error,          setError]          = useState<string | null>(null);
  const [showModal,      setShowModal]      = useState(false);
  const [successMsg,     setSuccessMsg]     = useState<string | null>(null);
  const [campaignsOpen,  setCampaignsOpen]  = useState(true);
  const [postsOpen,      setPostsOpen]      = useState(true);

  const canAccess = isGlobalAdmin() || hasAppAccess('roster') || hasAppAccess('alumni');

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [campRes, feedRes] = await Promise.all([
        appApi.get('/campaigns'),
        appApi.get('/feed?page=1&pageSize=50'),
      ]);

      const camps: Campaign[] = campRes.data.data ?? [];
      const feedPosts: FeedPost[] = (feedRes.data.data ?? []).map((p: FeedPost & { readCount?: number }) => p);

      setCampaigns(camps);
      setPosts(feedPosts);

      const totalSent  = camps.reduce((s, c) => s + (c.sentCount ?? 0), 0);
      const rateSum    = camps.filter(c => c.sentCount > 0).reduce((s, c) => s + c.responseRatePct, 0);
      const rateCount  = camps.filter(c => c.sentCount > 0).length;
      setStats({
        totalEmailsSent: totalSent,
        avgOpenRate:     rateCount > 0 ? Math.round(rateSum / rateCount) : 0,
        totalPosts:      feedPosts.length,
      });
    } catch {
      setError('Failed to load communications data');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!canAccess) { router.push('/dashboard'); return; }
    load();
  }, []);

  const handleSent = () => {
    setShowModal(false);
    setSuccessMsg('Email sent successfully!');
    load();
    setTimeout(() => setSuccessMsg(null), 4000);
  };

  const gradYearNumbers = (academicYears ?? []).map(y => typeof y === 'number' ? y : parseInt(y as string, 10)).filter(Boolean);

  const statCard = (label: string, value: string | number) => (
    <div style={{ backgroundColor: theme.white, border: `1px solid ${theme.cardBorder}`, borderRadius: 12, padding: '20px 24px', flex: 1, minWidth: 140 }}>
      <div style={{ fontSize: 28, fontWeight: 700, color: theme.gray900 }}>{value}</div>
      <div style={{ fontSize: 13, color: theme.gray500, marginTop: 4 }}>{label}</div>
    </div>
  );

  return (
    <PageLayout>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>Communications</h1>
          <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>Email campaigns, open rates, and feed engagement</p>
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          <Button label="+ New Post"    onClick={() => router.push('/feed/new')} />
          <Button label="+ Create Email" onClick={() => setShowModal(true)} />
        </div>
      </div>

      {successMsg && <div style={{ marginBottom: 16 }}><Alert variant="success" message={successMsg} /></div>}
      {error      && <div style={{ marginBottom: 16 }}><Alert variant="error"   message={error}      /></div>}

      {/* Stats row */}
      {!loading && (
        <div style={{ display: 'flex', gap: 16, marginBottom: 32, flexWrap: 'wrap' }}>
          {statCard('Emails Sent',   stats.totalEmailsSent)}
          {statCard('Avg Open Rate', `${stats.avgOpenRate}%`)}
          {statCard('Feed Posts',    stats.totalPosts)}
        </div>
      )}

      {loading ? (
        <p style={{ color: theme.gray500, padding: '40px 0', textAlign: 'center' }}>Loading…</p>
      ) : (
        <>
          {/* Email Campaigns — collapsible */}
          <div style={{ marginBottom: 24 }}>
            <button
              onClick={() => setCampaignsOpen(o => !o)}
              style={{ display: 'flex', alignItems: 'center', gap: 10, background: 'none', border: 'none', cursor: 'pointer', padding: '0 0 12px 0', width: '100%', textAlign: 'left' }}
            >
              <span style={{ fontSize: 17, fontWeight: 600, color: theme.gray900 }}>Email Campaigns</span>
              <span style={{ fontSize: 12, fontWeight: 700, backgroundColor: theme.primaryLight, color: theme.primaryDark, borderRadius: 20, padding: '2px 8px' }}>{campaigns.length}</span>
              <span style={{ marginLeft: 'auto', fontSize: 18, color: theme.gray400, lineHeight: 1 }}>{campaignsOpen ? '▾' : '▸'}</span>
            </button>
            {campaignsOpen && (
              campaigns.length === 0 ? (
                <p style={{ color: theme.gray400, fontSize: 14, margin: 0 }}>No campaigns yet. Create your first email above.</p>
              ) : (
                <div style={{ backgroundColor: theme.white, border: `1px solid ${theme.cardBorder}`, borderRadius: 12, overflow: 'hidden' }}>
                  <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
                    <thead>
                      <tr style={{ borderBottom: `1px solid ${theme.cardBorder}`, backgroundColor: theme.gray50 }}>
                        {['Subject / Name', 'Audience', 'Status', 'Sent', 'Opened', 'Open Rate', 'Date'].map(h => (
                          <th key={h} style={{ padding: '10px 16px', textAlign: 'left', fontWeight: 600, color: theme.gray600 }}>{h}</th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {campaigns.map((c, i) => (
                        <tr
                          key={c.id}
                          onClick={() => router.push(`/alumni/campaigns/${c.id}`)}
                          style={{ borderBottom: i < campaigns.length - 1 ? `1px solid ${theme.cardBorder}` : 'none', cursor: 'pointer', transition: 'background 0.1s' }}
                          onMouseEnter={e => (e.currentTarget.style.backgroundColor = theme.gray50)}
                          onMouseLeave={e => (e.currentTarget.style.backgroundColor = 'transparent')}
                        >
                          <td style={{ padding: '12px 16px', color: theme.gray900, fontWeight: 500 }}>{c.name}</td>
                          <td style={{ padding: '12px 16px' }}>
                            <Badge label={AUDIENCE_LABEL[c.targetAudience] ?? c.targetAudience} variant="green" />
                          </td>
                          <td style={{ padding: '12px 16px' }}>
                            <span style={{ fontSize: 12, fontWeight: 600, color: STATUS_COLOR[c.status] ?? theme.gray500, textTransform: 'capitalize' }}>{c.status}</span>
                          </td>
                          <td style={{ padding: '12px 16px', color: theme.gray700 }}>{c.sentCount ?? 0}</td>
                          <td style={{ padding: '12px 16px', color: theme.gray700 }}>{c.respondedCount ?? 0}</td>
                          <td style={{ padding: '12px 16px', color: theme.gray700, fontWeight: 500 }}>{c.responseRatePct ?? 0}%</td>
                          <td style={{ padding: '12px 16px', color: theme.gray500 }}>{fmt(c.createdAt)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )
            )}
          </div>

          {/* Feed Posts — collapsible */}
          <div>
            <button
              onClick={() => setPostsOpen(o => !o)}
              style={{ display: 'flex', alignItems: 'center', gap: 10, background: 'none', border: 'none', cursor: 'pointer', padding: '0 0 12px 0', width: '100%', textAlign: 'left' }}
            >
              <span style={{ fontSize: 17, fontWeight: 600, color: theme.gray900 }}>Feed Posts</span>
              <span style={{ fontSize: 12, fontWeight: 700, backgroundColor: theme.primaryLight, color: theme.primaryDark, borderRadius: 20, padding: '2px 8px' }}>{posts.length}</span>
              <span style={{ marginLeft: 'auto', fontSize: 18, color: theme.gray400, lineHeight: 1 }}>{postsOpen ? '▾' : '▸'}</span>
            </button>
            {postsOpen && (
              posts.length === 0 ? (
                <p style={{ color: theme.gray400, fontSize: 14, margin: 0 }}>No posts yet.</p>
              ) : (
                <div style={{ backgroundColor: theme.white, border: `1px solid ${theme.cardBorder}`, borderRadius: 12, overflow: 'hidden' }}>
                  <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
                    <thead>
                      <tr style={{ borderBottom: `1px solid ${theme.cardBorder}`, backgroundColor: theme.gray50 }}>
                        {['Title', 'Audience', 'Date'].map(h => (
                          <th key={h} style={{ padding: '10px 16px', textAlign: 'left', fontWeight: 600, color: theme.gray600 }}>{h}</th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {posts.map((p, i) => (
                        <tr
                          key={p.id}
                          onClick={() => router.push(`/feed/${p.id}`)}
                          style={{ borderBottom: i < posts.length - 1 ? `1px solid ${theme.cardBorder}` : 'none', cursor: 'pointer', transition: 'background 0.1s' }}
                          onMouseEnter={e => (e.currentTarget.style.backgroundColor = theme.gray50)}
                          onMouseLeave={e => (e.currentTarget.style.backgroundColor = 'transparent')}
                        >
                          <td style={{ padding: '12px 16px', color: theme.gray900, fontWeight: 500 }}>{p.title ?? '(no title)'}</td>
                          <td style={{ padding: '12px 16px' }}>
                            <Badge label={AUDIENCE_LABEL[p.audience] ?? p.audience} variant="gold" />
                          </td>
                          <td style={{ padding: '12px 16px', color: theme.gray500 }}>{fmt(p.publishedAt)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )
            )}
          </div>
        </>
      )}

      {showModal && (
        <CreateEmailModal
          positions={positions ?? []}
          gradYears={gradYearNumbers}
          onClose={() => setShowModal(false)}
          onSent={handleSent}
        />
      )}
    </PageLayout>
  );
}
