import React from 'react';
import { Icon } from '../icons/Icon.jsx';

/** Quiet informational card — accent glyph, muted body, on the info surface.
 *  Used for offline/privacy notes and tool caveats. */
export function InfoCard({ icon = 'bolt', children, style, ...rest }) {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'flex-start',
        gap: '12px',
        padding: '16px',
        borderRadius: 'var(--radius-panel)',
        background: 'var(--anvil-info)',
        ...style,
      }}
      {...rest}
    >
      <Icon name={icon} size={20} color="var(--anvil-accent)" style={{ marginTop: '1px' }} />
      <div style={{ flex: 1, minWidth: 0, font: 'var(--body-large)', color: 'var(--anvil-muted)' }}>{children}</div>
    </div>
  );
}
