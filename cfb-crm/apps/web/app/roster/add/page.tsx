'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { isGlobalAdmin } from '@/lib/auth';
import { appApi, globalApi, getApiError } from '@/lib/api';
import { theme } from '@/lib/theme';
import { useTeamConfig } from '@/lib/teamConfig';
import { PageLayout, Button, Input, Select, Alert } from '@/components';

const ROLE_OPTIONS = [
  { value: 'player',   label: 'Player (roster access only)' },
  { value: 'readonly', label: 'Read Only'                   },
];

const currentYear = new Date().getFullYear();
const CLASS_OPTIONS = Array.from({ length: 8 }, (_, i) => ({
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
      <h2 style={{ fontSize: 18, fontWeight: 700, color: theme.gray900, margin: '0 0 8px' }}>Player added to roster!</h2>
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
        <Button label="Add Another" variant="outline" onClick={onDone} />
        <Button label="Back to Roster" variant="ghost" onClick={() => window.location.href = '/roster'} />
      </div>
    </div>
  );
}

export default function AddPlayerPage() {
  const router = useRouter();
  const { positions, academicYears, rosterLabel, classLabel, level } = useTeamConfig();

  useEffect(() => {
    if (!isGlobalAdmin()) router.push('/unauthorized');
  }, []);

  const POSITION_OPTIONS = positions.map(p => ({ value: p, label: p }));
  const YEAR_OPTIONS     = academicYears;
  const [saving,    setSaving]    = useState(false);
  const [alert,     setAlert]     = useState<{ msg: string; type: 'success' | 'error' | 'warning' } | null>(null);
  const [inviteUrl, setInviteUrl] = useState('');

  const emptyForm = {
    email: '', globalRole: 'player',
    firstName: '', lastName: '', jerseyNumber: '',
    position: 'QB', academicYear: 'freshman',
    recruitingClass: String(currentYear),
    heightFeet: '', heightInches: '', weightLbs: '',
    homeTown: '', homeState: '', highSchool: '',
    major: '', phone: '',
    emergencyContactName: '', emergencyContactPhone: '',
    parent1Name: '', parent1Phone: '', parent1Email: '',
    parent2Name: '', parent2Phone: '', parent2Email: '',
    notes: '',
  };
  const [form, setForm] = useState(emptyForm);
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
      // 1. Create global user account — API returns an invite token automatically
      const userRes = await globalApi.post('/users', {
        email:        form.email.trim().toLowerCase(),
        firstName:    form.firstName.trim(),
        lastName:     form.lastName.trim(),
        globalRole:   form.globalRole,
        grantAppName: 'roster',
        grantAppRole: 'player',
      });
      const { id: userId, inviteToken } = userRes.data.data;

      // 2. Create roster record
      const heightInches = form.heightFeet && form.heightInches
        ? parseInt(form.heightFeet) * 12 + parseInt(form.heightInches)
        : undefined;
      await appApi.post('/players', {
        email:                form.email.trim().toLowerCase(),
        firstName:            form.firstName.trim(),
        lastName:             form.lastName.trim(),
        jerseyNumber:         form.jerseyNumber   ? parseInt(form.jerseyNumber)  : undefined,
        position:             form.position,
        academicYear:         form.academicYear,
        recruitingClass:      parseInt(form.recruitingClass),
        heightInches,
        weightLbs:            form.weightLbs      ? parseInt(form.weightLbs)     : undefined,
        homeTown:             form.homeTown        || undefined,
        homeState:            form.homeState       || undefined,
        highSchool:           form.highSchool      || undefined,
        major:                form.major           || undefined,
        phone:                form.phone           || undefined,
        emergencyContactName: form.emergencyContactName   || undefined,
        emergencyContactPhone:form.emergencyContactPhone  || undefined,
        parent1Name:          form.parent1Name     || undefined,
        parent1Phone:         form.parent1Phone    || undefined,
        parent1Email:         form.parent1Email    || undefined,
        parent2Name:          form.parent2Name     || undefined,
        parent2Phone:         form.parent2Phone    || undefined,
        parent2Email:         form.parent2Email    || undefined,
        notes:                form.notes           || undefined,
      });

      setInviteUrl(`${window.location.origin}/invite/${inviteToken}`);
    } catch (err: unknown) {
      setAlert({ msg: getApiError(err, 'Failed to create player.'), type: 'error' });
    } finally {
      setSaving(false);
    }
  };

  if (inviteUrl) {
    return (
      <PageLayout currentPage={`${rosterLabel} / Add`}>
        <div style={{ maxWidth: 560, margin: '40px auto' }}>
          <InviteBanner inviteUrl={inviteUrl} onDone={() => { setInviteUrl(''); setForm(emptyForm); setAlert(null); }} />
        </div>
      </PageLayout>
    );
  }

  return (
    <PageLayout currentPage={`${rosterLabel} / Add`}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>Add Player</h1>
          <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>An invite link will be generated for first-time login</p>
        </div>
        <Button label="← Back to Roster" variant="outline" onClick={() => router.push('/roster')} />
      </div>

      {alert && <Alert message={alert.msg} variant={alert.type} onClose={() => setAlert(null)} />}

      <form onSubmit={handleSubmit}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>

          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Login Account" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <Input label="Email *" type="email" value={form.email} onChange={set('email')} placeholder="player@email.com" required />
              <Select label="Portal Role" value={form.globalRole} onChange={set('globalRole')} options={ROLE_OPTIONS} />
            </div>
          </div>

          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Player Identity" />
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              <Input label="First Name *" value={form.firstName} onChange={set('firstName')} required />
              <Input label="Last Name *"  value={form.lastName}  onChange={set('lastName')}  required />
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 12 }}>
              <Input label="Jersey #" type="number" value={form.jerseyNumber} onChange={set('jerseyNumber')} />
              <Select label="Position *" value={form.position} onChange={set('position')} options={POSITION_OPTIONS} />
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 12 }}>
              <Select label="Academic Year" value={form.academicYear}    onChange={set('academicYear')}    options={YEAR_OPTIONS}  />
              <Select label={classLabel}    value={form.recruitingClass} onChange={set('recruitingClass')} options={CLASS_OPTIONS} />
            </div>
          </div>

          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Physical" />
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 12 }}>
              <Input label="Height (ft)" type="number" value={form.heightFeet}   onChange={set('heightFeet')}   placeholder="6" />
              <Input label="Inches"      type="number" value={form.heightInches} onChange={set('heightInches')} placeholder="2" />
              <Input label="Weight (lbs)"type="number" value={form.weightLbs}    onChange={set('weightLbs')}    placeholder="215" />
            </div>
          </div>

          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Background" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 12 }}>
                <Input label="Hometown" value={form.homeTown}  onChange={set('homeTown')}  placeholder="Tampa" />
                <Input label="State"    value={form.homeState} onChange={set('homeState')} placeholder="FL" />
              </div>
              <Input label="High School" value={form.highSchool} onChange={set('highSchool')} />
            </div>
          </div>

          {level === 'college' && (
            <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
              <SectionHeader title="Academic" />
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                <Input label="Major" value={form.major} onChange={set('major')} placeholder="Business" />
              </div>
            </div>
          )}

          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Contact" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <Input label="Phone"             value={form.phone}                onChange={set('phone')}                type="tel" />
              <Input label="Emergency Contact" value={form.emergencyContactName} onChange={set('emergencyContactName')} />
              <Input label="Emergency Phone"   value={form.emergencyContactPhone}onChange={set('emergencyContactPhone')}type="tel" />
            </div>
          </div>

          <div style={{ gridColumn: '1 / -1', backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Parent / Guardian Contact" />
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
              <div>
                <p style={{ fontSize: 12, fontWeight: 600, color: theme.gray500, textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 10, marginTop: 0 }}>Parent / Guardian 1</p>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  <Input label="Name"  value={form.parent1Name}  onChange={set('parent1Name')}  />
                  <Input label="Phone" value={form.parent1Phone} onChange={set('parent1Phone')} type="tel" />
                  <Input label="Email" value={form.parent1Email} onChange={set('parent1Email')} type="email" />
                </div>
              </div>
              <div>
                <p style={{ fontSize: 12, fontWeight: 600, color: theme.gray500, textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 10, marginTop: 0 }}>Parent / Guardian 2</p>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  <Input label="Name"  value={form.parent2Name}  onChange={set('parent2Name')}  />
                  <Input label="Phone" value={form.parent2Phone} onChange={set('parent2Phone')} type="tel" />
                  <Input label="Email" value={form.parent2Email} onChange={set('parent2Email')} type="email" />
                </div>
              </div>
            </div>
          </div>

          <div style={{ gridColumn: '1 / -1', backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Notes" />
            <textarea
              value={form.notes}
              onChange={e => setForm(p => ({ ...p, notes: e.target.value }))}
              rows={3}
              placeholder="Any additional notes about this player..."
              style={{ width: '100%', border: `1.5px solid ${theme.gray200}`, borderRadius: 'var(--radius-sm)', padding: '10px 14px', fontSize: 14, color: theme.gray900, resize: 'vertical', outline: 'none', boxSizing: 'border-box', fontFamily: 'inherit' }}
            />
          </div>

        </div>

        <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end', marginTop: 24 }}>
          <Button label="Cancel"        variant="ghost"   onClick={() => router.push('/roster')} />
          <Button label="Add to Roster" variant="primary" type="submit" loading={saving} />
        </div>
      </form>
    </PageLayout>
  );
}
