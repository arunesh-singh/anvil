/// Small building blocks shared by the PDF workspace screens and sheets (and
/// the Build chrome of the doc editor): pills, segmented control, sheet frame,
/// estimate box, header and colour swatches — the Direction A mock's `.pill`,
/// `.seg`, `.sheet`, `.estimate` and `.sw` classes mapped onto Anvil tokens.
library;

import 'package:flutter/material.dart';

import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/workspace/workspace_model.dart';
import 'package:anvil/ui/widgets/slab.dart';

AnvilColors _c(BuildContext context) =>
    Theme.of(context).extension<AnvilColors>()!;

/// The text tools' 10-colour palette (ARGB).
const kTextPalette = <Color>[
  Colors.black,
  Colors.white,
  Color(0xFF444444),
  Color(0xFFE53935),
  Color(0xFFFB8C00),
  Color(0xFFFDD835),
  Color(0xFF43A047),
  Color(0xFF1E88E5),
  Color(0xFF8E24AA),
  Color(0xFF6D4C41),
];

/// Rounded pill button. [on] = accent fill; [small] = compact in-sheet variant;
/// [raised] lifts the idle surface to [AnvilColors.containerHigh] so pills
/// stay legible on a `container` bar. Disabled (dimmed, no tap) when [onTap]
/// is null.
class WsPill extends StatelessWidget {
  const WsPill({
    super.key,
    this.icon,
    required this.label,
    this.on = false,
    this.small = false,
    this.raised = false,
    this.onTap,
  });

  final IconData? icon;
  final String label;
  final bool on;
  final bool small;
  final bool raised;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    final text = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final bg = on
        ? c.accent
        : (small || raised ? c.containerHigh : c.container);
    final fg = on ? c.onAccent : (enabled ? c.onSurface : c.faint);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AnvilRadii.chip),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: small ? 30 : 36,
          padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: small ? 16 : 18, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: (small ? text.bodyMedium : text.titleSmall)!.copyWith(
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of pills with an 8px gap.
class WsPillRail extends StatelessWidget {
  const WsPillRail({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          children[i],
        ],
      ],
    ),
  );
}

/// Equal-width segmented choice. [inSheet] lifts the idle surface to
/// [AnvilColors.containerHigh] so it reads on a sheet.
class WsSegmented extends StatelessWidget {
  const WsSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.inSheet = false,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: i == selected
                  ? c.accent
                  : (inSheet ? c.containerHigh : c.container),
              borderRadius: BorderRadius.circular(AnvilRadii.control),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onChanged(i),
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Text(
                      labels[i],
                      style: text.titleSmall!.copyWith(
                        color: i == selected ? c.onAccent : c.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Bottom-sheet chrome: grab bar, title row, scrollable body, keyboard inset.
/// Capped at 88% of the screen height.
class WsSheetFrame extends StatelessWidget {
  const WsSheetFrame({
    super.key,
    required this.title,
    this.sub,
    required this.children,
  });

  final String title;
  final String? sub;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    final mq = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
      child: Container(
        decoration: BoxDecoration(
          color: c.container,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AnvilRadii.panel),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          16 + mq.viewInsets.bottom + mq.padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: c.faint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 10),
                if (sub != null)
                  Expanded(
                    child: Text(
                      sub!,
                      style: AnvilText.mono(12, color: c.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [child] (normally a [WsSheetFrame]) as a modal bottom sheet.
Future<T?> showWsSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => child,
    );

/// Accent box summarising a measured/estimated result.
class WsEstimate extends StatelessWidget {
  const WsEstimate({
    super.key,
    required this.label,
    required this.value,
    this.delta,
  });

  final String label;
  final String value;
  final String? delta;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.accentContainer,
        borderRadius: BorderRadius.circular(AnvilRadii.panel),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionEyebrow(label, color: c.accentText),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AnvilText.mono(
                    22,
                    weight: FontWeight.w500,
                    color: c.accentText,
                  ).copyWith(letterSpacing: -0.5),
                ),
              ],
            ),
          ),
          if (delta != null)
            Text(
              delta!,
              style: Theme.of(
                context,
              ).textTheme.titleMedium!.copyWith(color: c.accentText),
            ),
        ],
      ),
    );
  }
}

/// 40px neutral header chip (`.chip.neutral`); dimmed and inert without
/// [onTap].
class WsChip extends StatelessWidget {
  const WsChip({super.key, required this.icon, this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    final chip = Material(
      color: c.container,
      borderRadius: BorderRadius.circular(AnvilRadii.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 20,
            color: onTap == null ? c.faint : c.iconStrong,
          ),
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// Screen header: back chip, title + mono sub, trailing chips.
class WsHeader extends StatelessWidget {
  const WsHeader({
    super.key,
    required this.title,
    this.sub,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final String? sub;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return Row(
      children: [
        WsChip(
          icon: Icons.arrow_back,
          tooltip: 'Back',
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (sub != null)
                Text(
                  sub!,
                  style: AnvilText.mono(12, color: c.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: 8), a],
      ],
    );
  }
}

/// 28px colour swatch; the selected one wears a 2px accent ring.
class WsSwatch extends StatelessWidget {
  const WsSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AnvilRadii.chip),
          border: Border.all(
            color: selected ? c.accent : c.faint,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

/// A mock `.srow`: leading chip, title, mono sub, trailing widget.
class WsRow extends StatelessWidget {
  const WsRow({
    super.key,
    this.leading,
    required this.title,
    this.sub,
    this.trailing,
    this.inSheet = false,
  });

  final Widget? leading;
  final String title;
  final String? sub;
  final Widget? trailing;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: inSheet ? c.containerHigh : c.container,
        borderRadius: BorderRadius.circular(AnvilRadii.row),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (sub != null)
                  Text(
                    sub!,
                    style: AnvilText.mono(12, color: c.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// "This page / Page 4 | Pages 4-9 | n selected / All N" scope picker for the
/// page-scoped sheets. The selection segment only appears with a non-empty
/// selection.
class ScopeSegment extends StatelessWidget {
  const ScopeSegment({
    super.key,
    required this.selectionLabels,
    required this.total,
    required this.value,
    required this.onChanged,
  });

  /// Sorted 1-based positions of the selected pages.
  final List<int> selectionLabels;
  final int total;
  final ScopeChoice value;
  final ValueChanged<ScopeChoice> onChanged;

  static String selectionLabel(List<int> labels) {
    if (labels.length == 1) return 'Page ${labels.single}';
    final contiguous = labels.last - labels.first == labels.length - 1;
    return contiguous
        ? 'Pages ${labels.first}-${labels.last}'
        : '${labels.length} selected';
  }

  @override
  Widget build(BuildContext context) {
    final choices = [
      ScopeChoice.page,
      if (selectionLabels.isNotEmpty) ScopeChoice.selection,
      ScopeChoice.all,
    ];
    final shown = choices.contains(value) ? value : ScopeChoice.page;
    return WsSegmented(
      inSheet: true,
      labels: [
        for (final ch in choices)
          switch (ch) {
            ScopeChoice.page => 'This page',
            ScopeChoice.selection => selectionLabel(selectionLabels),
            ScopeChoice.all => 'All $total',
          },
      ],
      selected: choices.indexOf(shown),
      onChanged: (i) => onChanged(choices[i]),
    );
  }
}
