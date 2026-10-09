import * as React from 'react';

/** Filled text field — the only field style in Slab: container fill, 16px
 *  radius, no resting outline, 2px accent ring on focus. */
export interface TextFieldProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'style' | 'value'> {
  /** Label, e.g. "Image quality (1-100)". Rises to an eyebrow once filled. */
  label?: string;
  /** Placeholder, e.g. "Search tools". */
  hint?: string;
  value?: string | number;
  /** Material Icons ligature drawn inside the leading edge, e.g. "search". */
  prefixIcon?: string;
  /** Multi-line body field (set in JetBrains Mono). */
  multiline?: boolean;
  rows?: number;
  error?: boolean;
  helperText?: string;
  style?: React.CSSProperties;
}

export declare function TextField(props: TextFieldProps): JSX.Element;
