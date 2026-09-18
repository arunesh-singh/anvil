import 'package:flutter/material.dart';

/// Design tokens for the "Slab, resolved" (2a) look. The single source of
/// truth for colors, radii, and the mono text helper. Every screen reads
/// colors via `Theme.of(context).extension<AnvilColors>()!` — no widget
/// hardcodes a hex value outside this file.
@immutable
class AnvilColors extends ThemeExtension<AnvilColors> {
  final Color bg;
  final Color container;
  final Color containerHigh;
  final Color accentContainer;
  final Color accent;
  final Color accentText;
  final Color onSurface;
  final Color muted;
  final Color hint;
  final Color faint;
  final Color faintMono;
  final Color iconStrong;
  final Color onAccent;
  final Color info;
  final Color error;

  const AnvilColors({
    required this.bg,
    required this.container,
    required this.containerHigh,
    required this.accentContainer,
    required this.accent,
    required this.accentText,
    required this.onSurface,
    required this.muted,
    required this.hint,
    required this.faint,
    required this.faintMono,
    required this.iconStrong,
    required this.onAccent,
    required this.info,
    required this.error,
  });

  static const dark = AnvilColors(
    bg: Color(0xFF16171A),
    container: Color(0xFF1F2126),
    containerHigh: Color(0xFF2C2F35),
    accentContainer: Color(0xFF242A45),
    accent: Color(0xFF4D67FF),
    accentText: Color(0xFF8FA0FF),
    onSurface: Color(0xFFE8E8EA),
    muted: Color(0xFF8B9099),
    hint: Color(0xFF6B7079),
    faint: Color(0xFF43464D),
    faintMono: Color(0xFF5C5C64),
    iconStrong: Color(0xFFC9CCD3),
    onAccent: Color(0xFFFFFFFF),
    info: Color(0xFF1A1C20),
    error: Color(0xFFFFB4AB),
  );

  static const light = AnvilColors(
    bg: Color(0xFFF3F3F6),
    container: Color(0xFFFFFFFF),
    containerHigh: Color(0xFFE7E8EC),
    accentContainer: Color(0xFFE1E5FF),
    accent: Color(0xFF4D67FF),
    accentText: Color(0xFF3346D6),
    onSurface: Color(0xFF1A1B1E),
    muted: Color(0xFF565A61),
    hint: Color(0xFF83888F),
    faint: Color(0xFFA8ACB3),
    faintMono: Color(0xFF8A8F98),
    iconStrong: Color(0xFF3C3F45),
    onAccent: Color(0xFFFFFFFF),
    info: Color(0xFFEEF0F5),
    error: Color(0xFFBA1A1A),
  );

  @override
  AnvilColors copyWith({
    Color? bg,
    Color? container,
    Color? containerHigh,
    Color? accentContainer,
    Color? accent,
    Color? accentText,
    Color? onSurface,
    Color? muted,
    Color? hint,
    Color? faint,
    Color? faintMono,
    Color? iconStrong,
    Color? onAccent,
    Color? info,
    Color? error,
  }) {
    return AnvilColors(
      bg: bg ?? this.bg,
      container: container ?? this.container,
      containerHigh: containerHigh ?? this.containerHigh,
      accentContainer: accentContainer ?? this.accentContainer,
      accent: accent ?? this.accent,
      accentText: accentText ?? this.accentText,
      onSurface: onSurface ?? this.onSurface,
      muted: muted ?? this.muted,
      hint: hint ?? this.hint,
      faint: faint ?? this.faint,
      faintMono: faintMono ?? this.faintMono,
      iconStrong: iconStrong ?? this.iconStrong,
      onAccent: onAccent ?? this.onAccent,
      info: info ?? this.info,
      error: error ?? this.error,
    );
  }

  @override
  AnvilColors lerp(ThemeExtension<AnvilColors>? other, double t) {
    if (other is! AnvilColors) return this;
    return AnvilColors(
      bg: Color.lerp(bg, other.bg, t)!,
      container: Color.lerp(container, other.container, t)!,
      containerHigh: Color.lerp(containerHigh, other.containerHigh, t)!,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      hint: Color.lerp(hint, other.hint, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      faintMono: Color.lerp(faintMono, other.faintMono, t)!,
      iconStrong: Color.lerp(iconStrong, other.iconStrong, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      info: Color.lerp(info, other.info, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

/// The four-step radius scale plus derived control radii.
class AnvilRadii {
  const AnvilRadii._();
  static const double chip = 12;
  static const double control = 14;
  static const double row = 18;
  static const double search = 16;
  static const double button = 20;
  static const double panel = 22;
}

/// Mono text helper — JetBrains Mono for filenames, metadata, versions.
/// No global Material slot uses mono; call this explicitly where needed.
class AnvilText {
  const AnvilText._();
  static TextStyle mono(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.4,
  }) {
    return TextStyle(
      fontFamily: 'JetBrains Mono',
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
    );
  }
}
