import 'package:flutter/material.dart';

import 'package:anvil/ui/tokens.dart';

/// The "Slab, resolved" (2a) themes. Both share the type scale and font; the
/// palette differs per brightness (see [AnvilColors.dark]/[AnvilColors.light]).
/// Exported as [lightTheme]/[darkTheme] (consumed by `lib/app.dart`).

TextTheme _textTheme(AnvilColors c) {
  const family = 'Space Grotesk';
  return TextTheme(
    headlineMedium: TextStyle(
      fontFamily: family,
      fontSize: 30,
      height: 34 / 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.0,
      color: c.onSurface,
    ),
    headlineSmall: TextStyle(
      fontFamily: family,
      fontSize: 25,
      height: 30 / 25,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.9,
      color: c.onSurface,
    ),
    titleLarge: TextStyle(
      fontFamily: family,
      fontSize: 21,
      height: 26 / 21,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.7,
      color: c.onSurface,
    ),
    titleMedium: TextStyle(
      fontFamily: family,
      fontSize: 18,
      height: 24 / 18,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      color: c.onSurface,
    ),
    titleSmall: TextStyle(
      fontFamily: family,
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: c.onSurface,
    ),
    bodyLarge: TextStyle(
      fontFamily: family,
      fontSize: 15,
      height: 23 / 15,
      fontWeight: FontWeight.w400,
      color: c.onSurface,
    ),
    bodyMedium: TextStyle(
      fontFamily: family,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w400,
      color: c.onSurface,
    ),
    labelSmall: TextStyle(
      fontFamily: family,
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: c.onSurface,
    ),
  );
}

ColorScheme _colorScheme(Brightness brightness, AnvilColors c) {
  final isDark = brightness == Brightness.dark;
  return ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: c.accentContainer,
    onPrimaryContainer: c.accentText,
    secondary: c.accentText,
    onSecondary: c.onAccent,
    secondaryContainer: c.accentContainer,
    onSecondaryContainer: c.accentText,
    tertiary: c.accentText,
    onTertiary: c.onAccent,
    surface: c.container,
    onSurface: c.onSurface,
    onSurfaceVariant: c.muted,
    surfaceContainerLowest: c.bg,
    surfaceContainerLow: c.container,
    surfaceContainer: c.container,
    surfaceContainerHigh: c.containerHigh,
    surfaceContainerHighest: c.containerHigh,
    surfaceDim: c.bg,
    surfaceBright: c.containerHigh,
    error: c.error,
    onError: Color(isDark ? 0xFF690005 : 0xFFFFFFFF),
    errorContainer: c.error,
    onErrorContainer: Color(isDark ? 0xFF690005 : 0xFFFFFFFF),
    outline: c.hint,
    outlineVariant: c.faint,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: c.onSurface,
    onInverseSurface: c.bg,
    inversePrimary: c.accent,
  );
}

ThemeData _build(Brightness brightness, AnvilColors c) {
  final textTheme = _textTheme(c);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'Space Grotesk',
    colorScheme: _colorScheme(brightness, c),
    textTheme: textTheme,
    iconTheme: IconThemeData(color: c.iconStrong),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.container,
      hintStyle: textTheme.bodyLarge!.copyWith(color: c.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AnvilRadii.search),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AnvilRadii.search),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AnvilRadii.search),
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.containerHigh,
      contentTextStyle: textTheme.bodyLarge,
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    dividerTheme: DividerThemeData(color: c.containerHigh),
    extensions: [c],
  );
}

final ThemeData lightTheme = _build(Brightness.light, AnvilColors.light);
final ThemeData darkTheme = _build(Brightness.dark, AnvilColors.dark);
