import * as React from 'react';

/** The job progress ring shown while a tool runs. */
export interface ProgressRingProps {
  /** 0–1 for determinate progress; omit for the rotating indeterminate arc. */
  value?: number;
  size?: number;
  stroke?: number;
  /** Centre text — the percentage, or a short status word. */
  centerLabel?: React.ReactNode;
  /** Sub-label — the gerund progress message ("Reading PDF…"). */
  subLabel?: string;
  style?: React.CSSProperties;
}

export declare function ProgressRing(props: ProgressRingProps): JSX.Element;
