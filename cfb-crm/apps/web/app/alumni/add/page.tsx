'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { alumniApi } from '@/lib/api';
import { theme } from '@/lib/theme';
import { useTeamConfig } from '@/lib/teamConfig';
import { PageLayout, Button, Input, Select, Alert } from '@/components';

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

export default function AddAlumniPage() {
  const router = useRouter();
  const { positions, academicYears, alumniLabel, classLabel } = useTeamConfig();

  const POSITION_OPTIONS = [
    { value: '', label: 'Select Position' },
    ...positions.map(p => ({ value: p, label: p })),
  ];

  const [saving, setSaving] = useState(false);
  const [alert,  setAlert]  = useState<{ msg: string; type: 'success' | 'error' | 'warning' } | null>(null);

  const [form, setForm] = useState({
    firstName:          '',
    lastName:           '',
    graduationYear:     String(currentYear),
    graduationSemester: 'spring',
    position:           '',
    recruitingClass:    String(currentYear),
    personalEmail:      '',
    phone:              '',
    linkedInUrl:        '',
    currentEmployer:    '',
    currentJobTitle:    '',
    currentCity:        '',
    currentState:       '',
    isDonor:            false,
    notes:              '',
  });

  const set = (key: keyof typeof form) => (val: string | boolean) =>
    setForm(p => ({ ...p, [key]: val }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.firstName.trim() || !form.lastName.trim()) {
      setAlert({ msg: 'First and last name are required.', type: 'warning' });
      return;
    }
    setSaving(true);
    try {
      await alumniApi.post('/alumni', {
        firstName:          form.firstName.trim(),
        lastName:           form.lastName.trim(),
        graduationYear:     parseInt(form.graduationYear),
        graduationSemester: form.graduationSemester,
        position:           form.position  || undefined,
        recruitingClass:    parseInt(form.recruitingClass),
        personalEmail:      form.personalEmail   || undefined,
        phone:              form.phone           || undefined,
        linkedInUrl:        form.linkedInUrl     || undefined,
        currentEmployer:    form.currentEmployer || undefined,
        currentJobTitle:    form.currentJobTitle || undefined,
        currentCity:        form.currentCity     || undefined,
        currentState:       form.currentState    || undefined,
        isDonor:            form.isDonor,
        notes:              form.notes           || undefined,
      });
      setAlert({ msg: `${form.firstName} ${form.lastName} added to ${alumniLabel} successfully.`, type: 'success' });
      setTimeout(() => router.push('/alumni'), 1500);
    } catch (err: any) {
      setAlert({ msg: err?.response?.data?.error ?? `Failed to add ${alumniLabel.toLowerCase()}.`, type: 'error' });
    } finally {
      setSaving(false);
    }
  };

  return (
    <PageLayout currentPage={`Add ${alumniLabel}`}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>Add {alumniLabel}</h1>
          <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>Manually add a record without transferring from the roster</p>
        </div>
        <Button label={`← Back to ${alumniLabel}`} variant="outline" onClick={() => router.push('/alumni')} />
      </div>

      {alert && <Alert message={alert.msg} variant={alert.type} onClose={() => setAlert(null)} />}

      <form onSubmit={handleSubmit}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>

          {/* Identity */}
          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Identity" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                <Input label="First Name *" value={form.firstName} onChange={set('firstName')} required />
                <Input label="Last Name *"  value={form.lastName}  onChange={set('lastName')}  required />
              </div>
              <Select label="Position"  value={form.position} onChange={set('position')} options={POSITION_OPTIONS} />
            </div>
          </div>

          {/* Graduation info */}
          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Graduation" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                <Select label="Year"     value={form.graduationYear}     onChange={set('graduationYear')}     options={YEAR_OPTIONS}    />
                <Select label="Semester" value={form.graduationSemester} onChange={set('graduationSemester')} options={SEMESTER_OPTIONS} />
              </div>
              <Select label={classLabel} value={form.recruitingClass} onChange={set('recruitingClass')} options={YEAR_OPTIONS} />
            </div>
          </div>

          {/* Contact */}
          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Contact" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <Input label="Personal Email" type="email" value={form.personalEmail} onChange={set('personalEmail')} />
              <Input label="Phone" type="tel" value={form.phone} onChange={set('phone')} />
              <Input label="LinkedIn URL" value={form.linkedInUrl} onChange={set('linkedInUrl')} placeholder="https://linkedin.com/in/..." />
            </div>
          </div>

          {/* Career */}
          <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Career" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <Input label="Employer" value={form.currentEmployer} onChange={set('currentEmployer')} />
              <Input label="Job Title" value={form.currentJobTitle} onChange={set('currentJobTitle')} />
              <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 12 }}>
                <Input label="City" value={form.currentCity} onChange={set('currentCity')} />
                <Input label="State" value={form.currentState} onChange={set('currentState')} placeholder="FL" />
              </div>
            </div>
          </div>

          {/* Notes */}
          <div style={{ gridColumn: '1 / -1', backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
            <SectionHeader title="Notes" />
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
              <input
                type="checkbox"
                id="isDonor"
                checked={form.isDonor}
                onChange={e => set('isDonor')(e.target.checked)}
                style={{ width: 16, height: 16 }}
              />
              <label htmlFor="isDonor" style={{ fontSize: 14, color: theme.gray700, fontWeight: 500 }}>Mark as Donor</label>
            </div>
            <textarea
              value={form.notes}
              onChange={e => setForm(p => ({ ...p, notes: e.target.value }))}
              rows={3}
              placeholder="Any additional notes..."
              style={{ width: '100%', border: `1.5px solid ${theme.gray200}`, borderRadius: 'var(--radius-sm)', padding: '10px 14px', fontSize: 14, color: theme.gray900, resize: 'vertical', outline: 'none', boxSizing: 'border-box', fontFamily: 'inherit' }}
            />
          </div>
        </div>

        <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end', marginTop: 24 }}>
          <Button label="Cancel"        variant="ghost"   onClick={() => router.push('/alumni')} />
          <Button label={`Add ${alumniLabel}`} variant="primary" type="submit" loading={saving} />
        </div>
      </form>
    </PageLayout>
  );
}
