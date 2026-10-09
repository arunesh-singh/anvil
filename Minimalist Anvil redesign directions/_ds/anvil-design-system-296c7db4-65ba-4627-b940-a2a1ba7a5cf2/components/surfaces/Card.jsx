import React from 'react';

/** Slab panel: a flat tinted container at the 22px panel radius. Depth is
 *  tint, never shadow — level 1 is the container colour, level 3 the raised one. */
export function Card({ level = 1, interactive = false, radius = 'var(--radius-panel)', onClick, children, style, ...rest }) {
  const [hover, setHover] = React.useState(false);
  return (
    <div
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        position: 'relative',
        overflow: 'hidden',
        background: 'var(--surface-level-' + level + ')',
        color: 'var(--anvil-on-surface)',
        borderRadius: radius,
        cursor: interactive ? 'pointer' : 'default',
        transition: 'var(--transition-state)',
        ...style,
      }}
      {...rest}
    >
      {interactive ? <span style={{ position: 'absolute', inset: 0, background: 'currentColor', opacity: hover ? 0.06 : 0, pointerEvents: 'none' }} /> : null}
      {children}
    </div>
  );
}
