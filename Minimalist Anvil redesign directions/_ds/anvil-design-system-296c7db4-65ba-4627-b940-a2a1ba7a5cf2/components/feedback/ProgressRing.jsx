import React from 'react';

/** The 200px job ring: determinate when `value` is set, a rotating arc when
 *  it is not. Centre label is the percentage, sub-label the progress message. */
export function ProgressRing({ value, size = 200, stroke = 14, centerLabel, subLabel, style, ...rest }) {
  const indeterminate = value === undefined || value === null;
  const r = (size - stroke) / 2;
  const circumference = 2 * Math.PI * r;
  const frac = indeterminate ? 0.25 : Math.max(0, Math.min(1, value));
  return (
    <div role="progressbar" style={{ position: 'relative', width: size + 'px', height: size + 'px', ...style }} {...rest}>
      <style>{'@keyframes anvil-ring-spin{to{transform:rotate(360deg)}}'}</style>
      <svg
        width={size}
        height={size}
        style={{ display: 'block', transform: 'rotate(-90deg)', animation: indeterminate ? 'anvil-ring-spin 1.2s linear infinite' : 'none', transformOrigin: '50% 50%' }}
      >
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--anvil-accent-container)" strokeWidth={stroke} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke="var(--anvil-accent)"
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={circumference * (1 - frac)}
          style={{ transition: indeterminate ? 'none' : 'stroke-dashoffset var(--duration-medium-2) var(--easing-standard)' }}
        />
      </svg>
      <div style={{ position: 'absolute', inset: stroke + 'px', borderRadius: 'var(--radius-full)', background: 'var(--anvil-bg)', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '4px', padding: '0 24px', textAlign: 'center' }}>
        <span style={{ font: 'var(--headline-medium)', letterSpacing: 'var(--headline-medium-tracking)', color: 'var(--anvil-on-surface)' }}>{centerLabel}</span>
        {subLabel ? <span style={{ font: 'var(--body-medium)', color: 'var(--anvil-muted)' }}>{subLabel}</span> : null}
      </div>
    </div>
  );
}
