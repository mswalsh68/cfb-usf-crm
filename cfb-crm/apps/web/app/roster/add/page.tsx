'use client';

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { isGlobalAdmin } from '@/lib/auth';
import { rosterApi, globalApi } from '@/lib/api';
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

export default function AddPlayerPage() {
  const router = useRouter();
  const { positions, academicYears, rosterLabel, classLabel } = useTeamConfig();
  const POSITION_OPTIONS = positions.map(p => ({ value: p, label: p }));
  const YEAR_OPTIONS     = academicYears;
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!isGlobalAdmin()) { router.push('/dashboard'); }
  }, []);
  const [alert,  setAlert]  = useState<{ msg: string; type: 'success' | 'error' | 'warning' } | null>(null);

  const [form, setForm] = useState({
    email: '', password: '', globalRole: 'player',
    firstName: '', lastName: '', jerseyNumber: '',
    position: 'QB', academicYear: 'freshman',
    recruitingClass: String(currentYear),
    heightFeet: '', heightInches: '', weightLbs: '',
    homeTown: '', homeState: '', highSchool: '',
    major: '', gpa: '', phone: '',
    emergencyContactName: '', emergencyContactPhone: '',
    notes: '',
  });

  const set = (key: keyof typeof form) => (val: string) =>
    setForm(p => ({ ...p, [key]: val }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.firstName.trim() || !form.lastName.trim()) {
      setAlert({ msg: 'First and last name are required.', type: 'warning' });
      return;
    }
    if (!form.email.trim() || !form.password.trim()) {
      setAlert({ msg: 'Email and password are required to create a login account.', type: 'warning' });
      return;
    }
    setSaving(true);
    try {
      const userRes = await globalApi.post('/users', {
        email:        form.email.trim().toLowerCase(),
        password:     form.password,
        firstName:    form.firstName.trim(),
        lastName:     form.lastName.trim(),
        globalRole:   form.globalRole,
        grantAppName: 'roster',
        grantAppRole: 'player',
      });
      const userId = userRes.data.data.id;
      const heightInches = form.heightFeet && form.heightInches
        ? parseInt(form.heightFeet) * 12 + parseInt(form.heightInches)
        : undefined;
      await rosterApi.post('/players', {
        userId,
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
        gpa:                  form.gpa             ? parseFloat(form.gpa)        : undefined,
        phone:                form.phone           || undefined,
        emergencyContactName: form.emergencyContactName   || undefined,
        emergencyContactPhone:form.emergencyContactPhone  || undefined,
        notes:                form.notes           || undefined,
      });
      setAlert({ msg: `${form.firstName} ${form.lastName} added to roster successfully.`, type: 'success' });
      setTimeout(() => router.push('/roster'), 1500);
    } catch (err: any) {
      setAlert({ msg: err?.response?.data?.error ?? 'Failed to create player.', type: 'error' });
    } finally {
      setSaving(false);
    }
  };

  return (
    <PageLayout currentPage="Add Player">
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>Add Player</h1>
          <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>Create a player account and roster record</p>
        </div>
        <Button label="← Back to Roster" variant="outline" onClick={() => router.push('/roster')} />
      </div>

      {alert && <Alert message={alert.msg} variant={alert.type} onClose={() => setAlert(null)} />}

      <form onSubmit={handleSubmit}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>

          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Login Account" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <Input label="Email *"    type="email"    value={form.email}    onChange={set('email')}    placeholder="player@email.com" required />
              <Input label="Password *" type="password" value={form.password} onChange={set('password')} placeholder="Min 10 characters" required helper="Player will use this to log in" />
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

          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Academic" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <Input label="Major" value={form.major} onChange={set('major')} placeholder="Business" />
              <Input label="GPA"   value={form.gpa}   onChange={set('gpa')}   placeholder="3.50" type="number" />
            </div>
          </div>

          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Contact" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <Input label="Phone"             value={form.phone}                onChange={set('phone')}                type="tel" />
              <Input label="Emergency Contact" value={form.emergencyContactName} onChange={set('emergencyContactName')} />
              <Input label="Emergency Phone"   value={form.emergencyContactPhone}onChange={set('emergencyContactPhone')}type="tel" />
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