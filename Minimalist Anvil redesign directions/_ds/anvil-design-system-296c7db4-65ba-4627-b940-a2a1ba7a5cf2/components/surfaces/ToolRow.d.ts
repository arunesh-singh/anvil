import * as React from 'react';

/** Tappable container row with an icon chip, title, subtitle and trailing slot. */
export interface ToolRowProps {
  /** Material Icons ligature for the leading chip. */
  icon?: string;
  /** Custom leading node — overrides `icon`. */
  leading?: React.ReactNode;
  title: string;
  subtitle?: string;
  /** Set the subtitle in JetBrains Mono (filenames, sizes, page counts). */
  mono?: boolean;
  /** Trailing node; omit for the default chevron, pass null for none. */
  trailing?: React.ReactNode;
  onClick?: () => void;
  style?: React.CSSProperties;
}

export declare function ToolRow(props: ToolRowProps): JSX.Element;
