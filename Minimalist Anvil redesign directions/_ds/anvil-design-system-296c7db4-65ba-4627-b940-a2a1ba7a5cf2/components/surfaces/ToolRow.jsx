import React from 'react';
import { Icon } from '../icons/Icon.jsx';
import { IconChip } from '../actions/IconChip.jsx';

/** Tappable container row: icon chip, title, subtitle, trailing chevron.
 *  The workhorse of Home, Browse and My Files. */
export function ToolRow({ icon, leading, title, subtitle, mono = false, trailing, onClick, style, ...rest }) {
  const [hover, setHover] = React.useState(false);
  return (
    <div
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        position: 'relative',
        display: 'flex',
        alignItems: 'center',
        gap: '14px',
        padding: '13px 16px',
        borderRadius: 'var(--radius-row)',
        background: 'var(--anvil-container)',
        color: 'var(--anvil-on-surface)',
        cursor: onClick ? 'pointer' : 'default',
        transition: 'var(--transition-state)',
        ...style,
      }}
      {...rest}
    >
      {onClick ? <span style={{ position: 'absolute', inset: 0, borderRadius: 'inherit', background: 'currentColor', opacity: hover ? 0.06 : 0, pointerEvents: 'none' }} /> : null}
      {leading || (icon ? <IconChip icon={icon} /> : null)}
      <div style={{ position: 'relative', flex: 1, minWidth: 0 }}>
        <div style={{ font: 'var(--title-small)', letterSpacing: 'var(--title-small-tracking)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{title}</div>
        {subtitle ? (
          <div style={{ marginTop: '2px', font: mono ? 'var(--mono-small)' : 'var(--body-medium)', color: 'var(--anvil-muted)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{subtitle}</div>
        ) : null}
      </div>
      <div style={{ position: 'relative', display: 'flex', alignItems: 'center', gap: '6px' }}>
        {trailing === undefined ? <Icon name="chevron_right" size={20} color="var(--anvil-hint)" /> : trailing}
      </div>
    </div>
  );
}
