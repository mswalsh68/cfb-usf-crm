'use client';

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { appApi } from '@/lib/api';
import { canWrite, getAppRole, hasAppAccess } from '@/lib/auth';
import { theme } from '@/lib/theme';
import { useTeamConfig } from '@/lib/teamConfig';
import { Alert, Badge, Button, PageLayout } from '@/components';

interface FeedPost {
  id:            string;
  title:         string | null;
  bodyHtml:      string;
  audience:      string;
  isPinned:      boolean;
  isWelcomePost: boolean;
  createdBy:     string;
  publishedAt:   string;
  isRead:        boolean;
}

const AUDIENCE_LABEL: Record<string, string> = {
  all:          'All',
  players_only: 'Players',
  alumni_only:  'Alumni',
  by_position:  'Position',
  by_grad_year: 'Grad Year',
  custom:       'Custom',
};

const AUDIENCE_BADGE: Record<string, 'green' | 'gold' | 'gray'> = {
  all:          'gray',
  players_only: 'green',
  alumni_only:  'gold',
  by_position:  'gray',
  by_grad_year: 'gray',
  custom:       'gray',
};

function FeedCard({
  post,
  onRead,
  onNavigate,
}: {
  post:       FeedPost;
  onRead:     (id: string) => void;
  onNavigate: (id: string) => void;
}) {
  const cardRef = useRef<HTMLDivElement>(null);
  const marked  = useRef(false);

  useEffect(() => {
    if (post.isRead || marked.current) return;
    const el = cardRef.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && !marked.current) {
          marked.current = true;
          onRead(post.id);
          observer.disconnect();
        }
      },
      { threshold: 0.6 }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [post.id, post.isRead, onRead]);

  const published = new Date(post.publishedAt).toLocaleDateString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric',
  });

  return (
    <div
      ref={cardRef}
      style={{
        backgroundColor: theme.cardBg,
        border:          `1px solid ${post.isRead ? theme.cardBorder : theme.primary}`,
        borderRadius:    'var(--radius-lg)',
        padding:         '20px 24px',
        cursor:          'pointer',
        transition:      'box-shadow 0.15s',
        position:        'relative',
      }}
      onClick={() => onNavigate(post.id)}
      onMouseEnter={e => { (e.currentTarget as HTMLElement).style.boxShadow = '0 2px 12px rgba(0,0,0,0.08)'; }}
      onMouseLeave={e => { (e.currentTarget as HTMLElement).style.boxShadow = 'none'; }}
    >
      {/* Unread indicator */}
      {!post.isRead && (
        <div style={{
          position:        'absolute',
          top:             16,
          right:           16,
          width:           8,
          height:          8,
          borderRadius:    '50%',
          backgroundColor: theme.primary,
        }} />
      )}

      {/* Header row */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10, flexWrap: 'wrap' }}>
        {post.isPinned && (
          <span style={{ fontSize: 12, color: theme.accent, fontWeight: 700 }}>📌 Pinned</span>
        )}
        <Badge
          label={AUDIENCE_LABEL[post.audience] ?? post.audience}
          variant={AUDIENCE_BADGE[post.audience] ?? 'gray'}
        />
        <span style={{ fontSize: 12, color: theme.gray400, marginLeft: 'auto' }}>{published}</span>
      </div>

      {/* Title */}
      {post.title && (
        <h2 style={{ fontSize: 16, fontWeight: 700, color: theme.gray900, margin: '0 0 8px 0' }}>
          {post.title}
        </h2>
      )}

      {/* Body preview — strip HTML tags for the card preview */}
      <p style={{
        fontSize:   14,
        color:      theme.gray600,
        margin:     0,
        display:    '-webkit-box',
        WebkitLineClamp: 3,
        WebkitBoxOrient: 'vertical',
        overflow:   'hidden',
      }}>
        {post.bodyHtml.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim()}
      </p>
    </div>
  );
}

export default function FeedPage() {
  const router          = useRouter();
  const { teamName }    = useTeamConfig();
  const [posts,    setPosts]    = useState<FeedPost[]>([]);
  const [loading,  setLoading]  = useState(true);
  const [error,    setError]    = useState('');
  const [page,     setPage]     = useState(1);
  const [total,    setTotal]    = useState(0);
  const [canPost,  setCanPost]  = useState(false);
  const PAGE_SIZE = 20;

  useEffect(() => {
    // Check write access client-side
    const role = getAppRole(null as never, 'roster') ?? getAppRole(null as never, 'alumni');
    setCanPost(canWrite(getAppRole(null as never, 'roster')) || canWrite(getAppRole(null as never, 'alumni')));

    // Simpler: just check if user has access at all; actual write guard is on the server
    const checkAccess = async () => {
      try {
        const { data } = await appApi.get('/feed?page=1&pageSize=1');
        if (data.success !== false) setCanPost(true); // will be filtered server-side
      } catch { /* ignore */ }
    };
    checkAccess();
  }, []);

  const fetchFeed = useCallback(async (p: number) => {
    setLoading(true);
    try {
      const { data } = await appApi.get('/feed', { params: { page: p, pageSize: PAGE_SIZE } });
      setPosts(prev => p === 1 ? (data.data ?? []) : [...prev, ...(data.data ?? [])]);
      setTotal(data.total ?? 0);
    } catch {
      setError('Failed to load feed.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchFeed(1); }, [fetchFeed]);

  const handleRead = useCallback(async (postId: string) => {
    setPosts(prev => prev.map(p => p.id === postId ? { ...p, isRead: true } : p));
    appApi.post(`/feed/${postId}/read`).catch(() => { /* fire and forget */ });
  }, []);

  const handleLoadMore = () => {
    const next = page + 1;
    setPage(next);
    fetchFeed(next);
  };

  const hasMore = posts.length < total;

  return (
    <PageLayout currentPage="Feed">
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>
            {teamName} Feed
          </h1>
          <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>{total} posts</p>
        </div>
        <Button label="+ New Post" onClick={() => router.push('/feed/new')} />
      </div>

      {error && <Alert message={error} variant="error" onClose={() => setError('')} />}

      {/* Posts */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        {loading && posts.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 60, color: theme.gray400 }}>Loading...</div>
        ) : posts.length === 0 ? (
          <div style={{
            textAlign:       'center',
            padding:         60,
            color:           theme.gray400,
            backgroundColor: theme.cardBg,
            borderRadius:    'var(--radius-lg)',
            border:          `1px dashed ${theme.cardBorder}`,
          }}>
            No posts yet. Staff can create posts using the button above.
          </div>
        ) : (
          posts.map(post => (
            <FeedCard
              key={post.id}
              post={post}
              onRead={handleRead}
              onNavigate={id => router.push(`/feed/${id}`)}
            />
          ))
        )}
      </div>

      {/* Load more */}
      {hasMore && (
        <div style={{ textAlign: 'center', marginTop: 24 }}>
          <Button
            label={loading ? 'Loading...' : 'Load More'}
            variant="outline"
            onClick={handleLoadMore}
          />
        </div>
      )}
    </PageLayout>
  );
}
