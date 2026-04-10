'use client';

import React, { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import DOMPurify from 'isomorphic-dompurify';
import { appApi } from '@/lib/api';
import { theme } from '@/lib/theme';
import { Alert, Badge, Button, PageLayout } from '@/components';

interface FeedPost {
  id:            string;
  title:         string | null;
  bodyHtml:      string;
  audience:      string;
  isPinned:      boolean;
  isWelcomePost: boolean;
  campaignId:    string | null;
  createdBy:     string;
  publishedAt:   string;
  isRead:        boolean;
}

interface ReadStats {
  totalEligible:     number;
  totalRead:         number;
  readThroughRatePct: number;
}

const AUDIENCE_LABEL: Record<string, string> = {
  all:          'All',
  players_only: 'Players',
  alumni_only:  'Alumni',
  by_position:  'By Position',
  by_grad_year: 'By Grad Year',
  custom:       'Custom',
};

const AUDIENCE_BADGE: Record<string, 'green' | 'gold' | 'gray'> = {
  all:          'gray',
  players_only: 'green',
  alumni_only:  'gold',
};

export default function FeedPostPage() {
  const { id }        = useParams<{ id: string }>();
  const router        = useRouter();
  const [post,  setPost]  = useState<FeedPost | null>(null);
  const [stats, setStats] = useState<ReadStats | null>(null);
  const [loading,  setLoading]  = useState(true);
  const [error,    setError]    = useState('');
  const [canWrite, setCanWrite] = useState(false);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        const { data } = await appApi.get(`/feed/${id}`);
        if (!data.success) { setError('Post not found.'); return; }
        setPost(data.data);

        // Mark as read
        appApi.post(`/feed/${id}/read`).catch(() => {});

        // Try to load stats (will 403 if not a writer — ignore)
        try {
          const statsRes = await appApi.get(`/feed/${id}/stats`);
          if (statsRes.data.success) {
            setStats(statsRes.data.data);
            setCanWrite(true);
          }
        } catch { /* not a writer */ }

      } catch {
        setError('Failed to load post.');
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [id]);

  if (loading) {
    return (
      <PageLayout currentPage="Post">
        <div style={{ textAlign: 'center', padding: 60, color: theme.gray400 }}>Loading...</div>
      </PageLayout>
    );
  }

  if (error || !post) {
    return (
      <PageLayout currentPage="Post">
        <Alert message={error || 'Post not found.'} variant="error" />
        <div style={{ marginTop: 16 }}>
          <Button label="Back to Feed" variant="outline" onClick={() => router.push('/feed')} />
        </div>
      </PageLayout>
    );
  }

  const published = new Date(post.publishedAt).toLocaleDateString('en-US', {
    weekday: 'long', month: 'long', day: 'numeric', year: 'numeric',
  });

  const safeHtml = DOMPurify.sanitize(post.bodyHtml, {
    ALLOWED_TAGS: ['b','i','em','strong','a','p','ul','ol','li','br','h1','h2','h3','span','div'],
    ALLOWED_ATTR: ['href','style','target'],
  });

  return (
    <PageLayout currentPage="Post">
      <div style={{ maxWidth: 720, margin: '0 auto' }}>
        {/* Back */}
        <button
          onClick={() => router.push('/feed')}
          style={{ background: 'none', border: 'none', color: theme.primary, fontSize: 13, fontWeight: 600, cursor: 'pointer', padding: '0 0 16px 0', display: 'flex', alignItems: 'center', gap: 4 }}
        >
          ← Feed
        </button>

        {/* Post */}
        <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: '28px 32px' }}>
          {/* Meta */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16, flexWrap: 'wrap' }}>
            {post.isPinned && <span style={{ fontSize: 12, color: theme.accent, fontWeight: 700 }}>📌 Pinned</span>}
            <Badge
              label={AUDIENCE_LABEL[post.audience] ?? post.audience}
              variant={AUDIENCE_BADGE[post.audience] ?? 'gray'}
            />
            <span style={{ fontSize: 13, color: theme.gray400, marginLeft: 'auto' }}>{published}</span>
          </div>

          {/* Title */}
          {post.title && (
            <h1 style={{ fontSize: 22, fontWeight: 700, color: theme.gray900, margin: '0 0 16px 0' }}>
              {post.title}
            </h1>
          )}

          {/* Body */}
          <div
            style={{ fontSize: 15, lineHeight: 1.7, color: theme.gray800 }}
            dangerouslySetInnerHTML={{ __html: safeHtml }}
          />
        </div>

        {/* Read stats — admin/writer only */}
        {canWrite && stats && (
          <div style={{
            marginTop:       20,
            backgroundColor: theme.cardBg,
            border:          `1px solid ${theme.cardBorder}`,
            borderRadius:    'var(--radius-lg)',
            padding:         '20px 28px',
          }}>
            <h3 style={{ fontSize: 14, fontWeight: 700, color: theme.gray700, margin: '0 0 14px 0', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
              Read Stats
            </h3>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16 }}>
              {[
                { label: 'Eligible',     value: stats.totalEligible },
                { label: 'Read',         value: stats.totalRead },
                { label: 'Read-Through', value: `${stats.readThroughRatePct}%` },
              ].map(s => (
                <div key={s.label} style={{ textAlign: 'center' }}>
                  <div style={{ fontSize: 28, fontWeight: 700, color: theme.primary }}>{s.value}</div>
                  <div style={{ fontSize: 12, color: theme.gray500, marginTop: 2 }}>{s.label}</div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </PageLayout>
  );
}
