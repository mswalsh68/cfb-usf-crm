'use client';

import React, { useEffect, useState } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { alumniApi } from '@/lib/api';
import { theme } from '@/lib/theme';
import { getUser, isGlobalAdmin } from '@/lib/auth';
import { useTeamConfig } from '@/lib/teamConfig';
import { PageLayout, Button, Input, Select, Badge, Alert, Modal, Card } from '@/components';

const STATUS_OPTIONS = [
  { value: 'active',       label: 'Active'        },
  { value: 'lostContact',  label: 'Lost Contact'  },
  { value: 'doNotContact', label: 'Do Not Contact'},
  { value: 'deceased',     label: 'Deceased'      },
];

const CHANNEL_OPTIONS = [
  { value: 'phone',     label: 'Phone Call'  },
  { value: 'email',     label: 'Email'       },
  { value: 'in_person', label: 'In Person'   },
  { value: 'event',     label: 'Event'       },
];

const statusBadge = (s: string): 'green' | 'warning' | 'danger' | 'gray' =>
  ({ active: 'green', lostContact: 'warning', doNotContact: 'danger', deceased: 'gray' }[s] ?? 'gray') as any;

function EngagementBar({ score }: { score: number }) {
  const pct = Math.min(100, Math.max(0, score));
  const color = pct >= 70 ? theme.success : pct >= 40 ? theme.warning : theme.danger;
  return (
    <div style={{ marginTop: 8 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: theme.gray500, marginBottom: 4 }}>
        <span>Engagement</span>
        <span style={{ fontWeight: 700, color }}>{pct}/100</span>
      </div>
      <div style={{ height: 6, backgroundColor: theme.gray100, borderRadius: 3 }}>
        <div style={{ height: '100%', width: `${pct}%`, backgroundColor: color, borderRadius: 3, transition: 'width 0.4s ease' }} />
      </div>
    </div>
  );
}

export default function AlumniDetailPage() {
  const router    = useRouter();
  const { id }    = useParams<{ id: string }>();
  const { positions, classLabel, alumniLabel } = useTeamConfig();

  const [alumni,       setAlumni]       = useState<any>(null);
  const [interactions, setInteractions] = useState<any[]>([]);
  const [loading,      setLoading]      = useState(true);
  const [error,        setError]        = useState('');
  const [success,      setSuccess]      = useState('');
  const [showEdit,     setShowEdit]     = useState(false);
  const [saving,       setSaving]       = useState(false);

  // Edit form state
  const [edit, setEdit] = useState({
    status: '', personalEmail: '', phone: '', linkedInUrl: '',
    currentEmployer: '', currentJobTitle: '', currentCity: '', currentState: '',
    isDonor: false, lastDonationDate: '', totalDonations: '', notes: '',
  });

  // Interaction form state
  const [interaction, setInteraction] = useState({ channel: 'phone', summary: '', outcome: '', followUpAt: '' });
  const [loggingInteraction, setLoggingInteraction] = useState(false);

  useEffect(() => { fetchAlumni(); }, [id]);

  const fetchAlumni = async () => {
    setLoading(true);
    try {
      const { data } = await alumniApi.get(`/alumni/${id}`);
      const a = data.data;
      setAlumni(a);
      setInteractions(a.interactions ?? []);
      setEdit({
        status:          a.status          ?? 'active',
        personalEmail:   a.personalEmail   ?? '',
        phone:           a.phone           ?? '',
        linkedInUrl:     a.linkedInUrl     ?? '',
        currentEmployer: a.currentEmployer ?? '',
        currentJobTitle: a.currentJobTitle ?? '',
        currentCity:     a.currentCity     ?? '',
        currentState:    a.currentState    ?? '',
        isDonor:         !!a.isDonor,
        lastDonationDate:a.lastDonationDate ? a.lastDonationDate.slice(0,10) : '',
        totalDonations:  a.totalDonations  ? String(a.totalDonations) : '',
        notes:           a.notes           ?? '',
      });
    } catch {
      setError('Failed to load alumni record.');
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      await alumniApi.patch(`/alumni/${id}`, {
        status:          edit.status          || undefined,
        personalEmail:   edit.personalEmail   || undefined,
        phone:           edit.phone           || undefined,
        linkedInUrl:     edit.linkedInUrl     || undefined,
        currentEmployer: edit.currentEmployer || undefined,
        currentJobTitle: edit.currentJobTitle || undefined,
        currentCity:     edit.currentCity     || undefined,
        currentState:    edit.currentState    || undefined,
        isDonor:         edit.isDonor,
        lastDonationDate:edit.lastDonationDate || undefined,
        totalDonations:  edit.totalDonations ? parseFloat(edit.totalDonations) : undefined,
        notes:           edit.notes           || undefined,
      });
      setSuccess('Saved successfully.');
      setShowEdit(false);
      fetchAlumni();
    } catch (err: any) {
      setError(err?.response?.data?.error ?? 'Save failed.');
    } finally {
      setSaving(false);
    }
  };

  const handleLogInteraction = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!interaction.summary.trim()) { setError('Summary is required.'); return; }
    setLoggingInteraction(true);
    try {
      await alumniApi.post(`/alumni/${id}/interactions`, {
        channel:    interaction.channel,
        summary:    interaction.summary,
        outcome:    interaction.outcome   || undefined,
        followUpAt: interaction.followUpAt || undefined,
      });
      setSuccess('Interaction logged.');
      setInteraction({ channel: 'phone', summary: '', outcome: '', followUpAt: '' });
      fetchAlumni();
    } catch (err: any) {
      setError(err?.response?.data?.error ?? 'Failed to log interaction.');
    } finally {
      setLoggingInteraction(false);
    }
  };

  if (loading) {
    return (
      <PageLayout currentPage={alumniLabel}>
        <div style={{ textAlign: 'center', padding: 80, color: theme.gray400 }}>Loading...</div>
      </PageLayout>
    );
  }

  if (!alumni) {
    return (
      <PageLayout currentPage={alumniLabel}>
        <Alert message={error || 'Record not found.'} variant="error" />
        <Button label={`← Back to ${alumniLabel}`} variant="outline" onClick={() => router.push('/alumni')} />
      </PageLayout>
    );
  }

  const positionOptions = [{ value: '', label: 'No Position' }, ...positions.map(p => ({ value: p, label: p }))];

  return (
    <PageLayout currentPage={`${alumniLabel} / ${alumni.lastName}, ${alumni.firstName}`}>

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <button
            onClick={() => router.push('/alumni')}
            style={{ background: 'none', border: 'none', cursor: 'pointer', color: theme.gray500, fontSize: 22, lineHeight: 1 }}
          >
            ←
          </button>
          <div>
            <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>
              {alumni.firstName} {alumni.lastName}
            </h1>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 4 }}>
              <Badge label={alumni.status} variant={statusBadge(alumni.status)} />
              {alumni.isDonor && <Badge label="Donor" variant="gold" />}
              <span style={{ fontSize: 13, color: theme.gray500 }}>
                {alumni.graduationSemester} {alumni.graduationYear} · {alumni.position || '—'}
              </span>
            </div>
          </div>
        </div>
        {(isGlobalAdmin() || getUser()?.sub === alumni.userId) && (
          <Button label="Edit Profile" onClick={() => setShowEdit(true)} />
        )}
      </div>

      {error   && <Alert message={error}   variant="error"   onClose={() => setError('')}   />}
      {success && <Alert message={success} variant="success" onClose={() => setSuccess('')} />}

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>

        {/* Left column */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>

          {/* Identity card */}
          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <h2 style={{ fontSize: 12, fontWeight: 700, color: theme.primary, textTransform: 'uppercase', letterSpacing: '0.8px', marginTop: 0, marginBottom: 16, paddingBottom: 8, borderBottom: `2px solid ${theme.primaryLight}` }}>
              {alumniLabel} Profile
            </h2>
            <dl style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px 16px', margin: 0 }}>
              {[
                [classLabel,    alumni.recruitingClass ?? '—'],
                ['Grad Year',   `${alumni.graduationSemester} ${alumni.graduationYear}`],
                ['Position',    alumni.position || '—'],
                ['Source',      alumni.sourcePlayerId ? 'Transferred from Roster' : 'Manually Added'],
              ].map(([k, v]) => (
                <div key={k}>
                  <dt style={{ fontSize: 11, fontWeight: 600, color: theme.gray400, textTransform: 'uppercase', letterSpacing: '0.5px' }}>{k}</dt>
                  <dd style={{ fontSize: 14, color: theme.gray800, marginLeft: 0, marginTop: 2 }}>{v}</dd>
                </div>
              ))}
            </dl>
            <EngagementBar score={alumni.engagementScore ?? 0} />
          </div>

          {/* Contact card */}
          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <h2 style={{ fontSize: 12, fontWeight: 700, color: theme.primary, textTransform: 'uppercase', letterSpacing: '0.8px', marginTop: 0, marginBottom: 16, paddingBottom: 8, borderBottom: `2px solid ${theme.primaryLight}` }}>
              Contact
            </h2>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {[
                ['Email',    alumni.personalEmail, `mailto:${alumni.personalEmail}`],
                ['Phone',    alumni.phone,         `tel:${alumni.phone}`],
                ['LinkedIn', alumni.linkedInUrl,   alumni.linkedInUrl],
              ].map(([label, value, href]) => (
                <div key={label} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: 12, color: theme.gray400, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.5px' }}>{label}</span>
                  {value
                    ? <a href={href ?? '#'} target="_blank" rel="noreferrer" style={{ fontSize: 13, color: theme.primary, fontWeight: 500, textDecoration: 'none' }}>{value}</a>
                    : <span style={{ fontSize: 13, color: theme.gray300 }}>—</span>
                  }
                </div>
              ))}
            </div>
          </div>

          {/* Career card */}
          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <h2 style={{ fontSize: 12, fontWeight: 700, color: theme.primary, textTransform: 'uppercase', letterSpacing: '0.8px', marginTop: 0, marginBottom: 16, paddingBottom: 8, borderBottom: `2px solid ${theme.primaryLight}` }}>
              Career
            </h2>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {alumni.currentEmployer
                ? <>
                    <div style={{ fontSize: 15, fontWeight: 600, color: theme.gray900 }}>{alumni.currentEmployer}</div>
                    {alumni.currentJobTitle && <div style={{ fontSize: 13, color: theme.gray600 }}>{alumni.currentJobTitle}</div>}
                    {(alumni.currentCity || alumni.currentState) && (
                      <div style={{ fontSize: 13, color: theme.gray500 }}>
                        {[alumni.currentCity, alumni.currentState].filter(Boolean).join(', ')}
                      </div>
                    )}
                  </>
                : <span style={{ fontSize: 13, color: theme.gray300 }}>No employer on record</span>
              }
            </div>
          </div>

          {/* Donor card */}
          {alumni.isDonor && (
            <div style={{ backgroundColor: theme.accentLight, border: `1px solid ${theme.accent}`, borderRadius: 'var(--radius-lg)', padding: 24 }}>
              <h2 style={{ fontSize: 12, fontWeight: 700, color: theme.accentDark, textTransform: 'uppercase', letterSpacing: '0.8px', marginTop: 0, marginBottom: 12 }}>
                Donor
              </h2>
              <div style={{ display: 'flex', gap: 24 }}>
                {alumni.totalDonations && (
                  <div>
                    <div style={{ fontSize: 11, color: theme.accentDark, fontWeight: 600 }}>TOTAL DONATED</div>
                    <div style={{ fontSize: 20, fontWeight: 700, color: theme.accentDark }}>${Number(alumni.totalDonations).toLocaleString()}</div>
                  </div>
                )}
                {alumni.lastDonationDate && (
                  <div>
                    <div style={{ fontSize: 11, color: theme.accentDark, fontWeight: 600 }}>LAST DONATION</div>
                    <div style={{ fontSize: 14, fontWeight: 600, color: theme.accentDark }}>{new Date(alumni.lastDonationDate).toLocaleDateString()}</div>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Right column — Interaction log */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>

          {/* Log new interaction */}
          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <h2 style={{ fontSize: 12, fontWeight: 700, color: theme.primary, textTransform: 'uppercase', letterSpacing: '0.8px', marginTop: 0, marginBottom: 16, paddingBottom: 8, borderBottom: `2px solid ${theme.primaryLight}` }}>
              Log Interaction
            </h2>
            <form onSubmit={handleLogInteraction} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <Select label="Channel" value={interaction.channel} onChange={v => setInteraction(p => ({ ...p, channel: v }))} options={CHANNEL_OPTIONS} />
              <div>
                <label style={{ fontSize: 12, fontWeight: 600, color: theme.gray700, display: 'block', marginBottom: 6 }}>Summary *</label>
                <textarea
                  value={interaction.summary}
                  onChange={e => setInteraction(p => ({ ...p, summary: e.target.value }))}
                  placeholder="What was discussed or accomplished..."
                  rows={3}
                  required
                  style={{ width: '100%', border: `1.5px solid ${theme.gray200}`, borderRadius: 'var(--radius-sm)', padding: '8px 12px', fontSize: 13, color: theme.gray900, resize: 'vertical', outline: 'none', boxSizing: 'border-box', fontFamily: 'inherit' }}
                />
              </div>
              <Input label="Outcome" value={interaction.outcome} onChange={v => setInteraction(p => ({ ...p, outcome: v }))} placeholder="e.g. Interested in attending alumni event" />
              <Input label="Follow-up Date" type="date" value={interaction.followUpAt} onChange={v => setInteraction(p => ({ ...p, followUpAt: v }))} />
              <Button label={loggingInteraction ? 'Logging...' : 'Log Interaction'} type="submit" loading={loggingInteraction} fullWidth />
            </form>
          </div>

          {/* Interaction history */}
          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', overflow: 'hidden', boxShadow: 'var(--shadow-sm)' }}>
            <div style={{ padding: '16px 24px', borderBottom: `1px solid ${theme.gray100}` }}>
              <h2 style={{ fontSize: 12, fontWeight: 700, color: theme.primary, textTransform: 'uppercase', letterSpacing: '0.8px', margin: 0 }}>
                Interaction History ({interactions.length})
              </h2>
            </div>
            {interactions.length === 0 ? (
              <div style={{ textAlign: 'center', padding: 32, color: theme.gray400, fontSize: 13 }}>No interactions logged yet</div>
            ) : (
              <div style={{ maxHeight: 480, overflowY: 'auto' }}>
                {interactions.map((it: any) => (
                  <div key={it.id} style={{ padding: '14px 24px', borderBottom: `1px solid ${theme.gray100}` }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 6 }}>
                      <Badge label={it.channel} variant="gray" />
                      <span style={{ fontSize: 11, color: theme.gray400 }}>
                        {new Date(it.loggedAt).toLocaleDateString()}
                      </span>
                    </div>
                    <p style={{ fontSize: 13, color: theme.gray800, margin: '4px 0' }}>{it.summary}</p>
                    {it.outcome && (
                      <p style={{ fontSize: 12, color: theme.gray500, margin: '2px 0 0', fontStyle: 'italic' }}>
                        Outcome: {it.outcome}
                      </p>
                    )}
                    {it.followUpAt && (
                      <p style={{ fontSize: 12, color: theme.warning, margin: '4px 0 0', fontWeight: 600 }}>
                        Follow-up: {new Date(it.followUpAt).toLocaleDateString()}
                      </p>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Edit Profile Modal */}
      {showEdit && (
        <Modal title="Edit Profile" onClose={() => setShowEdit(false)}>
          <form onSubmit={handleSave} style={{ display: 'flex', flexDirection: 'column', gap: 14, maxHeight: '70vh', overflowY: 'auto', paddingRight: 4 }}>
            <Select label="Status" value={edit.status} onChange={v => setEdit(p => ({ ...p, status: v }))} options={STATUS_OPTIONS} />

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              <Input label="Personal Email" type="email" value={edit.personalEmail} onChange={v => setEdit(p => ({ ...p, personalEmail: v }))} />
              <Input label="Phone" type="tel" value={edit.phone} onChange={v => setEdit(p => ({ ...p, phone: v }))} />
            </div>
            <Input label="LinkedIn URL" value={edit.linkedInUrl} onChange={v => setEdit(p => ({ ...p, linkedInUrl: v }))} />

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              <Input label="Employer" value={edit.currentEmployer} onChange={v => setEdit(p => ({ ...p, currentEmployer: v }))} />
              <Input label="Job Title" value={edit.currentJobTitle} onChange={v => setEdit(p => ({ ...p, currentJobTitle: v }))} />
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 12 }}>
              <Input label="City" value={edit.currentCity} onChange={v => setEdit(p => ({ ...p, currentCity: v }))} />
              <Input label="State" value={edit.currentState} onChange={v => setEdit(p => ({ ...p, currentState: v }))} />
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <input type="checkbox" id="isDonor" checked={edit.isDonor} onChange={e => setEdit(p => ({ ...p, isDonor: e.target.checked }))} style={{ width: 16, height: 16 }} />
              <label htmlFor="isDonor" style={{ fontSize: 14, color: theme.gray700, fontWeight: 500 }}>Mark as Donor</label>
            </div>
            {edit.isDonor && (
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                <Input label="Last Donation Date" type="date" value={edit.lastDonationDate} onChange={v => setEdit(p => ({ ...p, lastDonationDate: v }))} />
                <Input label="Total Donations ($)" type="number" value={edit.totalDonations} onChange={v => setEdit(p => ({ ...p, totalDonations: v }))} />
              </div>
            )}

            <div>
              <label style={{ fontSize: 12, fontWeight: 600, color: theme.gray700, display: 'block', marginBottom: 6 }}>Notes</label>
              <textarea
                value={edit.notes}
                onChange={e => setEdit(p => ({ ...p, notes: e.target.value }))}
                rows={3}
                style={{ width: '100%', border: `1.5px solid ${theme.gray200}`, borderRadius: 'var(--radius-sm)', padding: '8px 12px', fontSize: 13, color: theme.gray900, resize: 'vertical', outline: 'none', boxSizing: 'border-box', fontFamily: 'inherit' }}
              />
            </div>

            <div style={{ display: 'flex', gap: 10, paddingTop: 4 }}>
              <Button label="Cancel" variant="ghost" fullWidth onClick={() => setShowEdit(false)} />
              <Button label={saving ? 'Saving...' : 'Save Changes'} type="submit" loading={saving} fullWidth />
            </div>
          </form>
        </Modal>
      )}
    </PageLayout>
  );
}
