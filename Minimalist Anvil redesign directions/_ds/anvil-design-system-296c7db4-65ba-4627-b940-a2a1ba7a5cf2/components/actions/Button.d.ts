import * as React from 'react';

/**
 * Slab action button — the filled accent action, its neutral container
 * counterpart, and the two inline variants.
 */
export interface ButtonProps extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'style'> {
  /** filled = the one primary action. neutral = secondary. tonal/text = inline. */
  variant?: 'filled' | 'neutral' | 'tonal' | 'text';
  /** action = 60px full-bleed screen action; compact = 44px inline control. */
  size?: 'action' | 'compact';
  /** Material Icons ligature rendered before the label. */
  icon?: string;
  /** Material Icons ligature rendered after the label (Run uses arrow_forward). */
  trailingIcon?: string;
  children?: React.ReactNode;
  disabled?: boolean;
  /** Defaults to true at size="action". */
  fullWidth?: boolean;
  style?: React.CSSProperties;
}

export declare function Button(props: ButtonProps): JSX.Element;
