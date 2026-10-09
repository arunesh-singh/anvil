import React from 'react';
import { Card } from './Card.jsx';
import { IconChip } from '../actions/IconChip.jsx';

/** The home grid unit: a 2.4:1 card holding an icon and the tool label. */
export function ToolTile({ icon, label, onClick, style, ...rest }) {
  return (
    <Card interactive onClick={onClick} radius="var(--radius-row)" style={{ aspectRatio: 'var(--tool-tile-aspect)', ...style }} {...rest}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '14px', height: '100%', padding: 'var(--tile-padding)' }}>
        <IconChip icon={icon} />
        <span style={{ font: 'var(--title-small)', letterSpacing: 'var(--title-small-tracking)', overflow: 'hidden', textOverflow: 'ellipsis' }}>{label}</span>
      </div>
    </Card>
  );
}
