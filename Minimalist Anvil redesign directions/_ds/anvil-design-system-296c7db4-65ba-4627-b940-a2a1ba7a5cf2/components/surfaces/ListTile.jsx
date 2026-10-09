import React from 'react';
import { Icon } from '../icons/Icon.jsx';

/** `ListTile` — leading icon, title, optional 1–2 line subtitle, trailing slot. */
export function ListTile({ leadingIcon, title, subtitle, trailing, lines = 1, dense = false, onClick, style, ...rest }) {
  const [hover, setHover] = React.useState(false);
  const minHeight = lines >= 3 ? 88 : lines === 2 ? 72 : dense ? 48 : 56;
  return (
    <div
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        position: 'relative',
        display: 'flex',
        alignItems: lines > 1 ? 'flex-start' : 'center',
        gap: '16px',
        minHeight: minHeight + 'px',
        padding: lines > 1 ? '12px 16px' : '0 16px',
        color: 'var(--anvil-on-surface)',
        cursor: onClick ? 'pointer' : 'default',
        ...style,
      }}
      {...rest}
    >
      {onClick ? <span style={{ position: 'absolute', inset: 0, background: 'currentColor', opacity: hover ? 0.08 : 0, pointerEvents: 'none' }} /> : null}
      {leadingIcon ? <Icon name={leadingIcon} size={24} color="var(--anvil-icon-strong)" style={{ position: 'relative', marginTop: lines > 1 ? '2px' : 0 }} /> : null}
      <div style={{ position: 'relative', flex: 1, minWidth: 0 }}>
        <div style={{ font: 'var(--title-small)', letterSpacing: 'var(--title-small-tracking)' }}>{title}</div>
        {subtitle ? (
          <div style={{ font: 'var(--body-medium)', letterSpacing: 'var(--body-medium-tracking)', color: 'var(--anvil-muted)', whiteSpace: 'pre-line' }}>{subtitle}</div>
        ) : null}
      </div>
      {trailing ? <div style={{ position: 'relative', display: 'flex', alignItems: 'center', gap: '4px' }}>{trailing}</div> : null}
    </div>
  );
}
