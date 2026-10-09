import React from 'react';
import { Icon } from '../icons/Icon.jsx';

/** Rounded-square icon tile — the app's most repeated ornament: tool glyphs,
 *  back buttons, row leadings. Accent-container by default, neutral when
 *  `tone="neutral"`. */
export function IconChip({ icon, tone = 'accent', box = 40, glyph = 20, label, onClick, style, ...rest }) {
  const [hover, setHover] = React.useState(false);
  const tones = {
    accent: { background: 'var(--anvil-accent-container)', color: 'var(--anvil-accent-text)' },
    neutral: { background: 'var(--anvil-container)', color: 'var(--anvil-icon-strong)' },
    high: { background: 'var(--anvil-container-high)', color: 'var(--anvil-icon-strong)' },
    solid: { background: 'var(--anvil-accent)', color: 'var(--anvil-on-accent)' },
  };
  return (
    <span
      role={onClick ? 'button' : undefined}
      aria-label={label}
      title={label}
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        position: 'relative',
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        flex: '0 0 auto',
        width: box + 'px',
        height: box + 'px',
        borderRadius: 'var(--radius-control)',
        cursor: onClick ? 'pointer' : 'default',
        transition: 'var(--transition-state)',
        ...(tones[tone] || tones.accent),
        ...style,
      }}
      {...rest}
    >
      <span style={{ position: 'absolute', inset: 0, borderRadius: 'inherit', background: 'currentColor', opacity: onClick && hover ? 0.08 : 0 }} />
      <Icon name={icon} size={glyph} style={{ position: 'relative' }} />
    </span>
  );
}
