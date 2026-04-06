'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { globalApi, getApiError } from '@/lib/api';
import { isPlatformOwner, switchTeam } from '@/lib/auth';
import { theme } from '@/lib/theme';
import { triggerThemeRefresh } from '@/components/ThemeProvider';
import { PageLayout, Button, Input, Select, Badge, Modal, Alert } from '@/components';

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
  { value: 'college',     label: 'College'     },
  { value: 'high_school', label: 'High School' },
  { value: 'club',        label: 'Club'        },
];
const TIER_OPTIONS = [
  { value: 'starter',    label: 'Starter'    },
  { value: 'pro',        label: 'Pro'        },
  { value: 'enterprise', label: 'Enterprise' },
];

interface Team {
  id: string; name: string; abbr: string;
  sport: string; level: string;
  appDb: string; dbServer: string;
  subscriptionTier: string; isActive: boolean;
  createdAt: string;
}

interface LookedUpUser {
  id: string; email: string;
  firstName: string; lastName: string;
  globalRole: string; isActive: boolean;
}

const EMPTY_FORM = {
  clientName:        '',
  clientAbbr:        '',
  appDbName:         '',
  sport:             'football',
  level:             'college',
  colorPrimary:      '#1B1B2F',
  colorAccent:       '#B8973D',
  subscriptionTier:  'starter',
  adminMode:         'new' as 'new' | 'existing',
  adminEmail:        '',
  adminPassword:     '',
  adminFirstName:    '',
  adminLastName:     '',
  existingAdminEmail: '',
};

const tierBadge = (tier: string): 'green' | 'warning' | 'gray' => {
  if (tier === 'enterprise') return 'green';
  if (tier === 'pro')        return 'warning';
  return 'gray';
};

/** Derive a safe AppDB name suggestion from abbr, e.g. "PLANT" → "PLANTApp" */
function suggestDbName(abbr: string): string {
  const safe = abbr.replace(/[^A-Za-z0-9_]/g, '');
  return safe ? `${safe}App` : '';
}

export default function PlatformAdminPage() {
  const router = useRouter();
  const [isOwner,      setIsOwner]      = useState(false);
  const [teams,        setTeams]        = useState<Team[]>([]);
  const [loading,      setLoading]      = useState(true);
  const [error,        setError]        = useState('');
  const [success,      setSuccess]      = useState('');
  const [showAddModal, setShowAddModal] = useState(false);
  const [switching,    setSwitching]    = useState<string | null>(null);

  const [form,         setForm]         = useState(EMPTY_FORM);
  const [submitting,   setSubmitting]   = useState(false);
  const [formError,    setFormError]    = useState('');

  // Existing-user lookup state
  const [lookupLoading,  setLookupLoading]  = useState(false);
  const [lookedUpUser,   setLookedUpUser]   = useState<LookedUpUser | null>(null);
  const [lookupError,    setLookupError]    = useState('');
  // Track whether the abbr was manually edited so we don't overwrite a custom DB name
  const [dbNameTouched, setDbNameTouched]   = useState(false);

  useEffect(() => {
    const owner = isPlatformOwner();
    setIsOwner(owner);
    if (!owner) { router.replace('/dashboard'); return; }
    fetchTeams();
  }, []);

  const fetchTeams = async () => {
    setLoading(true);
    try {
      const { data } = await globalApi.get('/platform/teams');
      setTeams(data.data ?? []);
    } catch {
      setError('Failed to load teams.');
    } finally {
      setLoading(false);
    }
  };

  const handleViewAsClient = async (teamId: string, teamName: string) => {
    setSwitching(teamId);
    const newConfig = await switchTeam(teamId);
    setSwitching(null);
    if (!newConfig) { setError(`Failed to switch to ${teamName}`); return; }
    triggerThemeRefresh(newConfig);
    router.push('/dashboard');
  };

  const handleToggleActive = async (team: Team) => {
    try {
      await globalApi.patch(`/platform/teams/${team.id}`, { isActive: !team.isActive });
      setSuccess(`${team.name} ${team.isActive ? 'deactivated' : 'reactivated'} successfully.`);
      fetchTeams();
    } catch {
      setError('Failed to update team status.');
    }
  };

  /** Auto-suggest DB name when abbr changes, unless the user already typed a custom one */
  const handleAbbrChange = (val: string) => {
    const upper = val.toUpperCase().replace(/[^A-Z0-9_]/g, '');
    setForm(p => ({
      ...p,
      clientAbbr: upper,
      appDbName:  dbNameTouched ? p.appDbName : suggestDbName(upper),
    }));
  };

  const handleDbNameChange = (val: string) => {
    setDbNameTouched(true);
    setForm(p => ({ ...p, appDbName: val }));
  };

  const handleLookupUser = async () => {
    setLookupError('');
    setLookedUpUser(null);
    if (!form.existingAdminEmail.trim()) { setLookupError('Enter an email to look up'); return; }
    setLookupLoading(true);
    try {
      const { data } = await globalApi.get(`/platform/users/lookup?email=${encodeURIComponent(form.existingAdminEmail.trim().toLowerCase())}`);
      setLookedUpUser(data.data);
    } catch (err: unknown) {
      const msg = getApiError(err, 'User not found');
      setLookupError(msg === 'USER_NOT_FOUND' ? 'No user found with that email address.' : msg);
    } finally {
      setLookupLoading(false);
    }
  };

  const handleAddClient = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormError('');

    if (form.adminMode === 'existing' && !lookedUpUser) {
      setFormError('Please look up and confirm the existing user before submitting.');
      return;
    }

    setSubmitting(true);
    try {
      const payload: Record<string, unknown> = {
        clientName:       form.clientName.trim(),
        clientAbbr:       form.clientAbbr.trim(),
        appDbName:        form.appDbName.trim(),
        sport:            form.sport,
        level:            form.level,
        colorPrimary:     form.colorPrimary,
        colorAccent:      form.colorAccent,
        subscriptionTier: form.subscriptionTier,
        adminMode:        form.adminMode,
      };
      if (form.adminMode === 'new') {
        payload.adminEmail      = form.adminEmail.trim().toLowerCase();
        payload.adminPassword   = form.adminPassword;
        payload.adminFirstName  = form.adminFirstName.trim();
        payload.adminLastName   = form.adminLastName.trim();
      } else {
        payload.existingAdminEmail = form.existingAdminEmail.trim().toLowerCase();
      }

      const { data } = await globalApi.post('/platform/onboard-client', payload);

      setShowAddModal(false);
      setSuccess(data.data?.message ?? `${form.clientName} provisioned successfully.`);
      resetForm();
      fetchTeams();
    } catch (err: unknown) {
      setFormError(getApiError(err, 'Failed to provision client.'));
    } finally {
      setSubmitting(false);
    }
  };

  const resetForm = () => {
    setForm(EMPTY_FORM);
    setLookedUpUser(null);
    setLookupError('');
    setDbNameTouched(false);
  };

  const setF = <K extends keyof typeof EMPTY_FORM>(k: K) => (v: string) =>
    setForm(p => ({ ...p, [k]: v }));

  if (!isOwner) return null;

  const activeCount   = teams.filter(t => t.isActive).length;
  const inactiveCount = teams.length - activeCount;

  return (
    <PageLayout currentPage="Platform Admin">

      {/* Header */}
      <div style={{ marginBottom: 24 }}>
        <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>Platform Admin</h1>
        <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>LegacyLink — all client teams</p>
      </div>

      {error   && <Alert message={error}   variant="error"   onClose={() => setError('')}   />}
      {success && <Alert message={success} variant="success" onClose={() => setSuccess('')} />}

      {/* Stats */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16, marginBottom: 28 }}>
        {[
          { label: 'Active Clients',   value: activeCount   },
          { label: 'Inactive Clients', value: inactiveCount },
          { label: 'Total Clients',    value: teams.length  },
        ].map(s => (
          <div key={s.label} style={{ backgroundColor: theme.cardBg, borderRadius: 'var(--radius-lg)', border: `1px solid ${theme.cardBorder}`, padding: '20px 24px' }}>
            <div style={{ fontSize: 28, fontWeight: 700, color: theme.primary }}>{s.value}</div>
            <div style={{ fontSize: 13, color: theme.gray500, marginTop: 4 }}>{s.label}</div>
          </div>
        ))}
      </div>

      {/* Teams table */}
      <div style={{ backgroundColor: theme.cardBg, borderRadius: 'var(--radius-lg)', border: `1px solid ${theme.cardBorder}`, overflow: 'hidden' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 20px', borderBottom: `1px solid ${theme.gray100}` }}>
          <h2 style={{ fontSize: 16, fontWeight: 600, color: theme.gray900, margin: 0 }}>Client Teams</h2>
          <Button label="+ Add New Client" onClick={() => setShowAddModal(true)} />
        </div>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ backgroundColor: theme.gray50, borderBottom: `1px solid ${theme.gray200}` }}>
              {['Team', 'Sport / Level', 'App Database', 'Tier', 'Status', 'Created', 'Actions'].map(h => (
                <th key={h} style={{ textAlign: 'left', padding: '12px 20px', fontSize: 11, fontWeight: 600, color: theme.gray500, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={7} style={{ textAlign: 'center', padding: 48, color: theme.gray400 }}>Loading...</td></tr>
            ) : teams.length === 0 ? (
              <tr><td colSpan={7} style={{ textAlign: 'center', padding: 48, color: theme.gray400 }}>No teams yet</td></tr>
            ) : teams.map((t, i) => (
              <tr key={t.id} style={{ borderBottom: `1px solid ${theme.gray100}`, backgroundColor: i % 2 === 0 ? theme.cardBg : theme.gray50 }}>
                <td style={{ padding: '14px 20px' }}>
                  <div style={{ fontWeight: 600, fontSize: 14, color: theme.gray900 }}>{t.name}</div>
                  <div style={{ fontSize: 12, color: theme.gray400 }}>{t.abbr}</div>
                </td>
                <td style={{ padding: '14px 20px', fontSize: 13, color: theme.gray600 }}>
                  <div>{t.sport}</div>
                  <div style={{ fontSize: 11, color: theme.gray400, marginTop: 2 }}>{t.level}</div>
                </td>
                <td style={{ padding: '14px 20px', fontSize: 12, color: theme.gray500, fontFamily: 'monospace' }}>
                  {t.appDb || <span style={{ color: theme.gray300, fontFamily: 'inherit' }}>—</span>}
                </td>
                <td style={{ padding: '14px 20px' }}>
                  <Badge label={t.subscriptionTier} variant={tierBadge(t.subscriptionTier)} />
                </td>
                <td style={{ padding: '14px 20px' }}>
                  <Badge label={t.isActive ? 'Active' : 'Inactive'} variant={t.isActive ? 'green' : 'gray'} />
                </td>
                <td style={{ padding: '14px 20px', fontSize: 13, color: theme.gray500 }}>
                  {new Date(t.createdAt).toLocaleDateString()}
                </td>
                <td style={{ padding: '14px 20px' }}>
                  <div style={{ display: 'flex', gap: 8 }}>
                    <Button
                      label={switching === t.id ? '...' : 'View as Client'}
                      variant="outline" size="sm"
                      disabled={!t.isActive || switching === t.id}
                      onClick={() => handleViewAsClient(t.id, t.name)}
                    />
                    <Button
                      label={t.isActive ? 'Deactivate' : 'Reactivate'}
                      variant="outline" size="sm"
                      onClick={() => handleToggleActive(t)}
                    />
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* ── Add Client Modal ─────────────────────────────────────────────────── */}
      <Modal
        isOpen={showAddModal}
        onClose={() => { setShowAddModal(false); setFormError(''); resetForm(); }}
        title="Add New Client"
        size="lg"
      >
        <form onSubmit={handleAddClient}>
          {formError && <Alert message={formError} variant="error" onClose={() => setFormError('')} />}

          {/* ── Section 1: Team Identity ──────────────────────────────────── */}
          <SectionLabel>Team Identity</SectionLabel>

          <div style={{ marginBottom: 14 }}>
            <FieldLabel>Team Name *</FieldLabel>
            <Input
              value={form.clientName}
              onChange={setF('clientName')}
              placeholder="Plant Panthers Football"
            />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginBottom: 14 }}>
            <div>
              <FieldLabel>Abbreviation * <Hint>(unique, e.g. PLANT)</Hint></FieldLabel>
              <Input
                value={form.clientAbbr}
                onChange={handleAbbrChange}
                placeholder="PLANT"
              />
            </div>
            <div>
              <FieldLabel>App Database Name * <Hint>(SQL Server DB)</Hint></FieldLabel>
              <Input
                value={form.appDbName}
                onChange={handleDbNameChange}
                placeholder="PlantPanthersApp"
              />
              {form.appDbName && !/^[A-Za-z][A-Za-z0-9_]{0,149}$/.test(form.appDbName) && (
                <p style={{ fontSize: 11, color: '#ef4444', marginTop: 3 }}>
                  Must start with a letter — letters, numbers, underscores only.
                </p>
              )}
            </div>
          </div>

          {/* ── Section 2: Sport & Subscription ──────────────────────────── */}
          <SectionLabel>Sport &amp; Subscription</SectionLabel>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 14, marginBottom: 14 }}>
            <div>
              <FieldLabel>Sport *</FieldLabel>
              <Select value={form.sport} onChange={setF('sport')} options={SPORT_OPTIONS} />
            </div>
            <div>
              <FieldLabel>Level *</FieldLabel>
              <Select value={form.level} onChange={setF('level')} options={LEVEL_OPTIONS} />
            </div>
            <div>
              <FieldLabel>Tier</FieldLabel>
              <Select value={form.subscriptionTier} onChange={setF('subscriptionTier')} options={TIER_OPTIONS} />
            </div>
          </div>

          {/* ── Section 3: Branding ───────────────────────────────────────── */}
          <SectionLabel>Branding</SectionLabel>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginBottom: 14 }}>
            <ColorField
              label="Primary Color"
              value={form.colorPrimary}
              onChange={setF('colorPrimary')}
            />
            <ColorField
              label="Accent Color"
              value={form.colorAccent}
              onChange={setF('colorAccent')}
            />
          </div>

          {/* Live preview pill */}
          <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginBottom: 20, padding: '10px 14px', borderRadius: 8, backgroundColor: theme.gray50, border: `1px solid ${theme.gray100}` }}>
            <span style={{ fontSize: 12, color: theme.gray500, fontWeight: 500 }}>Preview:</span>
            <div style={{
              padding: '4px 14px', borderRadius: 20, fontSize: 13, fontWeight: 600,
              backgroundColor: form.colorPrimary, color: form.colorAccent,
              letterSpacing: '0.3px',
            }}>
              {form.clientAbbr || 'ABBR'}
            </div>
            <div style={{
              padding: '4px 14px', borderRadius: 20, fontSize: 13, fontWeight: 600,
              backgroundColor: form.colorAccent, color: form.colorPrimary,
              letterSpacing: '0.3px',
            }}>
              {form.clientName || 'Team Name'}
            </div>
          </div>

          {/* ── Section 4: Admin Access ────────────────────────────────────── */}
          <SectionLabel>Admin Access</SectionLabel>

          {/* Toggle */}
          <div style={{ display: 'flex', gap: 0, marginBottom: 16, borderRadius: 8, border: `1px solid ${theme.gray200}`, overflow: 'hidden' }}>
            {(['new', 'existing'] as const).map(mode => (
              <button
                key={mode}
                type="button"
                onClick={() => { setForm(p => ({ ...p, adminMode: mode })); setLookedUpUser(null); setLookupError(''); }}
                style={{
                  flex: 1,
                  padding: '9px 0',
                  fontSize: 13,
                  fontWeight: 600,
                  border: 'none',
                  cursor: 'pointer',
                  backgroundColor: form.adminMode === mode ? theme.primary : theme.white,
                  color:           form.adminMode === mode ? '#ffffff'      : theme.gray500,
                  transition:      'background-color 0.15s',
                }}
              >
                {mode === 'new' ? 'Create New Account' : 'Grant Existing User'}
              </button>
            ))}
          </div>

          {form.adminMode === 'new' && (
            <>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginBottom: 14 }}>
                <div>
                  <FieldLabel>First Name *</FieldLabel>
                  <Input value={form.adminFirstName} onChange={setF('adminFirstName')} placeholder="Jane" />
                </div>
                <div>
                  <FieldLabel>Last Name *</FieldLabel>
                  <Input value={form.adminLastName} onChange={setF('adminLastName')} placeholder="Smith" />
                </div>
              </div>
              <div style={{ marginBottom: 14 }}>
                <FieldLabel>Email *</FieldLabel>
                <Input value={form.adminEmail} onChange={setF('adminEmail')} placeholder="admin@school.edu" type="email" />
              </div>
              <div style={{ marginBottom: 8 }}>
                <FieldLabel>Temporary Password * <Hint>(min 10 characters)</Hint></FieldLabel>
                <Input value={form.adminPassword} onChange={setF('adminPassword')} placeholder="••••••••••" type="password" />
              </div>
            </>
          )}

          {form.adminMode === 'existing' && (
            <div style={{ marginBottom: 8 }}>
              <FieldLabel>Existing User Email *</FieldLabel>
              <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
                <div style={{ flex: 1 }}>
                  <Input
                    value={form.existingAdminEmail}
                    onChange={v => { setF('existingAdminEmail')(v); setLookedUpUser(null); setLookupError(''); }}
                    placeholder="existing.user@email.com"
                    type="email"
                  />
                </div>
                <button
                  type="button"
                  onClick={handleLookupUser}
                  disabled={lookupLoading}
                  style={{
                    padding: '8px 16px', borderRadius: 8, fontSize: 13, fontWeight: 600,
                    backgroundColor: theme.primary, color: '#ffffff',
                    border: 'none', cursor: lookupLoading ? 'wait' : 'pointer',
                    whiteSpace: 'nowrap', flexShrink: 0,
                  }}
                >
                  {lookupLoading ? 'Looking up…' : 'Look Up'}
                </button>
              </div>

              {lookupError && (
                <p style={{ fontSize: 12, color: '#ef4444', marginTop: 6 }}>{lookupError}</p>
              )}

              {lookedUpUser && (
                <div style={{
                  marginTop: 10, padding: '12px 14px', borderRadius: 8,
                  backgroundColor: '#f0fdf4', border: '1px solid #86efac',
                  display: 'flex', alignItems: 'center', gap: 10,
                }}>
                  <span style={{ fontSize: 18 }}>✓</span>
                  <div>
                    <div style={{ fontSize: 13, fontWeight: 600, color: '#166534' }}>
                      {lookedUpUser.firstName} {lookedUpUser.lastName}
                    </div>
                    <div style={{ fontSize: 12, color: '#166534', opacity: 0.8 }}>
                      {lookedUpUser.email} · {lookedUpUser.globalRole}
                      {!lookedUpUser.isActive && ' · ⚠ Account inactive'}
                    </div>
                  </div>
                </div>
              )}

              <p style={{ fontSize: 12, color: theme.gray400, marginTop: 8 }}>
                This user will be granted <strong>global_admin</strong> access to the new team.
                They can log in immediately with their existing password.
              </p>
            </div>
          )}

          {/* Actions */}
          <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end', marginTop: 24, paddingTop: 16, borderTop: `1px solid ${theme.gray100}` }}>
            <Button
              label="Cancel"
              variant="outline"
              onClick={() => { setShowAddModal(false); setFormError(''); resetForm(); }}
            />
            <Button
              label={submitting ? 'Provisioning…' : 'Provision Client'}
              disabled={submitting}
              type="submit"
            />
          </div>
        </form>
      </Modal>

    </PageLayout>
  );
}

// ─── Small helpers ────────────────────────────────────────────────────────────

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div style={{
      fontSize: 11, fontWeight: 700, color: theme.gray500,
      textTransform: 'uppercase', letterSpacing: '0.6px',
      marginBottom: 10, marginTop: 4,
      paddingBottom: 6, borderBottom: `1px solid ${theme.gray100}`,
    }}>
      {children}
    </div>
  );
}

function FieldLabel({ children }: { children: React.ReactNode }) {
  return (
    <label style={{ fontSize: 13, fontWeight: 500, color: theme.gray700, display: 'block', marginBottom: 5 }}>
      {children}
    </label>
  );
}

function Hint({ children }: { children: React.ReactNode }) {
  return <span style={{ fontSize: 11, fontWeight: 400, color: theme.gray400 }}>{children}</span>;
}

function ColorField({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <div>
      <FieldLabel>{label}</FieldLabel>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
        <input
          type="color"
          value={value}
          onChange={e => onChange(e.target.value)}
          style={{ width: 40, height: 36, padding: 2, borderRadius: 6, border: `1px solid ${theme.gray300}`, cursor: 'pointer', flexShrink: 0 }}
        />
        <Input value={value} onChange={onChange} placeholder="#1B1B2F" />
      </div>
    </div>
  );
}
