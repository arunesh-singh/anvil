import * as React from 'react';

/** Icon-only 48×48 action, matching Flutter's `IconButton` with a tooltip. */
export interface IconButtonProps extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'style'> {
  /** Material Icons ligature name, e.g. "history", "settings", "open_in_new". */
  icon: string;
  /** Tooltip + accessible name. Flutter always passes `tooltip:`; so should you. */
  label?: string;
  selected?: boolean;
  disabled?: boolean;
  size?: number;
  style?: React.CSSProperties;
}

export declare function IconButton(props: IconButtonProps): JSX.Element;
