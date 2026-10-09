import * as React from 'react';

/** Labelled integer stepper in a panel — the numeric parameter control. */
export interface StepperFieldProps {
  /** Label carries its unit in parentheses: "Image quality (1-100)". */
  label: string;
  value?: number;
  min?: number;
  max?: number;
  step?: number;
  /** Suffix rendered after the value, e.g. "%" or "pt". */
  unit?: string;
  helperText?: string;
  onChange?: (value: number) => void;
  style?: React.CSSProperties;
}

export declare function StepperField(props: StepperFieldProps): JSX.Element;
