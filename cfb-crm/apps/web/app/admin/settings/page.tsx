'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { isGlobalAdmin } from '@/lib/auth';
import { globalApi, getApiError } from '@/lib/api';
import { theme } from '@/lib/theme';
import { applyTheme, triggerThemeRefresh } from '@/components/ThemeProvider';
import { PageLayout, Button, Input, Select, Alert } from '@/components';

const SPORT_OPTIONS = [
  { value: 'football',   label: 'Football'   },
  { value: 'basketball', label: 'Basketball' },
  { value: 'baseball',   label: 'Baseball'   },
  { value: 'soccer',     label: 'Soccer'     },
  { value: 'softball',   label: 'Softball'   },
  { value: 'volleyball', label: 'Volleyball' },
  { value: 'other',      label: 'Other'      },
];

const LEVEL_OPTIONS = [
  { value: 'college',     label: 'College / University' },
  { value: 'high_school', label: 'High School'          },
  { value: 'club',        label: 'Club / Amateur'       },
];

const DEFAULT_POSITIONS: Record<string, string[]> = {
  football:   ['QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH'],
  basketball: ['PG','SG','SF','PF','C'],
  baseball:   ['P','C','1B','2B','3B','SS','LF','CF','RF','DH'],
  soccer:     ['GK','DEF','MID','FWD'],
  softball:   ['P','C','1B','2B','3B','SS','LF','CF','RF','DP'],
  volleyball: ['S','OH','MB','RS','L','DS'],
  other:      [],
};

const DEFAULT_ACADEMIC_YEARS: Record<string, string> = {
  college:     'freshman,sophomore,junior,senior,graduate',
  high_school: '9th,10th,11th,12th',
  club:        'year1,year2,year3,year4',
};

function SectionHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div style={{ marginBottom: 16 }}>
      <h2 style={{ fontSize: 12, fontWeight: 700, color: theme.primary, textTransform: 'uppercase', letterSpacing: '0.8px', margin: 0, paddingBottom: 8, borderBottom: `2px solid ${theme.primaryLight}` }}>
        {title}
      </h2>
      {subtitle && <p style={{ fontSize: 13, color: theme.gray500, marginTop: 6, marginBottom: 0 }}>{subtitle}</p>}
    </div>
  );
}

function ColorInput({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      <label style={{ fontSize: 12, fontWeight: 600, color: theme.gray700 }}>{label}</label>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <input
          type="color"
          value={value}
          onChange={e => onChange(e.target.value)}
          style={{ width: 40, height: 36, border: `1px solid ${theme.gray200}`, borderRadius: 6, cursor: 'pointer', padding: 2 }}
        />
        <input
          type="text"
          value={value}
          onChange={e => onChange(e.target.value)}
          maxLength={7}
          pattern="^#[0-9A-Fa-f]{6}$"
          style={{ flex: 1, border: `1.5px solid ${theme.gray200}`, borderRadius: 'var(--radius-sm)', padding: '8px 12px', fontSize: 13, fontFamily: 'monospace', outline: 'none', color: theme.gray900 }}
        />
        <div style={{ width: 36, height: 36, borderRadius: 8, backgroundColor: value, border: `1px solid ${theme.gray200}`, flexShrink: 0 }} />
      </div>
    </div>
  );
}

export default function TeamSettingsPage() {
  const router = useRouter();

  const [loading,  setLoading]  = useState(true);
  const [saving,   setSaving]   = useState(false);
  const [error,    setError]    = useState('');
  const [success,  setSuccess]  = useState('');

  const [form, setForm] = useState({
    teamName:          '',
    teamAbbr:          '',
    sport:             'football',
    level:             'college',
    logoUrl:           '',
    colorPrimary:      '#006747',
    colorPrimaryDark:  '#005432',
    colorPrimaryLight: '#E0F0EA',
    colorAccent:       '#CFC493',
    colorAccentDark:   '#A89C6A',
    colorAccentLight:  '#EDEBD1',
    positionsText:     '',   // comma-separated
    academicYearsText: '',   // comma-separated values (labels editable below)
    academicYearsJson: '',   // full JSON for editing labels
    alumniLabel:       'Alumni',
    rosterLabel:       'Roster',
    classLabel:        'Recruiting Class',
  });

  useEffect(() => {
    if (!isGlobalAdmin()) { router.push('/dashboard'); return; }
    fetchConfig();
  }, []);

  const fetchConfig = async () => {
    try {
      const { data } = await globalApi.get('/config');
      const c = data.data;
      setForm(prev => ({
        ...prev,
        teamName:          c.teamName          ?? '',
        teamAbbr:          c.teamAbbr          ?? '',
        sport:             c.sport             ?? 'football',
        level:             c.level             ?? 'college',
        logoUrl:           c.logoUrl           ?? '',
        colorPrimary:      c.colorPrimary      ?? '#006747',
        colorPrimaryDark:  c.colorPrimaryDark  ?? '#005432',
        colorPrimaryLight: c.colorPrimaryLight ?? '#E0F0EA',
        colorAccent:       c.colorAccent       ?? '#CFC493',
        colorAccentDark:   c.colorAccentDark   ?? '#A89C6A',
        colorAccentLight:  c.colorAccentLight  ?? '#EDEBD1',
        positionsText:     Array.isArray(c.positions) ? c.positions.join(', ') : '',
        academicYearsJson: JSON.stringify(c.academicYears ?? [], null, 2),
        alumniLabel:       c.alumniLabel       ?? 'Alumni',
        rosterLabel:       c.rosterLabel       ?? 'Roster',
        classLabel:        c.classLabel        ?? 'Recruiting Class',
      }));
    } catch {
      setError('Failed to load team settings. Make sure the Global API is running.');
    } finally {
      setLoading(false);
    }
  };

  const applyDefaultPositions = () => {
    const defaults = DEFAULT_POSITIONS[form.sport] ?? [];
    setForm(p => ({ ...p, positionsText: defaults.join(', ') }));
  };

  const applyDefaultAcademicYears = () => {
    const csv = DEFAULT_ACADEMIC_YEARS[form.level] ?? '';
    const years = csv.split(',').map(v => ({ value: v.trim(), label: v.trim().charAt(0).toUpperCase() + v.trim().slice(1) }));
    setForm(p => ({ ...p, academicYearsJson: JSON.stringify(years, null, 2) }));
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();

    // Parse positions from comma-separated text
    const positions = form.positionsText
      .split(',')
      .map(p => p.trim().toUpperCase())
      .filter(Boolean);

    // Parse academic years from JSON
    let academicYears;
    try {
      academicYears = JSON.parse(form.academicYearsJson);
      if (!Array.isArray(academicYears)) throw new Error('Must be an array');
    } catch {
      setError('Academic years must be valid JSON: [{"value":"freshman","label":"Freshman"}, ...]');
      return;
    }

    setSaving(true);
    try {
      const newConfig = {
        teamName:          form.teamName,
        teamAbbr:          form.teamAbbr,
        sport:             form.sport,
        level:             form.level,
        logoUrl:           form.logoUrl || '',
        colorPrimary:      form.colorPrimary,
        colorPrimaryDark:  form.colorPrimaryDark,
        colorPrimaryLight: form.colorPrimaryLight,
        colorAccent:       form.colorAccent,
        colorAccentDark:   form.colorAccentDark,
        colorAccentLight:  form.colorAccentLight,
        positions,
        academicYears,
        alumniLabel:       form.alumniLabel,
        rosterLabel:       form.rosterLabel,
        classLabel:        form.classLabel,
      };
      await globalApi.patch('/config', newConfig);

      // Bust the ThemeProvider sessionStorage cache so the new config is
      // fetched fresh on next load, then apply colors immediately.
      try { sessionStorage.removeItem('cfb_team_config'); } catch { /* ignore */ }
      applyTheme(newConfig);
      triggerThemeRefresh(newConfig);

      setSuccess('Team settings saved successfully.');
    } catch (err: unknown) {
      setError(getApiError(err, 'Failed to save settings.'));
    } finally {
      setSaving(false);
    }
  };

  const set = (key: keyof typeof form) => (val: string) => setForm(p => ({ ...p, [key]: val }));

  return (
    <PageLayout currentPage="Team Settings">
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>Team Settings</h1>
          <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>Configure your portal identity, colors, positions, and terminology</p>
        </div>
        <Button label="← Back to Admin" variant="outline" onClick={() => router.push('/admin')} />
      </div>

      {error   && <Alert message={error}   variant="error"   onClose={() => setError('')}   />}
      {success && <Alert message={success} variant="success" onClose={() => setSuccess('')} />}

      {loading ? (
        <div style={{ textAlign: 'center', padding: 60, color: theme.gray400 }}>Loading...</div>
      ) : (
        <form onSubmit={handleSave}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>

            {/* Identity */}
            <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
              <SectionHeader title="Team Identity" subtitle="Your program's name and branding." />
              <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 1fr', gap: 16 }}>
                <Input label="Team / Program Name" value={form.teamName} onChange={set('teamName')} placeholder="USF Bulls" required />
                <Input label="Abbreviation" value={form.teamAbbr} onChange={set('teamAbbr')} placeholder="USF" required />
                <Select label="Sport" value={form.sport} onChange={v => { setForm(p => ({ ...p, sport: v })); }} options={SPORT_OPTIONS} />
                <Select label="Level" value={form.level} onChange={v => { setForm(p => ({ ...p, level: v })); }} options={LEVEL_OPTIONS} />
              </div>
              <div style={{ marginTop: 16 }}>
                <Input label="Logo URL (optional)" value={form.logoUrl} onChange={set('logoUrl')} placeholder="https://example.com/logo.png" helper="Leave blank to show abbreviation badge instead" />
              </div>
            </div>

            {/* Brand Colors */}
            <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
              <SectionHeader title="Brand Colors" subtitle="Six hex values control the full portal color theme." />
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16, marginBottom: 16 }}>
                <ColorInput label="Primary"       value={form.colorPrimary}      onChange={set('colorPrimary')}      />
                <ColorInput label="Primary Dark"  value={form.colorPrimaryDark}  onChange={set('colorPrimaryDark')}  />
                <ColorInput label="Primary Light" value={form.colorPrimaryLight} onChange={set('colorPrimaryLight')} />
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16 }}>
                <ColorInput label="Accent"        value={form.colorAccent}       onChange={set('colorAccent')}       />
                <ColorInput label="Accent Dark"   value={form.colorAccentDark}   onChange={set('colorAccentDark')}   />
                <ColorInput label="Accent Light"  value={form.colorAccentLight}  onChange={set('colorAccentLight')}  />
              </div>
              {/* Preview swatch */}
              <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
                {[
                  form.colorPrimary, form.colorPrimaryDark, form.colorPrimaryLight,
                  form.colorAccent,  form.colorAccentDark,  form.colorAccentLight,
                ].map((c, i) => (
                  <div key={i} style={{ flex: 1, height: 32, backgroundColor: c, borderRadius: 6, border: `1px solid ${theme.gray200}` }} title={c} />
                ))}
              </div>
            </div>

            {/* Positions */}
            <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
              <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 16 }}>
                <SectionHeader title="Positions" subtitle="Comma-separated list of valid positions for your sport." />
                <Button label="Load defaults for sport" variant="outline" size="sm" onClick={applyDefaultPositions} />
              </div>
              <input
                type="text"
                value={form.positionsText}
                onChange={e => setForm(p => ({ ...p, positionsText: e.target.value }))}
                placeholder="QB, RB, WR, TE, OL, DL, LB, DB, K, P, LS, ATH"
                style={{ width: '100%', border: `1.5px solid ${theme.gray200}`, borderRadius: 'var(--radius-sm)', padding: '10px 14px', fontSize: 13, color: theme.gray900, outline: 'none', boxSizing: 'border-box', fontFamily: 'monospace' }}
              />
              {/* Position preview pills */}
              {form.positionsText && (
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 10 }}>
                  {form.positionsText.split(',').map(p => p.trim().toUpperCase()).filter(Boolean).map(p => (
                    <span key={p} style={{ padding: '3px 10px', backgroundColor: theme.primaryLight, color: theme.primaryDark, borderRadius: 'var(--radius-full)', fontSize: 12, fontWeight: 700 }}>
                      {p}
                    </span>
                  ))}
                </div>
              )}
            </div>

            {/* Academic Years */}
            <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
              <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 16 }}>
                <SectionHeader
                  title="Academic Years"
                  subtitle={`JSON array of {value, label} pairs. College: freshman–graduate. High school: 9th–12th.`}
                />
                <Button label="Load defaults for level" variant="outline" size="sm" onClick={applyDefaultAcademicYears} />
              </div>
              <textarea
                value={form.academicYearsJson}
                onChange={e => setForm(p => ({ ...p, academicYearsJson: e.target.value }))}
                rows={8}
                spellCheck={false}
                style={{ width: '100%', border: `1.5px solid ${theme.gray200}`, borderRadius: 'var(--radius-sm)', padding: '10px 14px', fontSize: 12, color: theme.gray900, fontFamily: 'monospace', resize: 'vertical', outline: 'none', boxSizing: 'border-box' }}
              />
            </div>

            {/* Terminology */}
            <div style={{ backgroundColor: theme.cardBg, border: `1px solid ${theme.cardBorder}`, borderRadius: 'var(--radius-lg)', padding: 24, boxShadow: 'var(--shadow-sm)' }}>
              <SectionHeader title="Terminology Labels" subtitle="Customize the labels used throughout the portal." />
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16 }}>
                <Input label="Alumni Label" value={form.alumniLabel} onChange={set('alumniLabel')} placeholder="Alumni" helper='e.g. "Alumni", "Former Players", "Graduates"' />
                <Input label="Roster Label" value={form.rosterLabel} onChange={set('rosterLabel')} placeholder="Roster" helper='e.g. "Roster", "Team Roster", "Players"' />
                <Input label="Class Label"  value={form.classLabel}  onChange={set('classLabel')}  placeholder="Recruiting Class" helper='e.g. "Recruiting Class", "Graduation Year"' />
              </div>
            </div>

          </div>

          <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end', marginTop: 24 }}>
            <Button label="Cancel" variant="ghost" onClick={() => router.push('/admin')} />
            <Button label={saving ? 'Saving...' : 'Save Settings'} type="submit" loading={saving} />
          </div>
        </form>
      )}
    </PageLayout>
  );
}
