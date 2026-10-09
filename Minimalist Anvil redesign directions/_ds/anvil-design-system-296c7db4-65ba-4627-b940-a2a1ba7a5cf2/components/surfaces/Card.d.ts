import * as React from 'react';

/** Flat tinted container ("SlabPanel"). Content is clipped to the corner. */
export interface CardProps extends Omit<React.HTMLAttributes<HTMLDivElement>, 'style'> {
  /** Tint level 0–5: 0 = page, 1–2 = container, 3–5 = raised container. */
  level?: 0 | 1 | 2 | 3 | 4 | 5;
  /** Adds the hover/press state layer for tappable panels. */
  interactive?: boolean;
  /** Corner radius; defaults to the 22px panel radius. */
  radius?: string;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}

export declare function Card(props: CardProps): JSX.Element;
