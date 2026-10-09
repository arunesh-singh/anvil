import React from 'react';

/** Two-to-three option segmented toggle — the method/mode switch on the PDF
 *  tools. Selected segment is solid accent; the rest sit on the container. */
export function SegmentedControl({ options = [], value, onChange, style, ...rest }) {
  return (
    <div style={{ display: 'flex', gap: '8px', ...style }} {...rest}>
      {options.map((o) => {
        const val = typeof o === 'string' ? o : o.value;
        const label = typeof o === 'string' ? o : o.label;
        const selected = val === value;
        return (
          <button
            key={val}
            type="button"
            onClick={() => onChange && onChange(val)}
            style={{
              flex: 1,
              minWidth: 0,
              height: 'var(--control-height)',
              border: 'none',
              borderRadius: 'var(--radius-control)',
              background: selected ? 'var(--anvil-accent)' : 'var(--anvil-container)',
              color: selected ? 'var(--anvil-on-accent)' : 'var(--anvil-on-surface)',
              font: 'var(--title-small)',
              letterSpacing: 'var(--title-small-tracking)',
              cursor: 'pointer',
              transition: 'var(--transition-state)',
            }}
          >
            {label}
          </button>
        );
      })}
    </div>
  );
}
