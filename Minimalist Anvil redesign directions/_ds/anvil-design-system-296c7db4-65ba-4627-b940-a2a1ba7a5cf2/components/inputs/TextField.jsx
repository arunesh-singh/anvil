import React from 'react';
import { Icon } from '../icons/Icon.jsx';

/** Filled text field — Slab's only field style: container fill, 16px radius,
 *  no resting outline, a 2px accent ring on focus. */
export function TextField({ label, hint, value, defaultValue, prefixIcon, error, helperText, type = 'text', multiline = false, rows = 4, onChange, style, ...rest }) {
  const [focus, setFocus] = React.useState(false);
  const [inner, setInner] = React.useState(defaultValue ?? '');
  const val = value !== undefined ? value : inner;
  const filled = String(val ?? '').length > 0;
  const showLabel = label && (focus || filled);
  const Field = multiline ? 'textarea' : 'input';
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', ...style }}>
      <div
        style={{
          display: 'flex',
          alignItems: multiline ? 'flex-start' : 'center',
          gap: '12px',
          minHeight: '56px',
          padding: showLabel ? '8px 16px' : '0 16px',
          borderRadius: 'var(--radius-search)',
          background: 'var(--anvil-container)',
          boxShadow: focus ? 'inset 0 0 0 2px var(--anvil-accent)' : error ? 'inset 0 0 0 2px var(--anvil-error)' : 'none',
          transition: 'var(--transition-state)',
        }}
      >
        {prefixIcon ? <Icon name={prefixIcon} size={22} color="var(--anvil-hint)" style={{ marginTop: multiline ? '10px' : 0 }} /> : null}
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: showLabel ? 0 : '8px 0' }}>
          {showLabel ? (
            <span style={{ font: 'var(--label-small)', letterSpacing: 'var(--label-small-tracking)', textTransform: 'uppercase', color: error ? 'var(--anvil-error)' : focus ? 'var(--anvil-accent-text)' : 'var(--anvil-muted)' }}>{label}</span>
          ) : null}
          <Field
            type={multiline ? undefined : type}
            rows={multiline ? rows : undefined}
            value={val}
            placeholder={hint || label}
            onFocus={() => setFocus(true)}
            onBlur={() => setFocus(false)}
            onChange={(e) => { setInner(e.target.value); onChange && onChange(e); }}
            style={{
              width: '100%',
              border: 'none',
              outline: 'none',
              resize: multiline ? 'vertical' : undefined,
              background: 'transparent',
              font: multiline ? 'var(--mono-medium)' : 'var(--body-large)',
              color: 'var(--anvil-on-surface)',
              padding: 0,
            }}
            {...rest}
          />
        </div>
      </div>
      {helperText ? (
        <span style={{ font: 'var(--body-medium)', color: error ? 'var(--anvil-error)' : 'var(--anvil-muted)', paddingLeft: '16px' }}>{helperText}</span>
      ) : null}
    </div>
  );
}
