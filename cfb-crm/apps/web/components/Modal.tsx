'use client';

import React, { useEffect, useRef } from 'react';

interface ModalProps {
  title:    string;
  onClose:  () => void;
  children: React.ReactNode;
  width?:   number;
}

export default function Modal({ title, onClose, children, width = 520 }: ModalProps) {
  const dialogRef  = useRef<HTMLDivElement>(null);
  const titleId    = React.useId();

  // Close on ESC
  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', handleKey);
    return () => document.removeEventListener('keydown', handleKey);
  }, [onClose]);

  // Focus trap — keep Tab inside the modal
  useEffect(() => {
    const el = dialogRef.current;
    if (!el) return;

    const focusable = el.querySelectorAll<HTMLElement>(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    );
    const first = focusable[0];
    const last  = focusable[focusable.length - 1];

    // Move focus into modal on open
    first?.focus();

    const trap = (e: KeyboardEvent) => {
      if (e.key !== 'Tab') return;
      if (e.shiftKey) {
        if (document.activeElement === first) { e.preventDefault(); last?.focus(); }
      } else {
        if (document.activeElement === last)  { e.preventDefault(); first?.focus(); }
      }
    };
    el.addEventListener('keydown', trap);
    return () => el.removeEventListener('keydown', trap);
  }, []);

  return (
    <div
      role="presentation"
      style={{ position: 'fixed', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 200, backgroundColor: 'rgba(0,0,0,0.5)' }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        style={{
          backgroundColor: 'var(--color-card-bg)',
          borderRadius:    'var(--radius-xl)',
          padding:         32,
          width:           '100%',
          maxWidth:        width,
          maxHeight:       '90vh',
          overflowY:       'auto',
          boxShadow:       'var(--shadow-lg)',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
          <h2 id={titleId} style={{ fontSize: 20, fontWeight: 700, color: 'var(--color-gray-900)', margin: 0 }}>{title}</h2>
          <button
            onClick={onClose}
            aria-label="Close dialog"
            style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--color-gray-400)', fontSize: 24, lineHeight: 1 }}
          >
            ×
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}
