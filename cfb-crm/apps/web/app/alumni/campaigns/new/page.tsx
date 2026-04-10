'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { appApi } from '@/lib/api';
import { theme } from '@/lib/theme';
import { useTeamConfig } from '@/lib/teamConfig';
import { Alert, Button, Input, PageLayout, Select } from '@/components';

const AUDIENCE_OPTIONS = [
  { value: 'alumni_only',  label: 'Alumni only'                 },
  { value: 'players_only', label: 'Current Players only'        },
  { value: 'all',          label: 'Everyone (players + alumni)' },
  { value: 'byGradYear',   label: 'By Graduation Year'          },
  { value: 'byPosition',   label: 'By Position'                 },
  { value: 'custom',       label: 'Custom filter'               },
];

const GRAD_YEAR_OPTIONS = Array.from({ length: 30 }, (_, i) => {
  const y = new Date().getFullYear() - i;
  return { value: String(y), label: String(y) };
});

export default function NewCampaignPage() {
  const router              = useRouter();
  const { positions }       = useTeamConfig();
  const POSITION_OPTIONS    = positions.map(p => ({ value: p, label: p }));

  const [name,            setName]            = useState('');
  const [description,     setDescription]     = useState('');
  const [targetAudience,  setTargetAudience]  = useState('alumni_only');
  const [subjectLine,     setSubjectLine]      = useState('');
  const [bodyHtml,        setBodyHtml]        = useState('');
  const [fromName,        setFromName]        = useState('');
  const [replyToEmail,    setReplyToEmail]    = useState('');
  const [filterGradYear,  setFilterGradYear]  = useState('');
  const [filterPosition,  setFilterPosition]  = useState('');
  const [dispatchNow,     setDispatchNow]     = useState(false);
  const [submitting,      setSubmitting]      = useState(false);
  const [error,           setError]           = useState('');

  function buildAudienceFilters(): Record<string, unknown> | undefined {
    const f: Record<string, unknown> = {};
    if (filterGradYear) f.gradYear = Number(filterGradYear);
    if (filterPosition) f.position = filterPosition;
    return Object.keys(f).length > 0 ? f : undefined;
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim())       { setError('Campaign name is required.'); return; }
    if (!subjectLine.trim()){ setError('Subject line is required.'); return; }
    if (!bodyHtml.trim())   { setError('Email body is required.'); return; }
    setError('');
    setSubmitting(true);
    try {
      const { data } = await appApi.post('/campaigns', {
        name:            name.trim(),
        description:     description.trim() || undefined,
        targetAudience,
        audienceFilters: buildAudienceFilters(),
        subjectLine:     subjectLine.trim(),
        bodyHtml,
        fromName:        fromName.trim() || undefined,
        replyToEmail:    replyToEmail.trim() || undefined,
      });
      if (!data.success) throw new Error(data.error ?? 'Unknown error');
      const campaignId = data.data.id;

      if (dispatchNow) {
        try {
          await appApi.post(`/campaigns/${campaignId}/dispatch`);
        } catch (dispatchErr) {
          // Campaign was created; dispatch failed — send to detail page with error
          router.push(`/alumni/campaigns/${campaignId}?dispatchError=1`);
          return;
        }
      }

      router.push(`/alumni/campaigns/${campaignId}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create campaign');
    } finally {
      setSubmitting(false);
    }
  };

  const audienceLabel = AUDIENCE_OPTIONS.find(o => o.value === targetAudience)?.label ?? targetAudience;

  return (
    <PageLayout currentPage="New Campaign">
      <div style={{ maxWidth: 720, margin: '0 auto' }}>
        <div style={{ marginBottom: 24 }}>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>New Email Campaign</h1>
          <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>
            Build a broadcast email. Recipients who have unsubscribed are automatically excluded.
          </p>
        </div>

        {error && <Alert message={error} variant="error" onClose={() => setError('')} />}

        <form onSubmit={handleSubmit}>
          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 28 }}>

            {/* Campaign name */}
            <div style={{ marginBottom: 18 }}>
              <label style={{ fontSize: 13, fontWeight: 600, color: theme.gray700, display: 'block', marginBottom: 6 }}>
                Campaign Name <span style={{ color: theme.danger }}>*</span>
              </label>
              <Input value={name} onChange={setName} placeholder="e.g. Spring 2026 Alumni Outreach" />
            </div>

            {/* Audience */}
            <div style={{ marginBottom: 18 }}>
              <label style={{ fontSize: 13, fontWeight: 600, color: theme.gray700, display: 'block', marginBottom: 6 }}>
                Audience
              </label>
              <Select value={targetAudience} onChange={setTargetAudience} options={AUDIENCE_OPTIONS} />
            </div>

            {/* Audience sub-filters */}
            {(targetAudience === 'byGradYear' || targetAudience === 'custom') && (
              <div style={{ marginBottom: 18 }}>
                <label style={{ fontSize: 12, color: theme.gray500, display: 'block', marginBottom: 4 }}>Graduation Year</label>
                <Select value={filterGradYear} onChange={setFilterGradYear} options={[{ value: '', label: 'Any' }, ...GRAD_YEAR_OPTIONS.slice(0, 20)]} />
              </div>
            )}
            {(targetAudience === 'byPosition' || targetAudience === 'custom') && POSITION_OPTIONS.length > 0 && (
              <div style={{ marginBottom: 18 }}>
                <label style={{ fontSize: 12, color: theme.gray500, display: 'block', marginBottom: 4 }}>Position</label>
                <Select value={filterPosition} onChange={setFilterPosition} options={[{ value: '', label: 'Any' }, ...POSITION_OPTIONS]} />
              </div>
            )}

            {/* Subject line */}
            <div style={{ marginBottom: 18 }}>
              <label style={{ fontSize: 13, fontWeight: 600, color: theme.gray700, display: 'block', marginBottom: 6 }}>
                Subject Line <span style={{ color: theme.danger }}>*</span>
              </label>
              <Input value={subjectLine} onChange={setSubjectLine} placeholder="Email subject line..." />
            </div>

            {/* Body */}
            <div style={{ marginBottom: 18 }}>
              <label style={{ fontSize: 13, fontWeight: 600, color: theme.gray700, display: 'block', marginBottom: 6 }}>
                Email Body <span style={{ color: theme.danger }}>*</span>
              </label>
              <textarea
                value={bodyHtml}
                onChange={e => setBodyHtml(e.target.value)}
                placeholder="Email body HTML. Use {first_name} to personalize."
                rows={10}
                style={{
                  width: '100%', padding: '10px 12px',
                  border: `1.5px solid ${theme.gray200}`, borderRadius: 'var(--radius-md)',
                  fontSize: 14, color: theme.gray900, fontFamily: 'inherit',
                  resize: 'vertical', boxSizing: 'border-box', outline: 'none',
                }}
              />
              <p style={{ fontSize: 12, color: theme.gray400, marginTop: 4 }}>
                A CAN-SPAM compliant footer with an unsubscribe link will be appended automatically.
              </p>
            </div>

            {/* Sender override (optional) */}
            <details style={{ marginBottom: 18 }}>
              <summary style={{ fontSize: 13, fontWeight: 600, color: theme.gray700, cursor: 'pointer', marginBottom: 8 }}>
                Sender Branding (optional)
              </summary>
              <div style={{ paddingTop: 10, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                <div>
                  <label style={{ fontSize: 12, color: theme.gray500, display: 'block', marginBottom: 4 }}>From Name</label>
                  <Input value={fromName} onChange={setFromName} placeholder="USF Bulls Football" />
                </div>
                <div>
                  <label style={{ fontSize: 12, color: theme.gray500, display: 'block', marginBottom: 4 }}>Reply-To Email</label>
                  <Input value={replyToEmail} onChange={setReplyToEmail} placeholder="coaches@example.com" />
                </div>
              </div>
            </details>

            {/* Audience confirmation */}
            <div style={{
              padding: '14px 18px',
              backgroundColor: theme.primaryLight,
              borderRadius: 'var(--radius-md)',
              border: `1px solid ${theme.primary}`,
              marginBottom: 20, fontSize: 13, color: theme.primaryDark,
            }}>
              <strong>Audience:</strong> {audienceLabel}
              {filterGradYear && <span> · Class of {filterGradYear}</span>}
              {filterPosition && <span> · {filterPosition}</span>}
            </div>

            {/* Dispatch option */}
            <div style={{ marginBottom: 20 }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', fontSize: 14, color: theme.gray700 }}>
                <input type="checkbox" checked={dispatchNow} onChange={e => setDispatchNow(e.target.checked)} />
                Send immediately after saving
              </label>
            </div>

            {/* Actions */}
            <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end' }}>
              <Button label="Cancel" variant="outline" onClick={() => router.push('/alumni/campaigns')} />
              <Button
                label={submitting ? 'Saving...' : (dispatchNow ? 'Save & Send' : 'Save as Draft')}
                type="submit"
                loading={submitting}
              />
            </div>
          </div>
        </form>
      </div>
    </PageLayout>
  );
}
