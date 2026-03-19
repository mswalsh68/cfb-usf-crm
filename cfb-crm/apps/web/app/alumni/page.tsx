'use client';

import React, { useState, useRef } from 'react';
import { useRouter } from 'next/navigation';
import * as XLSX from 'xlsx';
import { alumniApi } from '@/lib/api';
import { USF } from '@/lib/theme';
import { PageLayout, Button, Alert, Badge } from '@/components';

const TEMPLATE_HEADERS = [
  'firstName', 'lastName', 'graduationYear', 'graduationSemester', 'position',
  'recruitingClass', 'personalEmail', 'phone', 'linkedInUrl',
  'currentEmployer', 'currentJobTitle', 'currentCity', 'currentState',
  'isDonor', 'notes',
];

const TEMPLATE_EXAMPLE = [
  'Michael', 'Jordan', 2018, 'spring', 'QB',
  2014, 'mjordan@gmail.com', '813-555-0200', 'linkedin.com/in/mjordan',
  'Acme Corp', 'Software Engineer', 'Tampa', 'FL',
  'No', '',
];

const VALID_POSITIONS = ['QB','RB','WR','TE','OL','DL','LB','DB','K','P','LS','ATH'];
const VALID_SEMESTERS = ['spring','fall','summer'];

export default function AlumniUploadPage() {
  const router  = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);

  const [preview,   setPreview]   = useState<any[]>([]);
  const [errors,    setErrors]    = useState<any[]>([]);
  const [fileName,  setFileName]  = useState('');
  const [uploading, setUploading] = useState(false);
  const [result,    setResult]    = useState<any>(null);
  const [alert,     setAlert]     = useState<{ msg: string; type: 'success' | 'error' | 'warning' } | null>(null);

  const downloadTemplate = () => {
    const wb = XLSX.utils.book_new();
    const ws = XLSX.utils.aoa_to_sheet([TEMPLATE_HEADERS, TEMPLATE_EXAMPLE]);
    ws['!cols'] = TEMPLATE_HEADERS.map((h) => ({ wch: Math.max(h.length + 4, 16) }));
    XLSX.utils.book_append_sheet(wb, ws, 'Alumni');
    XLSX.writeFile(wb, 'USF_Alumni_Upload_Template.xlsx');
  };

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
          setAlert({ msg: 'File is empty.', type: 'error' });
          return;
        }

        const validRows: any[] = [];
        const errorRows: any[] = [];

        rows.forEach((row, i) => {
          const rowErrors: string[] = [];
          const rowNum = i + 2;

          if (!row.firstName?.toString().trim()) rowErrors.push('First name required');
          if (!row.lastName?.toString().trim())  rowErrors.push('Last name required');
          if (!row.graduationYear || isNaN(parseInt(row.graduationYear)))
            rowErrors.push('Graduation year required');
          if (!VALID_POSITIONS.includes(row.position?.toString().toUpperCase()))
            rowErrors.push(`Invalid position "${row.position}"`);

          const semester = row.graduationSemester?.toString().toLowerCase();
          const alumni = {
            firstName:           row.firstName?.toString().trim(),
            lastName:            row.lastName?.toString().trim(),
            graduationYear:      parseInt(row.graduationYear),
            graduationSemester:  VALID_SEMESTERS.includes(semester) ? semester : 'spring',
            position:            row.position?.toString().toUpperCase(),
            recruitingClass:     row.recruitingClass ? parseInt(row.recruitingClass) : parseInt(row.graduationYear) - 4,
            personalEmail:       row.personalEmail?.toString().trim()  || undefined,
            phone:               row.phone?.toString().trim()          || undefined,
            linkedInUrl:         row.linkedInUrl?.toString().trim()    || undefined,
            currentEmployer:     row.currentEmployer?.toString().trim()|| undefined,
            currentJobTitle:     row.currentJobTitle?.toString().trim()|| undefined,
            currentCity:         row.currentCity?.toString().trim()    || undefined,
            currentState:        row.currentState?.toString().trim()   || undefined,
            isDonor:             ['yes','true','1'].includes(row.isDonor?.toString().toLowerCase()),
            notes:               row.notes?.toString().trim()          || undefined,
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
          setAlert({ msg: `${errorRows.length} row(s) have errors and will be skipped. Proceeding with ${validRows.length} valid rows.`, type: 'warning' });
        } else {
          setAlert({ msg: `${validRows.length} alumni ready to import.`, type: 'success' });
        }
      } catch {
        setAlert({ msg: 'Could not read file. Make sure it is a valid .xlsx file.', type: 'error' });
      }
    };
    reader.readAsArrayBuffer(file);
  };

  const handleUpload = async () => {
    if (preview.length === 0) return;
    setUploading(true);
    try {
      const { data } = await alumniApi.post('/alumni/bulk', {
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

      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 24, fontWeight: 700, color: USF.gray900, margin: 0 }}>Bulk Alumni Upload</h1>
          <p style={{ fontSize: 14, color: USF.gray500, marginTop: 4 }}>Upload an Excel file to import multiple alumni at once</p>
        </div>
        <Button label="← Back to Alumni" variant="outline" onClick={() => router.push('/alumni')} />
      </div>

      {alert && <Alert message={alert.msg} variant={alert.type} onClose={() => setAlert(null)} />}

      {/* Step 1 */}
      <div style={{ backgroundColor: USF.white, borderRadius: 16, border: `1px solid ${USF.cardBorder}`, padding: 24, marginBottom: 20 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <div style={{ width: 40, height: 40, borderRadius: 10, backgroundColor: USF.sand, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, flexShrink: 0 }}>1️⃣</div>
          <div style={{ flex: 1 }}>
            <h2 style={{ fontSize: 16, fontWeight: 600, color: USF.gray900, margin: 0 }}>Download the template</h2>
            <p style={{ fontSize: 13, color: USF.gray500, marginTop: 4 }}>
              Required: firstName, lastName, graduationYear, position. Semester defaults to "spring" if blank.
            </p>
          </div>
          <Button label="📥 Download Template" variant="secondary" onClick={downloadTemplate} />
        </div>
        <div style={{ marginTop: 16, padding: 16, backgroundColor: USF.gray50, borderRadius: 10 }}>
          <p style={{ fontSize: 12, fontWeight: 600, color: USF.gray500, marginBottom: 8, textTransform: 'uppercase', letterSpacing: '0.5px' }}>Columns</p>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            {TEMPLATE_HEADERS.map((h) => (
              <span key={h} style={{ fontSize: 12, padding: '3px 8px', backgroundColor: USF.white, border: `1px solid ${USF.gray200}`, borderRadius: 6, color: USF.gray700, fontFamily: 'monospace' }}>
                {h}
              </span>
            ))}
          </div>
          <p style={{ fontSize: 12, color: USF.gray400, marginTop: 8 }}>
            isDonor: Yes/No &nbsp;|&nbsp; graduationSemester: spring, fall, summer &nbsp;|&nbsp; Position: {VALID_POSITIONS.join(', ')}
          </p>
        </div>
      </div>

      {/* Step 2 */}
      <div style={{ backgroundColor: USF.white, borderRadius: 16, border: `1px solid ${USF.cardBorder}`, padding: 24, marginBottom: 20 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 16 }}>
          <div style={{ width: 40, height: 40, borderRadius: 10, backgroundColor: USF.sand, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, flexShrink: 0 }}>2️⃣</div>
          <div>
            <h2 style={{ fontSize: 16, fontWeight: 600, color: USF.gray900, margin: 0 }}>Upload your file</h2>
            <p style={{ fontSize: 13, color: USF.gray500, marginTop: 4 }}>Select your filled-in Excel file (.xlsx)</p>
          </div>
        </div>
        <div
          onClick={() => fileRef.current?.click()}
          style={{ border: `2px dashed ${USF.gray300}`, borderRadius: 12, padding: 40, textAlign: 'center', cursor: 'pointer', backgroundColor: USF.gray50, transition: 'border-color 0.15s' }}
          onMouseEnter={e => (e.currentTarget.style.borderColor = USF.evergreen)}
          onMouseLeave={e => (e.currentTarget.style.borderColor = USF.gray300)}
        >
          <div style={{ fontSize: 36, marginBottom: 12 }}>📊</div>
          <p style={{ fontSize: 15, fontWeight: 600, color: USF.gray700, margin: 0 }}>
            {fileName ? fileName : 'Click to select your Excel file'}
          </p>
          <p style={{ fontSize: 13, color: USF.gray400, marginTop: 6 }}>.xlsx files only — max 500 alumni per upload</p>
          <input ref={fileRef} type="file" accept=".xlsx,.xls" onChange={handleFile} style={{ display: 'none' }} />
        </div>
      </div>

      {/* Step 3: Review */}
      {(preview.length > 0 || errors.length > 0) && (
        <div style={{ backgroundColor: USF.white, borderRadius: 16, border: `1px solid ${USF.cardBorder}`, padding: 24, marginBottom: 20 }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
              <div style={{ width: 40, height: 40, borderRadius: 10, backgroundColor: USF.sand, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, flexShrink: 0 }}>3️⃣</div>
              <div>
                <h2 style={{ fontSize: 16, fontWeight: 600, color: USF.gray900, margin: 0 }}>Review & confirm</h2>
                <p style={{ fontSize: 13, color: USF.gray500, marginTop: 4 }}>{preview.length} valid · {errors.length} with errors</p>
              </div>
            </div>
            <Button label={uploading ? 'Uploading...' : `Upload ${preview.length} Alumni`} loading={uploading} disabled={preview.length === 0} onClick={handleUpload} />
          </div>

          {errors.length > 0 && (
            <div style={{ marginBottom: 16 }}>
              <p style={{ fontSize: 12, fontWeight: 600, color: USF.danger, textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 8 }}>Rows with errors</p>
              {errors.map((e) => (
                <div key={e.rowNum} style={{ backgroundColor: USF.dangerLight, borderRadius: 8, padding: '8px 12px', marginBottom: 6, fontSize: 13 }}>
                  <span style={{ fontWeight: 600, color: USF.danger }}>Row {e.rowNum} — {e.name}: </span>
                  <span style={{ color: USF.danger }}>{e.errors.join(', ')}</span>
                </div>
              ))}
            </div>
          )}

          {preview.length > 0 && (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
                <thead>
                  <tr style={{ backgroundColor: USF.gray50, borderBottom: `1px solid ${USF.gray200}` }}>
                    {['Row','Name','Grad Year','Semester','Position','Employer','City'].map(h => (
                      <th key={h} style={{ textAlign: 'left', padding: '8px 12px', fontWeight: 600, color: USF.gray500, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.5px' }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {preview.slice(0, 20).map((a, i) => (
                    <tr key={i} style={{ borderBottom: `1px solid ${USF.gray100}`, backgroundColor: i % 2 === 0 ? USF.white : USF.gray50 }}>
                      <td style={{ padding: '7px 12px', color: USF.gray400 }}>{a._rowNum}</td>
                      <td style={{ padding: '7px 12px', fontWeight: 500, color: USF.gray900 }}>{a.lastName}, {a.firstName}</td>
                      <td style={{ padding: '7px 12px', color: USF.gray600 }}>{a.graduationYear}</td>
                      <td style={{ padding: '7px 12px', color: USF.gray600, textTransform: 'capitalize' }}>{a.graduationSemester}</td>
                      <td style={{ padding: '7px 12px' }}><Badge label={a.position} variant="gold" /></td>
                      <td style={{ padding: '7px 12px', color: USF.gray600 }}>{a.currentEmployer ?? '—'}</td>
                      <td style={{ padding: '7px 12px', color: USF.gray600 }}>{a.currentCity && a.currentState ? `${a.currentCity}, ${a.currentState}` : '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {preview.length > 20 && (
                <p style={{ fontSize: 13, color: USF.gray400, textAlign: 'center', padding: 12 }}>Showing first 20 of {preview.length}</p>
              )}
            </div>
          )}
        </div>
      )}

      {/* Result */}
      {result && (
        <div style={{ backgroundColor: USF.white, borderRadius: 16, border: `1px solid ${USF.cardBorder}`, padding: 24 }}>
          <h2 style={{ fontSize: 16, fontWeight: 600, color: USF.gray900, marginBottom: 16 }}>Upload Result</h2>
          <div style={{ display: 'flex', gap: 16, marginBottom: 16 }}>
            <div style={{ flex: 1, backgroundColor: USF.greenLight, borderRadius: 12, padding: 16, textAlign: 'center' }}>
              <div style={{ fontSize: 32, fontWeight: 700, color: USF.green }}>{result.inserted}</div>
              <div style={{ fontSize: 13, color: USF.evergreen }}>Alumni imported</div>
            </div>
            <div style={{ flex: 1, backgroundColor: USF.dangerLight, borderRadius: 12, padding: 16, textAlign: 'center' }}>
              <div style={{ fontSize: 32, fontWeight: 700, color: USF.danger }}>{result.skipped}</div>
              <div style={{ fontSize: 13, color: USF.danger }}>Skipped</div>
            </div>
          </div>
          <Button label="View Alumni" onClick={() => router.push('/alumni')} />
        </div>
      )}

    </PageLayout>
  );
}