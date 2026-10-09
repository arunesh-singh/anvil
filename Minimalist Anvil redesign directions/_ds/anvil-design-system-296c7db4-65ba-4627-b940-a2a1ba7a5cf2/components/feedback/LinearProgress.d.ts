/** Progress bar for running jobs. Omit `value` for the indeterminate phase. */
export interface LinearProgressProps {
  /** 0–1. `ToolRunning.fraction`; undefined while the engine can't estimate. */
  value?: number | null;
  style?: React.CSSProperties;
}

export declare function LinearProgress(props: LinearProgressProps): JSX.Element;
