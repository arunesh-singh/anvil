import * as React from 'react';

export interface IconProps extends React.HTMLAttributes<HTMLSpanElement> {
  /** Material Icons ligature name, e.g. "history", "compress", "call_split". */
  name: string;
  /** Glyph size in px. Anvil uses 24 everywhere except the 20px dense tiles. */
  size?: number;
  color?: string;
  filled?: boolean;
}

export declare function Icon(props: IconProps): JSX.Element;
