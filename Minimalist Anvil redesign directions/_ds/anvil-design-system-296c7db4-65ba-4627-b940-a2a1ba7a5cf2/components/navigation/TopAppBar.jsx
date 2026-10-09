import React from 'react';
import { IconChip } from '../actions/IconChip.jsx';

/** Small top app bar: optional back arrow, title, trailing icon actions. */
export function TopAppBar({ title, onBack, actions, style, ...rest }) {
  return (
    <header
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '14px',
        height: 'var(--appbar-height)',
        padding: '0 var(--screen-padding)',
        background: 'transparent',
        color: 'var(--anvil-on-surface)',
        ...style,
      }}
      {...rest}
    >
      {onBack ? <IconChip icon="arrow_back" tone="neutral" label="Back" onClick={onBack} /> : null}
      <h1 style={{ flex: 1, margin: 0, font: 'var(--title-large)', letterSpacing: 'var(--title-large-tracking)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{title}</h1>
      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>{actions}</div>
    </header>
  );
}
