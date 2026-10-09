import * as React from 'react';

/** Informational card: accent glyph plus muted body on the info surface. */
export interface InfoCardProps {
  /** Material Icons ligature; defaults to "bolt". */
  icon?: string;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}

export declare function InfoCard(props: InfoCardProps): JSX.Element;
