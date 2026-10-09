import * as React from 'react';

/** Transient message — "Saved report.pdf", "Output file no longer available." */
export interface SnackbarProps {
  children?: React.ReactNode;
  /** Optional single action label. */
  action?: string;
  onAction?: () => void;
  style?: React.CSSProperties;
}

export declare function Snackbar(props: SnackbarProps): JSX.Element;
