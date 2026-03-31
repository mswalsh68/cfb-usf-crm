'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { isGlobalAdmin } from '@/lib/auth';
import { globalApi, appApi, getApiError } from '@/lib/api';
import { theme } from '@/lib/theme';
import { useTeamConfig } from '@/lib/teamConfig';
import { PageLayout, Button, Input, Select, Alert } from '@/components';

const ROLE_OPTIONS = [
  { value: 'readonly',    label: 'Read Only'     },
  { value: 'coach_staff', label: 'Coach / Staff' },
];

const SEMESTER_OPTIONS = [
  { value: 'spring', label: 'Spring' },
  { value: 'fall',   label: 'Fall'   },
  { value: 'summer', label: 'Summer' },
];

const currentYear = new Date().getFullYear();
const YEAR_OPTIONS = Array.from({ length: 12 }, (_, i) => ({
  value: String(currentYear - i),
  label: String(currentYear - i),
}));

function SectionHeader({ title }: { title: string }) {
  return (
    <h2 style={{
      fontSize: 12, fontWeight: 700, color: theme.primary,
      textTransform: 'uppercase', letterSpacing: '0.8px',
      marginBottom: 16, marginTop: 0,
      paddingBottom: 8, borderBottom: `2px solid ${theme.primaryLight}`,
    }}>
      {title}
    </h2>
  );
}

function InviteBanner({ inviteUrl, onDone }: { inviteUrl: string; onDone: () => void }) {
  const [copied, setCopied] = useState(false);
  const copy = () => {
    navigator.clipboard.writeText(inviteUrl);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };
  return (
    <div style={{ backgroundColor: theme.cardBg, border: `2px solid ${theme.primary}`, borderRadius: 'var(--radius-lg)', padding: 28, textAlign: 'center' }}>
      <div style={{ fontSize: 36, marginBottom: 12 }}>🎉</div>
      <h2 style={{ fontSize: 18, fontWeight: 700, color: theme.gray900, margin: '0 0 8px' }}>Alumni added!</h2>
      <p style={{ fontSize: 14, color: theme.gray600, marginBottom: 20 }}>
        Share this invite link so they can set their password and log in for the first time.
        <br /><strong>Expires in 72 hours.</strong>
      </p>
      <div style={{
        backgroundColor: theme.gray50, border: `1px solid ${theme.gray200}`,
        borderRadius: 8, padding: '10px 14px',
        fontSize: 13, color: theme.gray700,
        wordBreak: 'break-all', marginBottom: 16, textAlign: 'left',
      }}>
        {inviteUrl}
      </div>
      <div style={{ display: 'flex', gap: 10, justifyContent: 'center' }}>
        <Button label={copied ? 'Copied!' : 'Copy Invite Link'} onClick={copy} />
        <Button label="Done" variant="outline" onClick={onDone} />
      </div>
    </div>
  );
}

export default function AddAlumniPage() {
  const router = useRouter();
  const { positions, classLabel, alumniLabel } = useTeamConfig();
  const POSITION_OPTIONS = [{ value: '', label: 'No Position' }, ...positions.map(p => ({ value: p, label: p }))];

  useEffect(() => {
    if (!isGlobalAdmin()) router.push('/unauthorized');
  }, []);

  const [saving,    setSaving]    = useState(false);
  const [alert,     setAlert]     = useState<{ msg: string; type: 'success' | 'error' | 'warning' } | null>(null);
  const [inviteUrl, setInviteUrl] = useState('');

  const [form, setForm] = useState({
    email: '', globalRole: 'readonly',
    firstName: '', lastName: '',
    position: '', recruitingClass: String(currentYear),
    graduationYear: String(currentYear), graduationSemester: 'spring',
    personalEmail: '', phone: '',
    currentEmployer: '', currentJobTitle: '',
    currentCity: '', currentState: '',
    notes: '',
  });

  const set = (key: keyof typeof form) => (val: string) => setForm(p => ({ ...p, [key]: val }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.firstName.trim() || !form.lastName.trim()) {
      setAlert({ msg: 'First and last name are required.', type: 'warning' });
      return;
    }
    if (!form.email.trim()) {
      setAlert({ msg: 'Email is required to create a login account.', type: 'warning' });
      return;
    }
    setSaving(true);
    try {
      // 1. Create global user account + invite token
      const userRes = await globalApi.post('/users', {
        email:        form.email.trim().toLowerCase(),
        firstName:    form.firstName.trim(),
        lastName:     form.lastName.trim(),
        globalRole:   form.globalRole,
        grantAppName: 'alumni',
        grantAppRole: 'readonly',
      });
      const { id: userId, inviteToken } = userRes.data.data;

      // 2. Create alumni record
      await appApi.post('/alumni', {
        userId,
        firstName:          form.firstName.trim(),
        lastName:           form.lastName.trim(),
        position:           form.position           || undefined,
        recruitingClass:    parseInt(form.recruitingClass),
        graduationYear:     parseInt(form.graduationYear),
        graduationSemester: form.graduationSemester,
        personalEmail:      form.personalEmail       || undefined,
        phone:              form.phone               || undefined,
        currentEmployer:    form.currentEmployer     || undefined,
        currentJobTitle:    form.currentJobTitle     || undefined,
        currentCity:        form.currentCity         || undefined,
        currentState:       form.currentState        || undefined,
        notes:              form.notes               || undefined,
      });

      setInviteUrl(`${window.location.origin}/invite/${inviteToken}`);
    } catch (err: unknown) {
      setAlert({ msg: getApiError(err, 'Failed to create alumni.'), type: 'error' });
    } finally {
      setSaving(false);
    }
  };

  if (inviteUrl) {
    return (
      <PageLayout currentPage={`${alumniLabel} / Add`}>
        <div style={{ maxWidth: 560, margin: '40px auto' }}>
          <InviteBanner inviteUrl={inviteUrl} onDone={() => router.push('/alumni')} />
        </div>
      </PageLayout>
    );
  }

  const cardStyle = { backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' };

  return (
    <PageLayout currentPage={`${alumniLabel} / Add`}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <Button label={`← Back to ${alumniLabel}`} variant="outline" onClick={() => router.push('/alumni')} />
      </div>

      {alert && <Alert message={alert.msg} variant={alert.type} onClose={() => setAlert(null)} />}

      <form onSubmit={handleSubmit}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20, marginBottom: 20 }}>

          {/* Login Account */}
          <div style={cardStyle}>
            <SectionHeader title="Login Account" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <Input label="Email *" type="email" value={form.email} onChange={set('email')} required />
              <Select label="Global Role" value={form.globalRole} onChange={set('globalRole')} options={ROLE_OPTIONS} />
            </div>
          </div>

          {/* Identity */}
          <div style={cardStyle}>
            <SectionHeader title="Identity" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                <Input label="First Name *" value={form.firstName} onChange={set('firstName')} required />
                <Input label="Last Name *"  value={form.lastName}  onChange={set('lastName')}  required />
              </div>
              <Select label="Position"  value={form.position}        onChange={set('position')}        options={POSITION_OPTIONS} />
              <Select label={classLabel} value={form.recruitingClass} onChange={set('recruitingClass')} options={YEAR_OPTIONS} />
            </div>
          </div>

          {/* Graduation */}
          <div style={cardStyle}>
            <SectionHeader title="Graduation" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <Select label="Graduation Year"     value={form.graduationYear}     onChange={set('graduationYear')}     options={YEAR_OPTIONS} />
              <Select label="Graduation Semester" value={form.graduationSemester} onChange={set('graduationSemester')} options={SEMESTER_OPTIONS} />
            </div>
          </div>

          {/* Contact */}
          <div style={cardStyle}>
            <SectionHeader title="Contact" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <Input label="Personal Email" type="email" value={form.personalEmail} onChange={set('personalEmail')} />
              <Input label="Phone"          type="tel"  value={form.phone}          onChange={set('phone')} />
            </div>
          </div>

          {/* Career */}
          <div style={{ ...cardStyle, gridColumn: '1 / -1' }}>
            <SectionHeader title="Career (optional)" />
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              <Input label="Employer"  value={form.currentEmployer} onChange={set('currentEmployer')} />
              <Input label="Job Title" value={form.currentJobTitle} onChange={set('currentJobTitle')} />
              <Input label="City"      value={form.currentCity}     onChange={set('currentCity')} />
              <Input label="State"     value={form.currentState}    onChange={set('currentState')} />
            </div>
          </div>

        </div>

        <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end' }}>
          <Button label="Cancel"           variant="ghost"   onClick={() => router.push('/alumni')} />
          <Button label={saving ? 'Adding…' : `Add ${alumniLabel}`} type="submit" loading={saving} />
        </div>
      </form>
    </PageLayout>
  );
}
