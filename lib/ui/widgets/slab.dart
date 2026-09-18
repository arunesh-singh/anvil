import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tokens.dart';

/// Shared "Slab, resolved" building blocks. Every widget reads its palette from
/// the [AnvilColors] theme extension so both light and dark render correctly.

AnvilColors _c(BuildContext context) =>
    Theme.of(context).extension<AnvilColors>()!;

/// Rounded-square icon tile. Defaults to the accent-container chip.
class IconChip extends StatelessWidget {
  const IconChip({
    super.key,
    required this.icon,
    this.box = 40,
    this.glyph = 20,
    this.bg,
    this.fg,
    this.radius = AnvilRadii.control,
  });

  final IconData icon;
  final double box;
  final double glyph;
  final Color? bg;
  final Color? fg;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: bg ?? c.accentContainer,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: glyph, color: fg ?? c.accentText),
    );
  }
}

/// A tappable container row: optional leading icon chip, title, subtitle,
/// trailing (defaults to a chevron).
class ToolRow extends StatelessWidget {
  const ToolRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.mono = false,
  });

  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    final text = Theme.of(context).textTheme;
    final lead = leading ?? (icon != null ? IconChip(icon: icon!) : null);
    return Material(
      color: c.container,
      borderRadius: BorderRadius.circular(AnvilRadii.row),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: mono
                            ? AnvilText.mono(12, color: c.muted, height: 18 / 12)
                            : text.bodyMedium!.copyWith(color: c.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing ??
                  Icon(Icons.chevron_right, size: 20, color: c.hint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small letter-spaced section label. Accent variant uses [AnvilColors.accentText].
class SectionEyebrow extends StatelessWidget {
  const SectionEyebrow(this.text, {super.key, this.icon, this.color});

  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    final col = color ?? c.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: col),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: col,
                letterSpacing: 1,
              ),
        ),
      ],
    );
  }
}

/// Full-width filled action button. Disabled when [onPressed] is null.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    final enabled = onPressed != null;
    final fg = enabled ? c.onAccent : c.hint;
    return Material(
      color: enabled ? c.accent : c.containerHigh,
      borderRadius: BorderRadius.circular(AnvilRadii.button),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall!
                    .copyWith(color: fg, fontSize: 16),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, size: 20, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width neutral button on the [AnvilColors.container] surface.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return Material(
      color: c.container,
      borderRadius: BorderRadius.circular(AnvilRadii.button),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall!
                    .copyWith(color: c.onSurface, fontSize: 16),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, size: 20, color: c.onSurface),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A rounded container panel at the [AnvilRadii.panel] radius.
class SlabPanel extends StatelessWidget {
  const SlabPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.container,
        borderRadius: BorderRadius.circular(AnvilRadii.panel),
      ),
      child: child,
    );
  }
}

/// Informational card: accent glyph + muted body on the [AnvilColors.info] bg.
class InfoCard extends StatelessWidget {
  const InfoCard(this.text, {super.key, this.icon = Icons.bolt});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.info,
        borderRadius: BorderRadius.circular(AnvilRadii.panel),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style:
                  Theme.of(context).textTheme.bodyLarge!.copyWith(color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled integer stepper: `[−] value [+]` with optional helper text.
class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final int value;
  final int min;
  final int? max;
  final ValueChanged<int> onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    final text = Theme.of(context).textTheme;
    final canDec = value > min;
    final canInc = max == null || value < max!;
    return SlabPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: text.titleSmall)),
              _stepBtn(
                context,
                Icons.remove,
                bg: c.containerHigh,
                fg: canDec ? c.onSurface : c.faint,
                onTap: canDec ? () => onChanged(value - 1) : null,
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: text.titleMedium,
                ),
              ),
              _stepBtn(
                context,
                Icons.add,
                bg: c.accent,
                fg: canInc ? c.onAccent : c.faint,
                onTap: canInc ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
          if (helperText != null && helperText!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              helperText!,
              style: text.bodyMedium!.copyWith(color: c.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepBtn(
    BuildContext context,
    IconData icon, {
    required Color bg,
    required Color fg,
    VoidCallback? onTap,
  }) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AnvilRadii.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: fg),
        ),
      ),
    );
  }
}

/// A 200px progress ring. Determinate when [fraction] is set, otherwise a
/// rotating indeterminate arc.
class CircularPercent extends StatefulWidget {
  const CircularPercent({
    super.key,
    required this.fraction,
    required this.centerLabel,
    this.subLabel,
  });

  final double? fraction;
  final String centerLabel;
  final String? subLabel;

  @override
  State<CircularPercent> createState() => _CircularPercentState();
}

class _CircularPercentState extends State<CircularPercent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    final text = Theme.of(context).textTheme;
    final indeterminate = widget.fraction == null;
    return SizedBox(
      width: 200,
      height: 200,
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) {
          return CustomPaint(
            painter: _RingPainter(
              fraction: widget.fraction,
              rotation: indeterminate ? _spin.value * 2 * math.pi : 0,
              track: c.accentContainer,
              sweep: c.accent,
              disc: c.bg,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.centerLabel, style: text.headlineMedium),
                  if (widget.subLabel != null &&
                      widget.subLabel!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        widget.subLabel!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium!.copyWith(color: c.muted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.rotation,
    required this.track,
    required this.sweep,
    required this.disc,
  });

  final double? fraction;
  final double rotation;
  final Color track;
  final Color sweep;
  final Color disc;

  static const double _stroke = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - _stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    canvas.drawCircle(center, radius, trackPaint);

    final sweepPaint = Paint()
      ..color = sweep
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    const start = -math.pi / 2;
    if (fraction == null) {
      // Indeterminate: a short arc rotating around the ring.
      canvas.drawArc(rect, start + rotation, math.pi * 0.5, false, sweepPaint);
    } else {
      final frac = fraction!.clamp(0.0, 1.0);
      if (frac > 0) {
        canvas.drawArc(rect, start, 2 * math.pi * frac, false, sweepPaint);
      }
    }

    // Inner disc.
    final discPaint = Paint()..color = disc;
    canvas.drawCircle(center, radius - _stroke / 2 - 2, discPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.rotation != rotation ||
      old.sweep != sweep ||
      old.track != track ||
      old.disc != disc;
}

/// Human category label, shared by Home and Browse.
String categoryLabel(ToolCategory c) => switch (c) {
      ToolCategory.pdf => 'PDF',
      ToolCategory.image => 'Image',
      ToolCategory.video => 'Video & audio',
      ToolCategory.converter => 'Convert files',
      ToolCategory.write => 'Write',
    };

/// Category glyph, shared by Home and Browse.
IconData categoryIcon(ToolCategory c) => switch (c) {
      ToolCategory.pdf => Icons.picture_as_pdf,
      ToolCategory.image => Icons.image,
      ToolCategory.video => Icons.movie,
      ToolCategory.converter => Icons.sync_alt,
      ToolCategory.write => Icons.edit_note,
    };

/// The fixed category display order used by the Home "Browse the bench" rows.
const List<ToolCategory> kCategoryOrder = [
  ToolCategory.pdf,
  ToolCategory.image,
  ToolCategory.video,
  ToolCategory.converter,
  ToolCategory.write,
];

/// Formats a byte count as KB/MB/GB with one decimal at/above 1 unit.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(1)} ${units[i]}';
}
