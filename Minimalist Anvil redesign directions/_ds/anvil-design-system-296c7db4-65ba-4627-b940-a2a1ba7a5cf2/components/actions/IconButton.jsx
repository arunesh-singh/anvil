import React from 'react';
import { Icon } from '../icons/Icon.jsx';

/** 48×48 icon-only tap target — app bar actions, list-tile trailing controls. */
export function IconButton({ icon, label, selected = false, disabled = false, size = 24, onClick, style, ...rest }) {
  const [hover, setHover] = React.useState(false);
  const [active, setActive] = React.useState(false);
  const layer = disabled ? 0 : active ? 0.10 : hover ? 0.08 : 0;
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => { setHover(false); setActive(false); }}
      onMouseDown={() => setActive(true)}
      onMouseUp={() => setActive(false)}
      style={{
        position: 'relative',
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        width: 'var(--touch-target)',
        height: 'var(--touch-target)',
        padding: 0,
        border: 'none',
        borderRadius: 'var(--radius-control)',
        background: selected ? 'var(--anvil-accent-container)' : 'transparent',
        color: disabled
          ? 'var(--anvil-faint)'
          : selected ? 'var(--anvil-accent-text)' : 'var(--anvil-icon-strong)',
        cursor: disabled ? 'default' : 'pointer',
        transition: 'var(--transition-state)',
        WebkitTapHighlightColor: 'transparent',
        ...style,
      }}
      {...rest}
    >
      <span style={{ position: 'absolute', inset: 0, borderRadius: 'inherit', background: 'currentColor', opacity: layer }} />
      <Icon name={icon} size={size} />
    </button>
  );
}
