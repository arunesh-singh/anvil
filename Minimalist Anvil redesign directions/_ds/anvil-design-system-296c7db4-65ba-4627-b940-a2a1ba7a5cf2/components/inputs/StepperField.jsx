import React from 'react';
import { Icon } from '../icons/Icon.jsx';

/** Labelled integer stepper — `[−] value [+]` inside a panel, with optional
 *  helper text. Every numeric tool parameter uses this instead of a raw field. */
export function StepperField({ label, value = 0, min = 0, max, step = 1, unit, helperText, onChange, style, ...rest }) {
  const canDec = value > min;
  const canInc = max === undefined || value < max;
  const btn = (icon, enabled, tone, onClick) => (
    <button
      type="button"
      disabled={!enabled}
      onClick={onClick}
      style={{
        width: 'var(--touch-target)',
        height: 'var(--touch-target)',
        border: 'none',
        borderRadius: 'var(--radius-control)',
        background: tone === 'accent' ? 'var(--anvil-accent)' : 'var(--anvil-container-high)',
        color: enabled ? (tone === 'accent' ? 'var(--anvil-on-accent)' : 'var(--anvil-on-surface)') : 'var(--anvil-faint)',
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        cursor: enabled ? 'pointer' : 'default',
      }}
    >
      <Icon name={icon} size={20} />
    </button>
  );
  return (
    <div style={{ padding: '16px', borderRadius: 'var(--radius-panel)', background: 'var(--anvil-container)', color: 'var(--anvil-on-surface)', ...style }} {...rest}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
        <span style={{ flex: 1, minWidth: 0, font: 'var(--title-small)', letterSpacing: 'var(--title-small-tracking)' }}>{label}</span>
        {btn('remove', canDec, 'neutral', () => canDec && onChange && onChange(value - step))}
        <span style={{ width: '56px', textAlign: 'center', font: 'var(--title-medium)', letterSpacing: 'var(--title-medium-tracking)' }}>{value}{unit || ''}</span>
        {btn('add', canInc, 'accent', () => canInc && onChange && onChange(value + step))}
      </div>
      {helperText ? <div style={{ marginTop: '8px', font: 'var(--body-medium)', color: 'var(--anvil-muted)' }}>{helperText}</div> : null}
    </div>
  );
}
