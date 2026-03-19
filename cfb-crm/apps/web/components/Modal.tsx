'use client';

import { USF } from '@/lib/theme';

interface ModalProps {
  title:     string;
  onClose:   () => void;
  children:  React.ReactNode;
  width?:    number;
}

export default function Modal({ title, onClose, children, width = 520 }: ModalProps) {
  return (
    <div
      className="fixed inset-0 flex items-center justify-center z-50"
      style={{ backgroundColor: 'rgba(0,0,0,0.5)' }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div
        style={{
          backgroundColor: USF.white,
          borderRadius:    20,
          padding:         32,
          width:           '100%',
          maxWidth:        width,
          maxHeight:       '90vh',
          overflowY:       'auto',
          boxShadow:       '0 20px 60px rgba(0,0,0,0.2)',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
          <h2 style={{ fontSize: 20, fontWeight: 700, color: USF.gray900, margin: 0 }}>{title}</h2>
          <button
            onClick={onClose}
            style={{ fontSize: 24, color: USF.gray400, background: 'none', border: 'none', cursor: 'pointer', lineHeight: 1 }}
          >
            ×
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}
