/* @ds-bundle: {"format":4,"namespace":"AnvilDesignSystem_296c7d","components":[{"name":"Button","sourcePath":"components/actions/Button.jsx"},{"name":"IconButton","sourcePath":"components/actions/IconButton.jsx"},{"name":"Banner","sourcePath":"components/feedback/Banner.jsx"},{"name":"CircularProgress","sourcePath":"components/feedback/CircularProgress.jsx"},{"name":"LinearProgress","sourcePath":"components/feedback/LinearProgress.jsx"},{"name":"Snackbar","sourcePath":"components/feedback/Snackbar.jsx"},{"name":"Icon","sourcePath":"components/icons/Icon.jsx"},{"name":"RadioTile","sourcePath":"components/inputs/RadioTile.jsx"},{"name":"TextField","sourcePath":"components/inputs/TextField.jsx"},{"name":"TopAppBar","sourcePath":"components/navigation/TopAppBar.jsx"},{"name":"Card","sourcePath":"components/surfaces/Card.jsx"},{"name":"ListTile","sourcePath":"components/surfaces/ListTile.jsx"},{"name":"ToolTile","sourcePath":"components/surfaces/ToolTile.jsx"}],"sourceHashes":{"components/actions/Button.jsx":"dc13df12f914","components/actions/IconButton.jsx":"c6ca3b924efc","components/feedback/Banner.jsx":"c6dd2cfdc17b","components/feedback/CircularProgress.jsx":"adfdb4459a18","components/feedback/LinearProgress.jsx":"ef437c09c83f","components/feedback/Snackbar.jsx":"41563ebc1e36","components/icons/Icon.jsx":"769dec2a898a","components/inputs/RadioTile.jsx":"e21f8c344d43","components/inputs/TextField.jsx":"893415af052f","components/navigation/TopAppBar.jsx":"dd505146af88","components/surfaces/Card.jsx":"a7d61896a612","components/surfaces/ListTile.jsx":"6de10b603a35","components/surfaces/ToolTile.jsx":"33059c626946","ui_kits/anvil-app/App.jsx":"c2bd89b79f6c","ui_kits/anvil-app/HistoryScreen.jsx":"de3184b55f0c","ui_kits/anvil-app/HomeScreen.jsx":"8e37682afa30","ui_kits/anvil-app/ResultScreen.jsx":"9558995e8e04","ui_kits/anvil-app/SettingsScreen.jsx":"7543d3b47e55","ui_kits/anvil-app/ToolScreen.jsx":"fac0344125bd","ui_kits/anvil-app/data.js":"bf3db236a6c5"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.AnvilDesignSystem_296c7d = window.AnvilDesignSystem_296c7d || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/feedback/CircularProgress.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Indeterminate spinner — shown while History loads or a result hands off. */
function CircularProgress({
  size = 36,
  stroke = 4,
  color = 'var(--md-primary)',
  style,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("span", _extends({
    role: "progressbar",
    style: {
      display: 'inline-block',
      width: size + 'px',
      height: size + 'px',
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("style", null, '@keyframes anvil-spin{to{transform:rotate(360deg)}}'), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'block',
      width: '100%',
      height: '100%',
      borderRadius: 'var(--corner-full)',
      border: stroke + 'px solid color-mix(in srgb, ' + color + ' 22%, transparent)',
      borderTopColor: color,
      animation: 'anvil-spin 1.1s linear infinite'
    }
  }));
}
Object.assign(__ds_scope, { CircularProgress });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/CircularProgress.jsx", error: String((e && e.message) || e) }); }

// components/feedback/LinearProgress.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** 4px determinate/indeterminate bar — the tool-run progress indicator. */
function LinearProgress({
  value,
  style,
  ...rest
}) {
  const indeterminate = value === undefined || value === null;
  return /*#__PURE__*/React.createElement("div", _extends({
    role: "progressbar",
    style: {
      position: 'relative',
      width: '100%',
      height: '4px',
      overflow: 'hidden',
      borderRadius: 'var(--corner-full)',
      background: 'var(--md-surface-container-highest)',
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("style", null, '@keyframes anvil-indeterminate{0%{left:-35%;right:100%}60%{left:100%;right:-90%}100%{left:100%;right:-90%}}'), /*#__PURE__*/React.createElement("div", {
    style: indeterminate ? {
      position: 'absolute',
      top: 0,
      bottom: 0,
      background: 'var(--md-primary)',
      animation: 'anvil-indeterminate 2s var(--easing-legacy) infinite'
    } : {
      position: 'absolute',
      top: 0,
      bottom: 0,
      left: 0,
      width: Math.max(0, Math.min(1, value)) * 100 + '%',
      background: 'var(--md-primary)',
      transition: 'width var(--duration-medium-2) var(--easing-standard)'
    }
  }));
}
Object.assign(__ds_scope, { LinearProgress });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/LinearProgress.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Snackbar.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Transient confirmation/error toast on the inverse surface. */
function Snackbar({
  children,
  action,
  onAction,
  style,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '8px',
      minHeight: '48px',
      padding: '8px 8px 8px 16px',
      borderRadius: 'var(--corner-extra-small)',
      background: 'var(--md-inverse-surface)',
      color: 'var(--md-inverse-on-surface)',
      boxShadow: 'var(--elevation-3)',
      font: 'var(--body-medium)',
      letterSpacing: 'var(--body-medium-tracking)',
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }, children), action ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onAction,
    style: {
      border: 'none',
      background: 'transparent',
      color: 'var(--md-inverse-primary)',
      font: 'var(--label-large)',
      letterSpacing: 'var(--label-large-tracking)',
      padding: '0 8px',
      height: '32px',
      borderRadius: 'var(--corner-full)',
      cursor: 'pointer'
    }
  }, action) : null);
}
Object.assign(__ds_scope, { Snackbar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Snackbar.jsx", error: String((e && e.message) || e) }); }

// components/icons/Icon.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Material Icons ligature glyph — the same set Flutter exposes as `Icons.*`. */
function Icon({
  name,
  size = 24,
  color = 'currentColor',
  filled = true,
  style,
  className = '',
  ...rest
}) {
  return /*#__PURE__*/React.createElement("span", _extends({
    className: ('material-icons ' + className).trim(),
    "aria-hidden": "true",
    style: {
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
      ...style
    }
  }, rest), name);
}
Object.assign(__ds_scope, { Icon });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/icons/Icon.jsx", error: String((e && e.message) || e) }); }

// components/actions/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const VARIANTS = {
  filled: {
    background: 'var(--md-primary)',
    color: 'var(--md-on-primary)',
    border: 'none',
    boxShadow: 'var(--elevation-0)'
  },
  tonal: {
    background: 'var(--md-secondary-container)',
    color: 'var(--md-on-secondary-container)',
    border: 'none',
    boxShadow: 'var(--elevation-0)'
  },
  outlined: {
    background: 'transparent',
    color: 'var(--md-primary)',
    border: '1px solid var(--md-outline)',
    boxShadow: 'none'
  },
  text: {
    background: 'transparent',
    color: 'var(--md-primary)',
    border: 'none',
    boxShadow: 'none'
  },
  elevated: {
    background: 'var(--md-surface-container-low)',
    color: 'var(--md-primary)',
    border: 'none',
    boxShadow: 'var(--elevation-1)'
  }
};

/** M3 common button. Anvil uses `filled` for Run/Share, `outlined` for
 *  Cancel/Pick file/Done, `text` for banner actions. */
function Button({
  variant = 'filled',
  icon,
  children,
  disabled = false,
  fullWidth = false,
  onClick,
  style,
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const [active, setActive] = React.useState(false);
  const v = VARIANTS[variant] || VARIANTS.filled;
  const layer = disabled ? 0 : active ? 0.10 : hover ? 0.08 : 0;
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    disabled: disabled,
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => {
      setHover(false);
      setActive(false);
    },
    onMouseDown: () => setActive(true),
    onMouseUp: () => setActive(false),
    style: {
      position: 'relative',
      display: fullWidth ? 'flex' : 'inline-flex',
      width: fullWidth ? '100%' : undefined,
      alignItems: 'center',
      justifyContent: 'center',
      gap: '8px',
      height: '40px',
      padding: variant === 'text' ? '0 12px' : icon ? '0 24px 0 16px' : '0 24px',
      borderRadius: 'var(--radius-button)',
      font: 'var(--label-large)',
      letterSpacing: 'var(--label-large-tracking)',
      cursor: disabled ? 'default' : 'pointer',
      transition: 'var(--transition-state)',
      WebkitTapHighlightColor: 'transparent',
      ...v,
      ...(disabled ? {
        background: variant === 'filled' || variant === 'tonal' || variant === 'elevated' ? 'color-mix(in srgb, var(--md-on-surface) 12%, transparent)' : 'transparent',
        color: 'color-mix(in srgb, var(--md-on-surface) 38%, transparent)',
        border: variant === 'outlined' ? '1px solid color-mix(in srgb, var(--md-on-surface) 12%, transparent)' : v.border,
        boxShadow: 'none'
      } : null),
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      inset: 0,
      borderRadius: 'inherit',
      background: 'currentColor',
      opacity: layer,
      pointerEvents: 'none'
    }
  }), icon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 18
  }) : null, /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'relative'
    }
  }, children));
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/actions/Button.jsx", error: String((e && e.message) || e) }); }

// components/actions/IconButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** 48×48 icon-only tap target — app bar actions, list-tile trailing controls. */
function IconButton({
  icon,
  label,
  selected = false,
  disabled = false,
  size = 24,
  onClick,
  style,
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const [active, setActive] = React.useState(false);
  const layer = disabled ? 0 : active ? 0.10 : hover ? 0.08 : 0;
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    title: label,
    "aria-label": label,
    disabled: disabled,
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => {
      setHover(false);
      setActive(false);
    },
    onMouseDown: () => setActive(true),
    onMouseUp: () => setActive(false),
    style: {
      position: 'relative',
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: 'var(--touch-target)',
      height: 'var(--touch-target)',
      padding: 0,
      border: 'none',
      borderRadius: 'var(--corner-full)',
      background: selected ? 'var(--md-secondary-container)' : 'transparent',
      color: disabled ? 'color-mix(in srgb, var(--md-on-surface) 38%, transparent)' : selected ? 'var(--md-on-secondary-container)' : 'var(--md-on-surface-variant)',
      cursor: disabled ? 'default' : 'pointer',
      transition: 'var(--transition-state)',
      WebkitTapHighlightColor: 'transparent',
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      inset: 0,
      borderRadius: 'inherit',
      background: 'currentColor',
      opacity: layer
    }
  }), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: size
  }));
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/actions/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Banner.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** `MaterialBanner` — a persistent, dismissable message pinned under the app bar. */
function Banner({
  icon,
  children,
  actions,
  style,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      display: 'flex',
      alignItems: 'flex-start',
      gap: '16px',
      padding: '16px 16px 8px 16px',
      background: 'var(--md-surface)',
      color: 'var(--md-on-surface)',
      borderBottom: '1px solid var(--md-outline-variant)',
      ...style
    }
  }, rest), icon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 24,
    color: "var(--md-on-surface-variant)",
    style: {
      marginTop: '2px'
    }
  }) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: 'var(--body-medium)',
      letterSpacing: 'var(--body-medium-tracking)'
    }
  }, children), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'flex-end',
      gap: '8px',
      marginTop: '8px'
    }
  }, actions)));
}
Object.assign(__ds_scope, { Banner });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Banner.jsx", error: String((e && e.message) || e) }); }

// components/inputs/RadioTile.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** `RadioListTile` — full-width row, radio on the leading edge (Android affinity). */
function RadioTile({
  label,
  value,
  selected = false,
  onSelect,
  disabled = false,
  style,
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const color = disabled ? 'color-mix(in srgb, var(--md-on-surface) 38%, transparent)' : selected ? 'var(--md-primary)' : 'var(--md-on-surface-variant)';
  return /*#__PURE__*/React.createElement("div", _extends({
    role: "radio",
    "aria-checked": selected,
    onClick: () => !disabled && onSelect && onSelect(value),
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: 'center',
      gap: '16px',
      minHeight: '56px',
      padding: '0 16px',
      cursor: disabled ? 'default' : 'pointer',
      color: 'var(--md-on-surface)',
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      inset: 0,
      background: 'currentColor',
      opacity: hover && !disabled ? 0.08 : 0
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'relative',
      width: '20px',
      height: '20px',
      borderRadius: 'var(--corner-full)',
      border: '2px solid ' + color,
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      flex: '0 0 auto'
    }
  }, selected ? /*#__PURE__*/React.createElement("span", {
    style: {
      width: '10px',
      height: '10px',
      borderRadius: 'var(--corner-full)',
      background: color
    }
  }) : null), /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'relative',
      font: 'var(--body-large)',
      letterSpacing: 'var(--body-large-tracking)'
    }
  }, label));
}
Object.assign(__ds_scope, { RadioTile });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/inputs/RadioTile.jsx", error: String((e && e.message) || e) }); }

// components/inputs/TextField.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Outlined text field — Flutter's `InputDecoration(border: OutlineInputBorder())`,
 *  the only field style Anvil uses (search + every tool param). */
function TextField({
  label,
  hint,
  value,
  defaultValue,
  prefixIcon,
  error,
  helperText,
  type = 'text',
  onChange,
  style,
  ...rest
}) {
  const [focus, setFocus] = React.useState(false);
  const [inner, setInner] = React.useState(defaultValue ?? '');
  const val = value !== undefined ? value : inner;
  const floated = focus || String(val ?? '').length > 0;
  const line = error ? 'var(--md-error)' : focus ? 'var(--md-primary)' : 'var(--md-outline)';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: '4px',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: 'center',
      gap: '12px',
      minHeight: '56px',
      padding: prefixIcon ? '0 16px 0 12px' : '0 16px',
      borderRadius: 'var(--radius-field)',
      border: (focus ? '2px solid ' : '1px solid ') + line,
      background: 'transparent',
      transition: 'var(--transition-state)'
    }
  }, prefixIcon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: prefixIcon,
    size: 24,
    color: "var(--md-on-surface-variant)"
  }) : null, label ? /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      left: prefixIcon ? '48px' : '16px',
      top: floated ? '-8px' : '50%',
      transform: floated ? 'none' : 'translateY(-50%)',
      padding: floated ? '0 4px' : 0,
      background: floated ? 'var(--md-surface)' : 'transparent',
      font: floated ? 'var(--body-small)' : 'var(--body-large)',
      letterSpacing: floated ? 'var(--body-small-tracking)' : 'var(--body-large-tracking)',
      color: error ? 'var(--md-error)' : focus ? 'var(--md-primary)' : 'var(--md-on-surface-variant)',
      pointerEvents: 'none',
      transition: 'all var(--duration-short-4) var(--easing-standard)'
    }
  }, label) : null, /*#__PURE__*/React.createElement("input", _extends({
    type: type,
    value: val,
    placeholder: label && !floated ? '' : hint,
    onFocus: () => setFocus(true),
    onBlur: () => setFocus(false),
    onChange: e => {
      setInner(e.target.value);
      onChange && onChange(e);
    },
    style: {
      flex: 1,
      minWidth: 0,
      border: 'none',
      outline: 'none',
      background: 'transparent',
      font: 'var(--body-large)',
      letterSpacing: 'var(--body-large-tracking)',
      color: 'var(--md-on-surface)',
      padding: 0
    }
  }, rest))), helperText ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--body-small)',
      letterSpacing: 'var(--body-small-tracking)',
      color: error ? 'var(--md-error)' : 'var(--md-on-surface-variant)',
      paddingLeft: '16px'
    }
  }, helperText) : null);
}
Object.assign(__ds_scope, { TextField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/inputs/TextField.jsx", error: String((e && e.message) || e) }); }

// components/navigation/TopAppBar.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Small top app bar: optional back arrow, title, trailing icon actions. */
function TopAppBar({
  title,
  onBack,
  actions,
  style,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("header", _extends({
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '4px',
      height: 'var(--appbar-height)',
      padding: '0 4px',
      background: 'var(--md-surface)',
      color: 'var(--md-on-surface)',
      ...style
    }
  }, rest), onBack ? /*#__PURE__*/React.createElement(__ds_scope.IconButton, {
    icon: "arrow_back",
    label: "Back",
    onClick: onBack
  }) : /*#__PURE__*/React.createElement("span", {
    style: {
      width: '12px'
    }
  }), /*#__PURE__*/React.createElement("h1", {
    style: {
      flex: 1,
      margin: 0,
      font: 'var(--title-large)',
      letterSpacing: 'var(--title-large-tracking)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, title), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '0px'
    }
  }, actions));
}
Object.assign(__ds_scope, { TopAppBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/TopAppBar.jsx", error: String((e && e.message) || e) }); }

// components/surfaces/Card.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** M3 card: tinted surface container + level-1 shadow, 12px corners. */
function Card({
  level = 1,
  interactive = false,
  onClick,
  children,
  style,
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", _extends({
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      position: 'relative',
      overflow: 'hidden',
      background: 'var(--surface-level-' + level + ')',
      color: 'var(--md-on-surface)',
      borderRadius: 'var(--radius-card)',
      boxShadow: 'var(--elevation-' + level + ')',
      cursor: interactive ? 'pointer' : 'default',
      transition: 'var(--transition-state)',
      ...style
    }
  }, rest), interactive ? /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      inset: 0,
      background: 'currentColor',
      opacity: hover ? 0.08 : 0,
      pointerEvents: 'none'
    }
  }) : null, children);
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/surfaces/Card.jsx", error: String((e && e.message) || e) }); }

// components/surfaces/ListTile.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** `ListTile` — leading icon, title, optional 1–2 line subtitle, trailing slot. */
function ListTile({
  leadingIcon,
  title,
  subtitle,
  trailing,
  lines = 1,
  dense = false,
  onClick,
  style,
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const minHeight = lines >= 3 ? 88 : lines === 2 ? 72 : dense ? 48 : 56;
  return /*#__PURE__*/React.createElement("div", _extends({
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: lines > 1 ? 'flex-start' : 'center',
      gap: '16px',
      minHeight: minHeight + 'px',
      padding: lines > 1 ? '12px 16px' : '0 16px',
      color: 'var(--md-on-surface)',
      cursor: onClick ? 'pointer' : 'default',
      ...style
    }
  }, rest), onClick ? /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      inset: 0,
      background: 'currentColor',
      opacity: hover ? 0.08 : 0,
      pointerEvents: 'none'
    }
  }) : null, leadingIcon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: leadingIcon,
    size: 24,
    color: "var(--md-on-surface-variant)",
    style: {
      position: 'relative',
      marginTop: lines > 1 ? '2px' : 0
    }
  }) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: 'var(--body-large)',
      letterSpacing: 'var(--body-large-tracking)'
    }
  }, title), subtitle ? /*#__PURE__*/React.createElement("div", {
    style: {
      font: 'var(--body-medium)',
      letterSpacing: 'var(--body-medium-tracking)',
      color: 'var(--md-on-surface-variant)',
      whiteSpace: 'pre-line'
    }
  }, subtitle) : null), trailing ? /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: 'center',
      gap: '4px'
    }
  }, trailing) : null);
}
Object.assign(__ds_scope, { ListTile });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/surfaces/ListTile.jsx", error: String((e && e.message) || e) }); }

// components/surfaces/ToolTile.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** The home grid unit: a 2.4:1 card holding an icon and the tool label. */
function ToolTile({
  icon,
  label,
  onClick,
  style,
  ...rest
}) {
  return /*#__PURE__*/React.createElement(__ds_scope.Card, _extends({
    interactive: true,
    onClick: onClick,
    style: {
      aspectRatio: 'var(--tool-tile-aspect)',
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '12px',
      height: '100%',
      padding: 'var(--tile-padding)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 24,
    color: "var(--md-on-surface-variant)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--title-medium)',
      letterSpacing: 'var(--title-medium-tracking)',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, label)));
}
Object.assign(__ds_scope, { ToolTile });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/surfaces/ToolTile.jsx", error: String((e && e.message) || e) }); }

// ui_kits/anvil-app/App.jsx
try { (() => {
const {
  HomeScreen,
  ToolScreen,
  ResultScreen,
  HistoryScreen,
  SettingsScreen
} = window;
function outputsFor(tool, file) {
  const base = (file || 'document').replace(/\.[^.]+$/, '');
  switch (tool.id) {
    case 'pdf/split':
      return {
        files: [base + '_1.pdf', base + '_2.pdf', base + '_3.pdf']
      };
    case 'converter/csv-to-json':
      return {
        files: [base + '.json']
      };
    case 'converter/csv-to-excel':
      return {
        files: [base + '.xlsx']
      };
    case 'pdf/extract-text':
      return {
        files: [base + '.txt'],
        text: 'Q2 revenue grew 14% quarter over quarter…'
      };
    case 'video/extract-audio':
      return {
        files: [base + '.mp3']
      };
    case 'video/mp4-to-gif':
      return {
        files: [base + '.gif']
      };
    case 'write/word-count':
      return {
        files: [],
        text: 'Words: 1284\nCharacters: 7910\nCharacters (no spaces): 6702\nSentences: 71\nParagraphs: 12'
      };
    default:
      return {
        files: [base + '.' + (tool.accepts[0] || 'pdf')]
      };
  }
}
function App() {
  const [stack, setStack] = React.useState([{
    screen: 'home'
  }]);
  const [mode, setMode] = React.useState('light');
  const [shared, setShared] = React.useState('invoice.pdf');
  const top = stack[stack.length - 1];
  const push = s => setStack(st => [...st, s]);
  const pop = () => setStack(st => st.length > 1 ? st.slice(0, -1) : st);
  const home = () => setStack([{
    screen: 'home'
  }]);
  const dark = mode === 'dark';
  return /*#__PURE__*/React.createElement("div", {
    "data-theme": dark ? 'dark' : undefined,
    style: {
      height: '100%',
      background: 'var(--md-surface)',
      color: 'var(--md-on-surface)'
    }
  }, top.screen === 'home' && /*#__PURE__*/React.createElement(HomeScreen, {
    shared: shared,
    onDismissShared: () => setShared(null),
    onOpenTool: t => push({
      screen: 'tool',
      tool: t,
      file: shared && t.accepts.includes(shared.split('.').pop()) ? shared : null
    }),
    onOpenHistory: () => push({
      screen: 'history'
    }),
    onOpenSettings: () => push({
      screen: 'settings'
    })
  }), top.screen === 'tool' && /*#__PURE__*/React.createElement(ToolScreen, {
    tool: top.tool,
    preselected: top.file,
    onBack: pop,
    onDone: (tool, file) => {
      const out = outputsFor(tool, file);
      setStack(st => [...st.slice(0, -1), {
        screen: 'result',
        ...out
      }]);
    }
  }), top.screen === 'result' && /*#__PURE__*/React.createElement(ResultScreen, {
    files: top.files,
    text: top.text,
    onBack: pop,
    onHome: home
  }), top.screen === 'history' && /*#__PURE__*/React.createElement(HistoryScreen, {
    onBack: pop,
    onOpen: r => push({
      screen: 'result',
      files: r.outputs
    })
  }), top.screen === 'settings' && /*#__PURE__*/React.createElement(SettingsScreen, {
    onBack: pop,
    mode: mode,
    onMode: setMode
  }));
}
Object.assign(window, {
  App
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/anvil-app/App.jsx", error: String((e && e.message) || e) }); }

// ui_kits/anvil-app/HistoryScreen.jsx
try { (() => {
const {
  TopAppBar,
  IconButton,
  ListTile
} = window.AnvilDesignSystem_296c7d;
function HistoryScreen({
  onBack,
  onOpen
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      background: 'var(--md-surface)'
    }
  }, /*#__PURE__*/React.createElement(TopAppBar, {
    title: "My Files",
    onBack: onBack,
    actions: /*#__PURE__*/React.createElement(IconButton, {
      icon: "refresh",
      label: "Refresh"
    })
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflowY: 'auto'
    }
  }, window.ANVIL_HISTORY.map(r => /*#__PURE__*/React.createElement(ListTile, {
    key: r.at,
    leadingIcon: r.icon,
    title: r.label,
    subtitle: r.inputs.join(', ') + '\n' + r.at,
    lines: 3,
    onClick: () => onOpen(r)
  }))));
}
Object.assign(window, {
  HistoryScreen
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/anvil-app/HistoryScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/anvil-app/HomeScreen.jsx
try { (() => {
const {
  TopAppBar,
  IconButton,
  TextField,
  ToolTile,
  Banner,
  Button
} = window.AnvilDesignSystem_296c7d;
function CategorySection({
  title,
  tools,
  onOpen
}) {
  if (!tools.length) return null;
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '16px 4px 8px',
      font: 'var(--title-small)',
      letterSpacing: 'var(--title-small-tracking)'
    }
  }, title), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr 1fr',
      gap: 'var(--grid-gutter)'
    }
  }, tools.map(t => /*#__PURE__*/React.createElement(ToolTile, {
    key: t.id,
    icon: t.icon,
    label: t.label,
    onClick: () => onOpen(t)
  }))));
}
function HomeScreen({
  onOpenTool,
  onOpenHistory,
  onOpenSettings,
  shared,
  onDismissShared
}) {
  const [q, setQ] = React.useState('');
  const query = q.trim().toLowerCase();
  const tools = query ? window.ANVIL_TOOLS.filter(t => t.label.toLowerCase().includes(query) || t.desc.toLowerCase().includes(query)) : window.ANVIL_TOOLS;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      background: 'var(--md-surface)'
    }
  }, /*#__PURE__*/React.createElement(TopAppBar, {
    title: "Anvil",
    actions: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(IconButton, {
      icon: "history",
      label: "History",
      onClick: onOpenHistory
    }), /*#__PURE__*/React.createElement(IconButton, {
      icon: "settings",
      label: "Settings",
      onClick: onOpenSettings
    }))
  }), shared ? /*#__PURE__*/React.createElement(Banner, {
    icon: "attach_file",
    actions: /*#__PURE__*/React.createElement(Button, {
      variant: "text",
      onClick: onDismissShared
    }, "Dismiss")
  }, 'Shared file ready: ' + shared + ' — pick a tool') : null, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 'var(--list-padding)'
    }
  }, /*#__PURE__*/React.createElement(TextField, {
    hint: "Search tools",
    prefixIcon: "search",
    value: q,
    onChange: e => setQ(e.target.value)
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflowY: 'auto',
      padding: '0 var(--list-padding) 16px'
    }
  }, tools.length === 0 ? /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '48px 0',
      textAlign: 'center',
      font: 'var(--body-large)',
      color: 'var(--md-on-surface)'
    }
  }, "No tools match.") : window.ANVIL_CATEGORIES.map(c => /*#__PURE__*/React.createElement(CategorySection, {
    key: c,
    title: c,
    tools: tools.filter(t => t.cat === c),
    onOpen: onOpenTool
  }))));
}
Object.assign(window, {
  HomeScreen
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/anvil-app/HomeScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/anvil-app/ResultScreen.jsx
try { (() => {
const {
  TopAppBar,
  ListTile,
  IconButton,
  Button,
  Snackbar
} = window.AnvilDesignSystem_296c7d;
function ResultScreen({
  files,
  text,
  onHome,
  onBack
}) {
  const [toast, setToast] = React.useState(null);
  React.useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 2400);
    return () => clearTimeout(t);
  }, [toast]);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      background: 'var(--md-surface)'
    }
  }, /*#__PURE__*/React.createElement(TopAppBar, {
    title: "Result",
    onBack: onBack
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      padding: 'var(--screen-padding)',
      overflowY: 'auto'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: 'var(--title-medium)',
      letterSpacing: 'var(--title-medium-tracking)'
    }
  }, "Output files"), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 'var(--space-2)'
    }
  }), files.map(name => /*#__PURE__*/React.createElement(ListTile, {
    key: name,
    style: {
      padding: 0
    },
    leadingIcon: "insert_drive_file",
    title: name,
    trailing: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(IconButton, {
      icon: "open_in_new",
      label: "Open",
      onClick: () => setToast('Opened ' + name)
    }), /*#__PURE__*/React.createElement(IconButton, {
      icon: "save_alt",
      label: "Save to Files",
      onClick: () => setToast('Saved ' + name)
    }))
  })), text ? /*#__PURE__*/React.createElement("pre", {
    style: {
      marginTop: 'var(--space-4)',
      font: 'var(--body-medium)',
      fontFamily: 'var(--font-mono)',
      color: 'var(--md-on-surface)',
      whiteSpace: 'pre-wrap'
    }
  }, text) : /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--space-3)',
      marginTop: 'var(--space-4)'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "filled",
    icon: "share",
    fullWidth: true,
    onClick: () => setToast('Shared ' + files.length + ' file' + (files.length > 1 ? 's' : ''))
  }, "Share"), /*#__PURE__*/React.createElement(Button, {
    variant: "outlined",
    fullWidth: true,
    onClick: onHome
  }, "Done"))), toast ? /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      left: 'var(--space-2)',
      right: 'var(--space-2)',
      bottom: 'var(--space-2)'
    }
  }, /*#__PURE__*/React.createElement(Snackbar, null, toast)) : null);
}
Object.assign(window, {
  ResultScreen
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/anvil-app/ResultScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/anvil-app/SettingsScreen.jsx
try { (() => {
const {
  TopAppBar,
  RadioTile
} = window.AnvilDesignSystem_296c7d;
function SettingsScreen({
  onBack,
  mode,
  onMode
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      background: 'var(--md-surface)'
    }
  }, /*#__PURE__*/React.createElement(TopAppBar, {
    title: "Settings",
    onBack: onBack
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflowY: 'auto'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '16px 16px 8px',
      font: 'var(--body-large)',
      letterSpacing: 'var(--body-large-tracking)'
    }
  }, "Theme"), [['System', 'system'], ['Light', 'light'], ['Dark', 'dark']].map(([l, v]) => /*#__PURE__*/React.createElement(RadioTile, {
    key: v,
    label: l,
    value: v,
    selected: mode === v,
    onSelect: onMode
  }))));
}
Object.assign(window, {
  SettingsScreen
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/anvil-app/SettingsScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/anvil-app/ToolScreen.jsx
try { (() => {
const {
  TopAppBar,
  TextField,
  Button,
  LinearProgress
} = window.AnvilDesignSystem_296c7d;
function ToolScreen({
  tool,
  onBack,
  onDone,
  preselected
}) {
  const [file, setFile] = React.useState(preselected || null);
  const [phase, setPhase] = React.useState('idle');
  const [progress, setProgress] = React.useState(null);
  const [message, setMessage] = React.useState('Working…');
  const timers = React.useRef([]);
  React.useEffect(() => () => timers.current.forEach(clearTimeout), []);
  const pick = () => setFile('quarterly_report.' + (tool.accepts[0] || 'pdf'));
  const run = () => {
    setPhase('running');
    setProgress(null);
    setMessage('Reading file…');
    const steps = [[500, 0.3, 'Processing…'], [1200, 0.85, 'Saving…']];
    steps.forEach(([ms, p, m]) => timers.current.push(setTimeout(() => {
      setProgress(p);
      setMessage(m);
    }, ms)));
    timers.current.push(setTimeout(() => onDone(tool, file), 1900));
  };
  const needsFile = tool.requiresInput !== false;
  const canRun = !needsFile || !!file;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      background: 'var(--md-surface)'
    }
  }, /*#__PURE__*/React.createElement(TopAppBar, {
    title: tool.label,
    onBack: onBack
  }), phase === 'running' ? /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      padding: 'var(--screen-padding)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: '100%'
    }
  }, /*#__PURE__*/React.createElement(LinearProgress, {
    value: progress
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 'var(--space-4)',
      font: 'var(--body-large)',
      letterSpacing: 'var(--body-large-tracking)',
      textAlign: 'center'
    }
  }, message), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 'var(--space-6)'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "outlined",
    onClick: () => setPhase('idle')
  }, "Cancel"))) : /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflowY: 'auto',
      display: 'flex',
      flexDirection: 'column',
      padding: 'var(--screen-padding)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: 'var(--body-large)',
      letterSpacing: 'var(--body-large-tracking)'
    }
  }, tool.desc), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 'var(--space-6)'
    }
  }), needsFile ? /*#__PURE__*/React.createElement(Button, {
    variant: "outlined",
    icon: "attach_file",
    onClick: pick
  }, tool.multi ? 'Pick files' : 'Pick file') : null, file ? /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 'var(--space-3)',
      font: 'var(--body-medium)',
      letterSpacing: 'var(--body-medium-tracking)'
    }
  }, 'Selected: ' + file) : null, tool.params.map(p => /*#__PURE__*/React.createElement("div", {
    key: p.key,
    style: {
      marginTop: 'var(--space-4)'
    }
  }, /*#__PURE__*/React.createElement(TextField, {
    label: p.label,
    defaultValue: p.value
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 'var(--space-6)'
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "filled",
    fullWidth: true,
    disabled: !canRun,
    onClick: run
  }, "Run")));
}
Object.assign(window, {
  ToolScreen
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/anvil-app/ToolScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/anvil-app/data.js
try { (() => {
// Sample slice of Anvil's tool registry — labels, icons, descriptions and
// params copied verbatim from lib/tools/**/​*.dart (ToolMeta / ToolParam).
window.ANVIL_TOOLS = [{
  id: 'converter/csv-to-json',
  cat: 'Converters',
  label: 'CSV to JSON',
  icon: 'data_object',
  desc: 'Convert a CSV file into a JSON array of objects.',
  accepts: ['csv'],
  params: []
}, {
  id: 'converter/csv-to-excel',
  cat: 'Converters',
  label: 'CSV to Excel',
  icon: 'table_chart',
  desc: 'Convert a CSV file into an Excel (.xlsx) spreadsheet.',
  accepts: ['csv'],
  params: []
}, {
  id: 'converter/csv-to-xml',
  cat: 'Converters',
  label: 'CSV to XML',
  icon: 'code',
  desc: 'Convert a CSV file into an XML table.',
  accepts: ['csv'],
  params: []
}, {
  id: 'converter/xml-to-csv',
  cat: 'Converters',
  label: 'XML to CSV',
  icon: 'grid_on',
  desc: 'Convert an XML table into a CSV file.',
  accepts: ['xml'],
  params: []
}, {
  id: 'pdf/merge',
  cat: 'PDF',
  label: 'Merge PDFs',
  icon: 'merge',
  desc: 'Combine several PDF files into one document.',
  accepts: ['pdf'],
  multi: true,
  params: []
}, {
  id: 'pdf/split',
  cat: 'PDF',
  label: 'Split PDF',
  icon: 'call_split',
  desc: 'Split a PDF into smaller files by page count.',
  accepts: ['pdf'],
  params: [{
    key: 'every',
    label: 'Pages per file',
    value: '5'
  }]
}, {
  id: 'pdf/compress',
  cat: 'PDF',
  label: 'Compress PDF',
  icon: 'compress',
  desc: 'Shrink a PDF by optimizing its images.',
  accepts: ['pdf'],
  params: [{
    key: 'imageQuality',
    label: 'Image quality (1-100)',
    value: '75'
  }]
}, {
  id: 'pdf/protect',
  cat: 'PDF',
  label: 'Protect PDF',
  icon: 'lock',
  desc: 'Encrypt a PDF with a password (AES-256).',
  accepts: ['pdf'],
  params: [{
    key: 'password',
    label: 'Password',
    value: ''
  }]
}, {
  id: 'pdf/watermark',
  cat: 'PDF',
  label: 'Watermark PDF',
  icon: 'branding_watermark',
  desc: 'Tile a text watermark across every page.',
  accepts: ['pdf'],
  params: [{
    key: 'text',
    label: 'Watermark text',
    value: 'CONFIDENTIAL'
  }]
}, {
  id: 'pdf/sign',
  cat: 'PDF',
  label: 'Sign PDF',
  icon: 'draw',
  desc: 'Stamp a signature image onto a page of a PDF.',
  accepts: ['pdf', 'png', 'jpg'],
  params: []
}, {
  id: 'pdf/extract-text',
  cat: 'PDF',
  label: 'Extract Text',
  icon: 'text_snippet',
  desc: 'Extract selectable text from a PDF.',
  accepts: ['pdf'],
  params: []
}, {
  id: 'pdf/from-url',
  cat: 'PDF',
  label: 'Website to PDF',
  icon: 'public',
  desc: 'Render a web page into a PDF.',
  accepts: [],
  requiresInput: false,
  params: [{
    key: 'url',
    label: 'Page URL',
    value: ''
  }]
}, {
  id: 'image/compress',
  cat: 'Image',
  label: 'Compress Image',
  icon: 'compress',
  desc: "Shrink an image's file size with lossy re-encoding.",
  accepts: ['png', 'jpg', 'webp'],
  params: [{
    key: 'quality',
    label: 'Quality (0-100)',
    value: '75'
  }]
}, {
  id: 'image/crop-circle',
  cat: 'Image',
  label: 'Circle Crop',
  icon: 'panorama_fish_eye',
  desc: 'Crop an image into a circle with a transparent background.',
  accepts: ['png', 'jpg'],
  params: []
}, {
  id: 'image/collage-maker',
  cat: 'Image',
  label: 'Collage Maker',
  icon: 'dashboard',
  desc: 'Arrange several images into a grid collage.',
  accepts: ['png', 'jpg'],
  multi: true,
  params: [{
    key: 'columns',
    label: 'Columns',
    value: '2'
  }]
}, {
  id: 'image/border',
  cat: 'Image',
  label: 'Add Border',
  icon: 'border_outer',
  desc: 'Add a solid color border around an image.',
  accepts: ['png', 'jpg'],
  params: [{
    key: 'sizePx',
    label: 'Border size (px)',
    value: '16'
  }, {
    key: 'color',
    label: 'Color (hex, e.g. #FF0000)',
    value: '#FF000000'
  }]
}, {
  id: 'video/cutter',
  cat: 'Video',
  label: 'Video Cutter',
  icon: 'content_cut',
  desc: 'Cut a clip out of a video without re-encoding.',
  accepts: ['mp4', 'mov', 'mkv'],
  params: [{
    key: 'start',
    label: 'Start (seconds)',
    value: '0'
  }, {
    key: 'duration',
    label: 'Duration (seconds)',
    value: '10'
  }]
}, {
  id: 'video/mp4-to-gif',
  cat: 'Video',
  label: 'MP4 to GIF',
  icon: 'gif',
  desc: 'Turn an MP4 video into an animated GIF.',
  accepts: ['mp4'],
  params: [{
    key: 'fps',
    label: 'Frames per second',
    value: '12'
  }, {
    key: 'width',
    label: 'Width (px)',
    value: '480'
  }]
}, {
  id: 'video/extract-audio',
  cat: 'Video',
  label: 'Extract Audio',
  icon: 'music_note',
  desc: "Extract a video's audio track as an MP3.",
  accepts: ['mp4', 'mov'],
  params: []
}, {
  id: 'video/mute',
  cat: 'Video',
  label: 'Mute Video',
  icon: 'volume_off',
  desc: 'Remove the audio track from a video (no re-encode).',
  accepts: ['mp4', 'mov'],
  params: []
}, {
  id: 'write/word-count',
  cat: 'Write',
  label: 'Word Counter',
  icon: 'numbers',
  desc: 'Count words, characters, sentences and paragraphs.',
  accepts: ['txt'],
  requiresInput: false,
  params: [{
    key: 'text',
    label: 'Text',
    value: ''
  }]
}, {
  id: 'write/summarize',
  cat: 'Write',
  label: 'Summarize PDF',
  icon: 'summarize',
  desc: 'Summarize a PDF with the on-device model.',
  accepts: ['pdf'],
  params: []
}];
window.ANVIL_CATEGORIES = ['Converters', 'PDF', 'Image', 'Video', 'Write'];
window.ANVIL_HISTORY = [{
  toolId: 'pdf/split',
  label: 'Split PDF',
  icon: 'call_split',
  inputs: ['quarterly_report.pdf'],
  at: '2026-08-04 14:02',
  outputs: ['quarterly_report_1.pdf', 'quarterly_report_2.pdf']
}, {
  toolId: 'image/compress',
  label: 'Compress Image',
  icon: 'compress',
  inputs: ['IMG_4471.jpg'],
  at: '2026-08-03 09:18',
  outputs: ['IMG_4471.jpg']
}, {
  toolId: 'converter/csv-to-json',
  label: 'CSV to JSON',
  icon: 'data_object',
  inputs: ['orders_july.csv'],
  at: '2026-08-01 21:44',
  outputs: ['orders_july.json']
}, {
  toolId: 'video/extract-audio',
  label: 'Extract Audio',
  icon: 'music_note',
  inputs: ['lecture_03.mp4'],
  at: '2026-07-29 11:05',
  outputs: ['lecture_03.mp3']
}];
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/anvil-app/data.js", error: String((e && e.message) || e) }); }

__ds_ns.Button = __ds_scope.Button;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.Banner = __ds_scope.Banner;

__ds_ns.CircularProgress = __ds_scope.CircularProgress;

__ds_ns.LinearProgress = __ds_scope.LinearProgress;

__ds_ns.Snackbar = __ds_scope.Snackbar;

__ds_ns.Icon = __ds_scope.Icon;

__ds_ns.RadioTile = __ds_scope.RadioTile;

__ds_ns.TextField = __ds_scope.TextField;

__ds_ns.TopAppBar = __ds_scope.TopAppBar;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.ListTile = __ds_scope.ListTile;

__ds_ns.ToolTile = __ds_scope.ToolTile;

})();
