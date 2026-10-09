import * as React from 'react';

/**
 * Small top app bar — every Anvil screen has one and nothing else for navigation.
 */
export interface TopAppBarProps {
  /** Screen name: "Anvil", "My Files", "Settings", or the tool's label. */
  title: React.ReactNode;
  /** Supplying this renders the back arrow. */
  onBack?: () => void;
  /** `IconButton`s, trailing edge. */
  actions?: React.ReactNode;
  style?: React.CSSProperties;
}

export declare function TopAppBar(props: TopAppBarProps): JSX.Element;
