import React from 'react';
import { Icon } from '../icons/Icon.jsx';

/** `MaterialBanner` — a persistent, dismissable message pinned under the app bar. */
export function Banner({ icon, children, actions, style, ...rest }) {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'flex-start',
        gap: '16px',
        padding: '16px',
        borderRadius: 'var(--radius-panel)',
        background: 'var(--anvil-container)',
        color: 'var(--anvil-on-surface)',
        ...style,
      }}
      {...rest}
    >
      {icon ? <Icon name={icon} size={24} color="var(--anvil-accent)" style={{ marginTop: '2px' }} /> : null}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ font: 'var(--body-large)', color: 'var(--anvil-muted)' }}>{children}</div>
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '8px', marginTop: '8px' }}>{actions}</div>
      </div>
    </div>
  );
}
