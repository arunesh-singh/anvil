import React from 'react';
import { Icon } from '../icons/Icon.jsx';

const ANVIL_BUTTON_VARIANTS = {
  filled:  { background: 'var(--anvil-accent)', color: 'var(--anvil-on-accent)' },
  neutral: { background: 'var(--anvil-container)', color: 'var(--anvil-on-surface)' },
  tonal:   { background: 'var(--anvil-accent-container)', color: 'var(--anvil-accent-text)' },
  text:    { background: 'transparent', color: 'var(--anvil-accent-text)' },
};

/** Slab action button. `filled` is the one primary action per screen (Run,
 *  Share); `neutral` is the container-coloured secondary (Stop, Swap, Add).
 *  `action` is the 60px full-bleed size the app uses at the foot of a screen. */
export function Button({ variant = 'filled', size = 'action', icon, trailingIcon, children, disabled = false, fullWidth, onClick, style, ...rest }) {
  const [hover, setHover] = React.useState(false);
  const [active, setActive] = React.useState(false);
  const v = ANVIL_BUTTON_VARIANTS[variant] || ANVIL_BUTTON_VARIANTS.filled;
  const layer = disabled ? 0 : active ? 0.1 : hover ? 0.08 : 0;
  const stretch = fullWidth === undefined ? size === 'action' : fullWidth;
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => { setHover(false); setActive(false); }}
      onMouseDown={() => setActive(true)}
      onMouseUp={() => setActive(false)}
      style={{
        position: 'relative',
        display: stretch ? 'flex' : 'inline-flex',
        width: stretch ? '100%' : undefined,
        alignItems: 'center',
        justifyContent: 'center',
        gap: '8px',
        border: 'none',
        height: size === 'action' ? 'var(--action-height)' : 'var(--touch-target)',
        padding: size === 'action' ? '0 24px' : '0 18px',
        borderRadius: size === 'action' ? 'var(--radius-button)' : 'var(--radius-control)',
        font: 'var(--label-large)',
        letterSpacing: 'var(--label-large-tracking)',
        cursor: disabled ? 'default' : 'pointer',
        transition: 'var(--transition-state)',
        WebkitTapHighlightColor: 'transparent',
        ...v,
        ...(disabled ? { background: variant === 'text' ? 'transparent' : 'var(--anvil-container-high)', color: 'var(--anvil-hint)' } : null),
        ...style,
      }}
      {...rest}
    >
      <span style={{ position: 'absolute', inset: 0, borderRadius: 'inherit', background: 'currentColor', opacity: layer, pointerEvents: 'none' }} />
      {icon ? <Icon name={icon} size={20} /> : null}
      <span style={{ position: 'relative' }}>{children}</span>
      {trailingIcon ? <Icon name={trailingIcon} size={20} style={{ position: 'relative' }} /> : null}
    </button>
  );
}
