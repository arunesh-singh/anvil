import * as React from 'react';

/** Persistent banner under the app bar — Anvil announces a shared file this way. */
export interface BannerProps {
  /** Material Icons ligature name. */
  icon?: string;
  children?: React.ReactNode;
  /** Text buttons, right-aligned below the message. */
  actions?: React.ReactNode;
  style?: React.CSSProperties;
}

export declare function Banner(props: BannerProps): JSX.Element;
