'use client';

import React from 'react';

interface ModalProps {
  title:    string;
  onClose:  () => void;
  children: React.ReactNode;
  width?:   number;
}

export default function Modal({ title, onClose, children, width = 520 }: ModalProps) {
  return (
    <div
      style={{ position: 'fixed', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 200, backgroundColor: 'rgba(0,0,0,0.5)' }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div style={{
        backgroundColor: 'var(--color-card-bg)',
        borderRadius:    'var(--radius-xl)',
        padding:         32,
        width:           '100%',
        maxWidth:        width,
        maxHeight:       '90vh',
        overflowY:       'auto',
        boxShadow:       'var(--shadow-lg)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
          <h2 style={{ fontSize: 20, fontWeight: 700, color: 'var(--color-gray-900)', margin: 0 }}>{title}</h2>
          <button onClick={onClose} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--color-gray-400)', fontSize: 24, lineHeight: 1 }}>×</button>
        </div>
        {children}
      </div>
    </div>
  );
}