'use client';

import React, { useEffect, useState, useRef } from 'react';
import { useRouter } from 'next/navigation';
import * as XLSX from 'xlsx';
import { isGlobalAdmin } from '@/lib/auth';
import { appApi } from '@/lib/api';
import { theme } from '@/lib/theme';
import { PageLayout, Button, Alert, Badge } from '@/components';

// ─── Template columns ─────────────────────────────────────────
const TEMPLATE_HEADERS = [
  'firstName', 'lastName', 'position', 'recruitingClass',
  'graduationYear', 'graduationSemester',
  'email', 'phone', 'major', 'homeTown', 'homeState', 'highSchool', 'notes',
];

const TEMPLATE_EXAMPLE = [
  'James', 'Brown', 'QB', 2019,
  2023, 'spring',
  'james.brown@email.com', '813-555-0100', 'Business', 'Tampa', 'FL', 'Plant High School', '',
];

const VALID_POSITIONS  = ['QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH'];
const VALID_SEMESTERS  = ['spring','fall','summer'];

export default function AlumniUploadPage() {
  const router  = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!isGlobalAdmin()) router.push('/unauthorized');
  }, []);

  const [preview,   setPreview]   = useState<any[]>([]);
  const [errors,    setErrors]    = useState<any[]>([]);
  const [fileName,  setFileName]  = useState('');
  const [uploading, setUploading] = useState(false);
  const [result,    setResult]    = useState<any>(null);
  const [alert,     setAlert]     = useState<{ msg: string; type: 'success' | 'error' | 'warning' } | null>(null);

  // ─── Download template ──────────────────────────────────────
  const downloadTemplate = () => {
    const wb = XLSX.utils.book_new();
    const ws = XLSX.utils.aoa_to_sheet([TEMPLATE_HEADERS, TEMPLATE_EXAMPLE]);
    ws['!cols'] = TEMPLATE_HEADERS.map((h) => ({ wch: Math.max(h.length + 4, 14) }));
    XLSX.utils.book_append_sheet(wb, ws, 'Alumni');
    XLSX.writeFile(wb, 'Alumni_Upload_Template.xlsx');
  };

  // ─── Parse uploaded file ─────────────────────────────────────
  const handleFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setFileName(file.name);
    setResult(null);
    setAlert(null);

    const reader = new FileReader();
    reader.onload = (ev) => {
      try {
        const data = new Uint8Array(ev.target!.result as ArrayBuffer);
        const wb   = XLSX.read(data, { type: 'array' });
        const ws   = wb.Sheets[wb.SheetNames[0]];
        const rows = XLSX.utils.sheet_to_json(ws, { defval: '' }) as any[];

        if (rows.length === 0) {
          setAlert({ msg: 'File is empty or has no data rows.', type: 'error' });
          return;
        }

        const validRows: any[] = [];
        const errorRows: any[] = [];

        rows.forEach((row, i) => {
          const rowErrors: string[] = [];
          const rowNum = i + 2;

          if (!row.firstName?.toString().trim())  rowErrors.push('First name required');
          if (!row.lastName?.toString().trim())   rowErrors.push('Last name required');
          if (!VALID_POSITIONS.includes(row.position?.toString().toUpperCase()))
            rowErrors.push(`Invalid position "${row.position}" — must be one of: ${VALID_POSITIONS.join(', ')}`);
          if (!row.graduationYear || isNaN(parseInt(row.graduationYear)))
            rowErrors.push('Graduation year required');
          const sem = row.graduationSemester?.toString().toLowerCase();
          if (!VALID_SEMESTERS.includes(sem))
            rowErrors.push(`Graduation semester must be: ${VALID_SEMESTERS.join(', ')}`);

          const alumni = {
            firstName:           row.firstName?.toString().trim(),
            lastName:            row.lastName?.toString().trim(),
            position:            row.position?.toString().toUpperCase(),
            recruitingClass:     row.recruitingClass ? parseInt(row.recruitingClass) : undefined,
            graduationYear:      parseInt(row.graduationYear),
            graduationSemester:  sem,
            email:               row.email?.toString().trim()      || undefined,
            phone:               row.phone?.toString().trim()      || undefined,
            major:               row.major?.toString().trim()      || undefined,
            homeTown:            row.homeTown?.toString().trim()   || undefined,
            homeState:           row.homeState?.toString().trim()  || undefined,
            highSchool:          row.highSchool?.toString().trim() || undefined,
            notes:               row.notes?.toString().trim()      || undefined,
            _rowNum: rowNum,
          };

          if (rowErrors.length > 0) {
            errorRows.push({ rowNum, name: `${row.firstName} ${row.lastName}`, errors: rowErrors });
          } else {
            validRows.push(alumni);
          }
        });

        setPreview(validRows);
        setErrors(errorRows);

        if (errorRows.length > 0) {
          setAlert({ msg: `${errorRows.length} row(s) have errors and will be skipped. Fix them in the file and re-upload, or proceed with ${validRows.length} valid rows.`, type: 'warning' });
        } else {
          setAlert({ msg: `${validRows.length} alumni ready to import. Review below and click Upload.`, type: 'success' });
        }
      } catch {
        setAlert({ msg: 'Could not read file. Make sure it is a valid .xlsx file.', type: 'error' });
      }
    };
    reader.readAsArrayBuffer(file);
  };

  // ─── Submit to API ───────────────────────────────────────────
  const handleUpload = async () => {
    if (preview.length === 0) return;
    setUploading(true);
    try {
      const { data } = await appApi.post('/alumni/bulk', {
        alumni: preview.map(({ _rowNum, ...a }) => a),
      });
      setResult(data.data);
      setPreview([]);
      setAlert({
        msg: `Done! ${data.data.inserted} alumni imported, ${data.data.skipped} skipped.`,
        type: data.data.skipped > 0 ? 'warning' : 'success',
      });
    } catch (err: any) {
      setAlert({ msg: err?.response?.data?.error ?? 'Upload failed', type: 'error' });
    } finally {
      setUploading(false);
    }
  };

  return (
    <PageLayout currentPage="Alumni Upload">

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: theme.gray900, margin: 0 }}>Bulk Alumni Upload</h1>
          <p style={{ fontSize: 14, color: theme.gray500, marginTop: 4 }}>Upload an Excel file to import multiple alumni at once</p>
        </div>
        <Button label="← Back to Alumni" variant="outline" onClick={() => router.push('/alumni')} />
      </div>

      {alert && <Alert message={alert.msg} variant={alert.type} onClose={() => setAlert(null)} />}

      {/* Step 1: Download template */}
      <div style={{ backgroundColor: theme.white, borderRadius: 16, border: `1px solid ${theme.cardBorder}`, padding: 24, marginBottom: 20 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <div style={{ width: 40, height: 40, borderRadius: 10, backgroundColor: theme.primaryLight, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, flexShrink: 0 }}>1️⃣</div>
          <div style={{ flex: 1 }}>
            <h2 style={{ fontSize: 16, fontWeight: 600, color: theme.gray900, margin: 0 }}>Download the template</h2>
            <p style={{ fontSize: 13, color: theme.gray500, marginTop: 4 }}>
              Fill in the Excel template with your alumni data. Required columns: firstName, lastName, position, graduationYear, graduationSemester.
            </p>
          </div>
          <Button label="📥 Download Template" variant="secondary" onClick={downloadTemplate} />
        </div>

        <div style={{ marginTop: 16, padding: 16, backgroundColor: theme.gray50, borderRadius: 10 }}>
          <p style={{ fontSize: 12, fontWeight: 600, color: theme.gray500, marginBottom: 8, textTransform: 'uppercase', letterSpacing: '0.5px' }}>Column reference</p>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            {TEMPLATE_HEADERS.map((h) => (
              <span key={h} style={{ fontSize: 12, padding: '3px 8px', backgroundColor: theme.white, border: `1px solid ${theme.gray200}`, borderRadius: 6, color: theme.gray700, fontFamily: 'monospace' }}>
                {h}
              </span>
            ))}
          </div>
          <p style={{ fontSize: 12, color: theme.gray400, marginTop: 8 }}>
            Position must be one of: {VALID_POSITIONS.join(', ')} &nbsp;|&nbsp;
            Graduation semester: {VALID_SEMESTERS.join(', ')}
          </p>
        </div>
      </div>

      {/* Step 2: Upload file */}
      <div style={{ backgroundColor: theme.white, borderRadius: 16, border: `1px solid ${theme.cardBorder}`, padding: 24, marginBottom: 20 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 16 }}>
          <div style={{ width: 40, height: 40, borderRadius: 10, backgroundColor: theme.primaryLight, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, flexShrink: 0 }}>2️⃣</div>
          <div>
            <h2 style={{ fontSize: 16, fontWeight: 600, color: theme.gray900, margin: 0 }}>Upload your file</h2>
            <p style={{ fontSize: 13, color: theme.gray500, marginTop: 4 }}>Select your filled-in Excel file (.xlsx)</p>
          </div>
        </div>

        <div
          onClick={() => fileRef.current?.click()}
          style={{
            border: `2px dashed ${theme.gray300}`,
            borderRadius: 12,
            padding: 40,
            textAlign: 'center',
            cursor: 'pointer',
            transition: 'border-color 0.15s',
            backgroundColor: theme.gray50,
          }}
          onMouseEnter={e => (e.currentTarget.style.borderColor = theme.primary)}
          onMouseLeave={e => (e.currentTarget.style.borderColor = theme.gray300)}
        >
          <div style={{ fontSize: 36, marginBottom: 12 }}>🎓</div>
          <p style={{ fontSize: 15, fontWeight: 600, color: theme.gray700, margin: 0 }}>
            {fileName ? fileName : 'Click to select your Excel file'}
          </p>
          <p style={{ fontSize: 13, color: theme.gray400, marginTop: 6 }}>
            .xlsx files only — max 500 alumni per upload
          </p>
          <input ref={fileRef} type="file" accept=".xlsx,.xls" onChange={handleFile} style={{ display: 'none' }} />
        </div>
      </div>

      {/* Step 3: Review & upload */}
      {(preview.length > 0 || errors.length > 0) && (
        <div style={{ backgroundColor: theme.white, borderRadius: 16, border: `1px solid ${theme.cardBorder}`, padding: 24, marginBottom: 20 }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
              <div style={{ width: 40, height: 40, borderRadius: 10, backgroundColor: theme.primaryLight, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, flexShrink: 0 }}>3️⃣</div>
              <div>
                <h2 style={{ fontSize: 16, fontWeight: 600, color: theme.gray900, margin: 0 }}>Review & confirm</h2>
                <p style={{ fontSize: 13, color: theme.gray500, marginTop: 4 }}>
                  {preview.length} valid · {errors.length} with errors
                </p>
              </div>
            </div>
            <Button
              label={uploading ? 'Uploading...' : `Upload ${preview.length} Alumni`}
              loading={uploading}
              disabled={preview.length === 0}
              onClick={handleUpload}
            />
          </div>

          {errors.length > 0 && (
            <div style={{ marginBottom: 16 }}>
              <p style={{ fontSize: 12, fontWeight: 600, color: theme.danger, textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 8 }}>
                Rows with errors (will be skipped)
              </p>
              {errors.map((e) => (
                <div key={e.rowNum} style={{ backgroundColor: theme.dangerLight, borderRadius: 8, padding: '8px 12px', marginBottom: 6, fontSize: 13 }}>
                  <span style={{ fontWeight: 600, color: theme.danger }}>Row {e.rowNum} — {e.name}: </span>
                  <span style={{ color: theme.danger }}>{e.errors.join(', ')}</span>
                </div>
              ))}
            </div>
          )}

          {preview.length > 0 && (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
                <thead>
                  <tr style={{ backgroundColor: theme.gray50, borderBottom: `1px solid ${theme.gray200}` }}>
                    {['Row', 'Name', 'Position', 'Class', 'Graduated', 'Hometown'].map(h => (
                      <th key={h} style={{ textAlign: 'left', padding: '8px 12px', fontWeight: 600, color: theme.gray500, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.5px' }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {preview.slice(0, 20).map((a, i) => (
                    <tr key={i} style={{ borderBottom: `1px solid ${theme.gray100}`, backgroundColor: i % 2 === 0 ? theme.white : theme.gray50 }}>
                      <td style={{ padding: '7px 12px', color: theme.gray400 }}>{a._rowNum}</td>
                      <td style={{ padding: '7px 12px', fontWeight: 500, color: theme.gray900 }}>{a.lastName}, {a.firstName}</td>
                      <td style={{ padding: '7px 12px' }}><Badge label={a.position} variant="green" /></td>
                      <td style={{ padding: '7px 12px', color: theme.gray600 }}>{a.recruitingClass ?? '—'}</td>
                      <td style={{ padding: '7px 12px', color: theme.gray600, textTransform: 'capitalize' }}>{a.graduationSemester} {a.graduationYear}</td>
                      <td style={{ padding: '7px 12px', color: theme.gray600 }}>{a.homeTown && a.homeState ? `${a.homeTown}, ${a.homeState}` : '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {preview.length > 20 && (
                <p style={{ fontSize: 13, color: theme.gray400, textAlign: 'center', padding: 12 }}>
                  Showing first 20 of {preview.length} alumni
                </p>
              )}
            </div>
          )}
        </div>
      )}

      {/* Result */}
      {result && (
        <div style={{ backgroundColor: theme.white, borderRadius: 16, border: `1px solid ${theme.cardBorder}`, padding: 24 }}>
          <h2 style={{ fontSize: 16, fontWeight: 600, color: theme.gray900, marginBottom: 16 }}>Upload Result</h2>
          <div style={{ display: 'flex', gap: 16, marginBottom: 16 }}>
            <div style={{ flex: 1, backgroundColor: theme.primaryLight, borderRadius: 12, padding: 16, textAlign: 'center' }}>
              <div style={{ fontSize: 32, fontWeight: 700, color: theme.primary }}>{result.inserted}</div>
              <div style={{ fontSize: 13, color: theme.primaryDark }}>Alumni imported</div>
            </div>
            <div style={{ flex: 1, backgroundColor: theme.dangerLight, borderRadius: 12, padding: 16, textAlign: 'center' }}>
              <div style={{ fontSize: 32, fontWeight: 700, color: theme.danger }}>{result.skipped}</div>
              <div style={{ fontSize: 13, color: theme.danger }}>Skipped</div>
            </div>
          </div>
          {result.errors?.length > 0 && (
            <>
              <p style={{ fontSize: 12, fontWeight: 600, color: theme.danger, textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 8 }}>Skip reasons</p>
              {result.errors.map((e: any, i: number) => (
                <div key={i} style={{ backgroundColor: theme.dangerLight, borderRadius: 8, padding: '6px 12px', marginBottom: 4, fontSize: 13, color: theme.danger }}>
                  Row {e.rowNum}: {e.reason}
                </div>
              ))}
            </>
          )}
          <div style={{ marginTop: 16 }}>
            <Button label="View Alumni" onClick={() => router.push('/alumni')} />
          </div>
        </div>
      )}

    </PageLayout>
  );
}
