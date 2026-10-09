import * as React from 'react';

/** Segmented two/three-way toggle used for tool modes (Optimize / Rasterize). */
export interface SegmentedControlProps {
  /** Labels, or {value,label} pairs. */
  options?: Array<string | { value: string; label: string }>;
  value?: string;
  onChange?: (value: string) => void;
  style?: React.CSSProperties;
}

export declare function SegmentedControl(props: SegmentedControlProps): JSX.Element;
