import React from 'react';

/** Transient confirmation/error toast on the inverse surface. */
export function Snackbar({ children, action, onAction, style, ...rest }) {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '8px',
        minHeight: '48px',
        padding: '8px 8px 8px 16px',
        borderRadius: 'var(--radius-control)',
        background: 'var(--anvil-container-high)',
        color: 'var(--anvil-on-surface)',
        font: 'var(--body-large)',
        ...style,
      }}
      {...rest}
    >
      <span style={{ flex: 1 }}>{children}</span>
      {action ? (
        <button
          type="button"
          onClick={onAction}
          style={{ border: 'none', background: 'transparent', color: 'var(--anvil-accent-text)', font: 'var(--title-small)', padding: '0 10px', height: '36px', borderRadius: 'var(--radius-chip)', cursor: 'pointer' }}
        >
          {action}
        </button>
      ) : null}
    </div>
  );
}
