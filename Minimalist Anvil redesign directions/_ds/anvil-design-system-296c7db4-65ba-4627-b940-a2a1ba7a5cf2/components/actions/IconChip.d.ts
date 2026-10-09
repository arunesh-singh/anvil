import * as React from 'react';

/** Rounded-square icon tile (40px box, 14px radius) used for tool glyphs,
 *  back/help buttons and row leadings. */
export interface IconChipProps {
  /** Material Icons ligature name. */
  icon: string;
  /** accent = accent container (default), neutral = surface, high = raised, solid = filled accent. */
  tone?: 'accent' | 'neutral' | 'high' | 'solid';
  /** Box size in px (40 in rows, 52 on tool headers). */
  box?: number;
  /** Glyph size in px. */
  glyph?: number;
  /** Accessible label — set when the chip is tappable. */
  label?: string;
  onClick?: () => void;
  style?: React.CSSProperties;
}

export declare function IconChip(props: IconChipProps): JSX.Element;
