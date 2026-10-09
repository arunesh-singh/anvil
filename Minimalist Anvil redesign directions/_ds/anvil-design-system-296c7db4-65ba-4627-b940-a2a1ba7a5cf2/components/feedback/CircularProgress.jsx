import React from 'react';

/** Indeterminate spinner — shown while History loads or a result hands off. */
export function CircularProgress({ size = 36, stroke = 4, color = 'var(--anvil-accent)', style, ...rest }) {
  return (
    <span
      role="progressbar"
      style={{ display: 'inline-block', width: size + 'px', height: size + 'px', ...style }}
      {...rest}
    >
      <style>{'@keyframes anvil-spin{to{transform:rotate(360deg)}}'}</style>
      <span
        style={{
          display: 'block',
          width: '100%',
          height: '100%',
          borderRadius: 'var(--radius-full)',
          border: stroke + 'px solid color-mix(in srgb, ' + color + ' 22%, transparent)',
          borderTopColor: color,
          animation: 'anvil-spin 1.1s linear infinite',
        }}
      />
    </span>
  );
}
