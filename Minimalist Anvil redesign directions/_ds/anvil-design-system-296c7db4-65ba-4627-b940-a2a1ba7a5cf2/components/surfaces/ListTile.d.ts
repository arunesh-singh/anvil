import * as React from 'react';

/** Row primitive for History and Result lists. */
export interface ListTileProps extends Omit<React.HTMLAttributes<HTMLDivElement>, 'style' | 'title'> {
  /** Material Icons ligature name. */
  leadingIcon?: string;
  title: React.ReactNode;
  /** Second (and third) line; newline-separated text is preserved. */
  subtitle?: React.ReactNode;
  trailing?: React.ReactNode;
  /** 1 → 56px, 2 → 72px, 3 → 88px, matching Flutter's isThreeLine. */
  lines?: 1 | 2 | 3;
  dense?: boolean;
  style?: React.CSSProperties;
}

export declare function ListTile(props: ListTileProps): JSX.Element;
