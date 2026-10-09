import * as React from 'react';

/** Small letter-spaced section label — the system's only uppercase type. */
export interface SectionEyebrowProps {
  children?: React.ReactNode;
  /** Material Icons ligature shown before the label. */
  icon?: string;
  tone?: 'muted' | 'accent';
  style?: React.CSSProperties;
}

export declare function SectionEyebrow(props: SectionEyebrowProps): JSX.Element;
