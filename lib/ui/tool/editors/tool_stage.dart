/// Controls shared by the redesigned single-tool screens (design
/// `explorations/tools-workspace.html`): the media stage with its dark pill
/// bar (`.istage` + `.stagebar`), a labelled slider with named ends, editable
/// mono number boxes (`.mini2`), the aspect lock, and colour swatches with an
/// eyedropper — mapped onto Anvil tokens.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';

AnvilColors _c(BuildContext context) =>
    Theme.of(context).extension<AnvilColors>()!;

/// Media scrim for pills drawn over photos/video — theme-independent because
/// it sits on the content, not the surface.
final _scrim = Colors.black.withValues(alpha: 0.6);

/// The containerHigh stage panel the file sits on, with an optional
/// bottom-centred bar of [StagePill]s over it.
class StagePanel extends StatelessWidget {
  const StagePanel({
    super.key,
    required this.child,
    this.bar = const [],
    this.height,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final List<Widget> bar;
  final double? height;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: c.containerHigh,
        borderRadius: BorderRadius.circular(AnvilRadii.panel),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: Center(child: child)),
          if (bar.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < bar.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    bar[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Dark translucent pill over media: an icon, a mono label, or both.
class StagePill extends StatelessWidget {
  const StagePill({super.key, this.icon, this.label, this.onTap, this.tooltip})
    : assert(icon != null || label != null);

  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pill = Material(
      color: _scrim,
      borderRadius: BorderRadius.circular(AnvilRadii.chip),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, size: 18, color: Colors.white),
              if (icon != null && label != null) const SizedBox(width: 6),
              if (label != null)
                Text(label!, style: AnvilText.mono(12, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// "Quality ········ 75" over an accent slider with muted mono ends
/// ("smaller" … "sharper").
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.onChangeEnd,
    this.startLabel,
    this.endLabel,
  });

  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? startLabel;
  final String? endLabel;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            Text(valueLabel, style: AnvilText.mono(13, color: c.onSurface)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: c.accent,
            inactiveTrackColor: c.accentContainer,
            thumbColor: c.accent,
            overlayShape: SliderComponentShape.noOverlay,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        if (startLabel != null || endLabel != null)
          Row(
            children: [
              Text(startLabel ?? '', style: AnvilText.mono(11, color: c.muted)),
              const Spacer(),
              Text(endLabel ?? '', style: AnvilText.mono(11, color: c.muted)),
            ],
          ),
      ],
    );
  }
}

/// Eyebrow label over an editable mono integer (the mock's `.mini2`).
/// Read-only when [onChanged] is null. Commits on submit / focus loss.
class NumberBox extends StatefulWidget {
  const NumberBox({
    super.key,
    required this.label,
    required this.value,
    this.suffix = '',
    this.onChanged,
  });

  final String label;
  final int value;
  final String suffix;
  final ValueChanged<int>? onChanged;

  @override
  State<NumberBox> createState() => _NumberBoxState();
}

class _NumberBoxState extends State<NumberBox> {
  late final TextEditingController _ctl = TextEditingController(
    text: '${widget.value}',
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(NumberBox old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _ctl.text != '${widget.value}') {
      _ctl.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = int.tryParse(_ctl.text.trim());
    if (v == null || v == widget.value) {
      _ctl.text = '${widget.value}';
      return;
    }
    widget.onChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    final style = AnvilText.mono(14, color: c.onSurface);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.container,
        borderRadius: BorderRadius.circular(AnvilRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: c.muted, letterSpacing: 1),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctl,
                  focusNode: _focus,
                  enabled: widget.onChanged != null,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: style,
                  decoration: const InputDecoration.collapsed(hintText: ''),
                  onSubmitted: (_) => _commit(),
                ),
              ),
              if (widget.suffix.isNotEmpty)
                Text(widget.suffix, style: AnvilText.mono(14, color: c.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The chain-link aspect lock between two [NumberBox]es.
class LinkToggle extends StatelessWidget {
  const LinkToggle({super.key, required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return Tooltip(
      message: on ? 'Aspect locked' : 'Aspect unlocked',
      child: Material(
        color: on ? c.accentContainer : c.container,
        borderRadius: BorderRadius.circular(AnvilRadii.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              on ? Icons.link : Icons.link_off,
              size: 20,
              color: on ? c.accentText : c.iconStrong,
            ),
          ),
        ),
      ),
    );
  }
}

/// Colour swatches, an optional eyedropper chip, and a trailing mono label
/// (usually the hex of the current colour).
class SwatchRow extends StatelessWidget {
  const SwatchRow({
    super.key,
    required this.colors,
    required this.selected,
    required this.onSelected,
    this.onEyedropper,
    this.eyedropperActive = false,
    this.trailing,
  });

  final List<Color> colors;
  final Color? selected;
  final ValueChanged<Color> onSelected;
  final VoidCallback? onEyedropper;

  /// Highlights the eyedropper while the screen waits for a tap on the media.
  final bool eyedropperActive;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = _c(context);
    return Row(
      children: [
        for (final col in colors) ...[
          WsSwatch(
            color: col,
            selected: selected?.toARGB32() == col.toARGB32(),
            onTap: () => onSelected(col),
          ),
          const SizedBox(width: 8),
        ],
        if (onEyedropper != null)
          Tooltip(
            message: 'Pick a colour from the photo',
            child: Material(
              color: eyedropperActive ? c.accent : c.container,
              borderRadius: BorderRadius.circular(AnvilRadii.chip),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onEyedropper,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(
                    Icons.colorize,
                    size: 16,
                    color: eyedropperActive ? c.onAccent : c.iconStrong,
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        if (trailing != null)
          Text(trailing!, style: AnvilText.mono(12, color: c.muted)),
      ],
    );
  }
}

/// `#AARRGGBB` for [c] — the format the image tools' colour params take.
String hexOf(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// Parses `#RGB`, `#RRGGBB` or `#AARRGGBB` (hash optional); null if invalid.
Color? parseHexColor(String s) {
  var h = s.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 3) h = h.split('').map((d) => '$d$d').join();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}
