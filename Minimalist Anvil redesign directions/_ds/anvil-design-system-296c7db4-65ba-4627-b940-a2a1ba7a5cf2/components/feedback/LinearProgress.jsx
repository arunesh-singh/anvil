import React from 'react';

/** 4px determinate/indeterminate bar — the tool-run progress indicator. */
export function LinearProgress({ value, style, ...rest }) {
  const indeterminate = value === undefined || value === null;
  return (
    <div
      role="progressbar"
      style={{ position: 'relative', width: '100%', height: '4px', overflow: 'hidden', borderRadius: 'var(--radius-full)', background: 'var(--anvil-accent-container)', ...style }}
      {...rest}
    >
      <style>{'@keyframes anvil-indeterminate{0%{left:-35%;right:100%}60%{left:100%;right:-90%}100%{left:100%;right:-90%}}'}</style>
      <div
        style={
          indeterminate
            ? { position: 'absolute', top: 0, bottom: 0, background: 'var(--anvil-accent)', animation: 'anvil-indeterminate 2s var(--easing-legacy) infinite' }
            : { position: 'absolute', top: 0, bottom: 0, left: 0, width: Math.max(0, Math.min(1, value)) * 100 + '%', background: 'var(--anvil-accent)', transition: 'width var(--duration-medium-2) var(--easing-standard)' }
        }
      />
    </div>
  );
}
