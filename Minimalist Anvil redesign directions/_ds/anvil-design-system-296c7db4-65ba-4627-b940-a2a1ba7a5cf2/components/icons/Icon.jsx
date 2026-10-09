import React from 'react';

/** Material Icons ligature glyph — the same set Flutter exposes as `Icons.*`. */
export function Icon({ name, size = 24, color = 'currentColor', filled = true, style, className = '', ...rest }) {
  return (
    <span
      className={('material-icons ' + className).trim()}
      aria-hidden="true"
      style={{
        fontFamily: 'var(--font-icons)',
        fontWeight: 'normal',
        fontStyle: 'normal',
        fontSize: size + 'px',
        lineHeight: 1,
        letterSpacing: 'normal',
        textTransform: 'none',
        display: 'inline-block',
        whiteSpace: 'nowrap',
        wordWrap: 'normal',
        direction: 'ltr',
        fontFeatureSettings: "'liga'",
        WebkitFontSmoothing: 'antialiased',
        color,
        opacity: filled ? 1 : 0.86,
        flex: '0 0 auto',
        ...style,
      }}
      {...rest}
    >
      {name}
    </span>
  );
}
