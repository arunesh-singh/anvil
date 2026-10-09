import * as React from 'react';

/**
 * One tool in the home grid — icon plus label on a 2.4:1 card.
 */
export interface ToolTileProps {
  /** Material Icons ligature name from the tool's `ToolMeta.icon`. */
  icon: string;
  /** `ToolMeta.label`, in Title Case: "CSV to JSON", "Merge PDFs". */
  label: string;
  onClick?: () => void;
  style?: React.CSSProperties;
}

export declare function ToolTile(props: ToolTileProps): JSX.Element;
