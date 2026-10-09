import React from 'react';

/** `RadioListTile` — full-width row, radio on the leading edge (Android affinity). */
export function RadioTile({ label, value, selected = false, onSelect, disabled = false, style, ...rest }) {
  const [hover, setHover] = React.useState(false);
  const color = disabled
    ? 'var(--anvil-faint)'
    : selected ? 'var(--anvil-accent)' : 'var(--anvil-muted)';
  return (
    <div
      role="radio"
      aria-checked={selected}
      onClick={() => !disabled && onSelect && onSelect(value)}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        position: 'relative',
        display: 'flex',
        alignItems: 'center',
        gap: '16px',
        minHeight: '56px',
        padding: '0 16px',
        cursor: disabled ? 'default' : 'pointer',
        color: 'var(--anvil-on-surface)',
        ...style,
      }}
      {...rest}
    >
      <span style={{ position: 'absolute', inset: 0, background: 'currentColor', opacity: hover && !disabled ? 0.08 : 0 }} />
      <span style={{ position: 'relative', width: '20px', height: '20px', borderRadius: 'var(--radius-full)', border: '2px solid ' + color, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' }}>
        {selected ? <span style={{ width: '10px', height: '10px', borderRadius: 'var(--radius-full)', background: color }} /> : null}
      </span>
      <span style={{ position: 'relative', font: 'var(--body-large)', letterSpacing: 'var(--body-large-tracking)' }}>{label}</span>
    </div>
  );
}
