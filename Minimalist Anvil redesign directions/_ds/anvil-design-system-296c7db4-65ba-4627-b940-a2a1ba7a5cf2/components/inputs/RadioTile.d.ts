import * as React from 'react';

/** One option row in a radio group — Anvil's Settings theme picker. */
export interface RadioTileProps {
  label: string;
  value: string;
  selected?: boolean;
  onSelect?: (value: string) => void;
  disabled?: boolean;
  style?: React.CSSProperties;
}

export declare function RadioTile(props: RadioTileProps): JSX.Element;
