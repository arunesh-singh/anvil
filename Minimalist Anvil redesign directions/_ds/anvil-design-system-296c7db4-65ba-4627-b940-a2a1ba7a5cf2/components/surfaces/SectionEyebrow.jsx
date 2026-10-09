import React from 'react';
import { Icon } from '../icons/Icon.jsx';

/** Letter-spaced 11px section label, optionally with a leading glyph. The only
 *  uppercase type in the system. */
export function SectionEyebrow({ children, icon, tone = 'muted', style, ...rest }) {
  const color = tone === 'accent' ? 'var(--anvil-accent-text)' : 'var(--anvil-muted)';
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', color, ...style }} {...rest}>
      {icon ? <Icon name={icon} size={15} /> : null}
      <span style={{ font: 'var(--label-small)', letterSpacing: '1px', textTransform: 'uppercase' }}>{children}</span>
    </div>
  );
}
