/// The Collage screen (design `explorations/tools-workspace.html`, frame
/// "Collage maker") for `image/collage-maker` and `image/combine-maker`: a
/// live preview of the exact output (cells, gap, background) with its pixel
/// size, a layout picker, a strip to reorder / remove / add images, gap and
/// background controls, and Run once there are two images.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/collage_layout.dart';
import 'package:anvil/ui/tool/editors/tool_frame.dart';
import 'package:anvil/ui/tool/editors/tool_stage.dart';
import 'package:anvil/ui/tool/input/input_picker.dart';
import 'package:anvil/ui/tool/input/media_sources.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Background swatches; fully transparent is drawn as a checker.
const collageSwatches = [
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFFE1E5FF),
  Color(0x00000000),
];

class CollageEditorScreen extends ConsumerStatefulWidget {
  const CollageEditorScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<CollageEditorScreen> createState() =>
      _CollageEditorScreenState();
}

class _CollageEditorScreenState extends ConsumerState<CollageEditorScreen> {
  late CollageDraft _draft;
  final List<CollageDraft> _undo = [];
  bool _gapDragging = false;
  bool _loading = false;

  bool get _combine => widget.tool.meta.id == 'combine-maker';

  @override
  void initState() {
    super.initState();
    var background = '#00000000';
    for (final p in widget.tool.meta.params) {
      if (p.key == 'background') background = p.defaultText;
    }
    _draft = CollageDraft(
      layout: _combine ? CollageLayout.oneRow : CollageLayout.twoColumns,
      background: background,
    );
    final shared = takeSharedInput(ref, widget.tool.meta);
    if (shared != null) _add([shared], undoable: false);
  }

  Future<void> _add(List<InputFile> files, {bool undoable = true}) async {
    if (files.isEmpty) return;
    setState(() => _loading = true);
    final fs = getIt<FileService>();
    final added = <CollageItem>[];
    for (final f in files) {
      if (!toolAccepts(widget.tool.meta, f)) continue;
      final b = Uint8List.fromList(await fs.readBytes(f.path));
      final codec = await ui.instantiateImageCodec(b);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      added.add(CollageItem(file: f, size: size, bytes: b));
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (added.isEmpty) return;
      if (undoable) _undo.add(_draft);
      _draft = _draft.add(added);
    });
  }

  Future<void> _pickMore() async {
    final files = await ref
        .read(mediaSourcesProvider)
        .files(widget.tool.meta.acceptedExtensions, multiple: true);
    await _add(files);
  }

  void _apply(CollageDraft next) {
    setState(() {
      _undo.add(_draft);
      _draft = next;
    });
  }

  Future<void> _hexSheet() async {
    final picked = await showWsSheet<Color>(
      context,
      _HexSheet(initial: _draft.background),
    );
    if (picked != null) _apply(_draft.copyWith(background: hexOf(picked)));
  }

  void _run() {
    if (!_draft.canRun) return;
    ref.read(jobProvider.notifier).start(widget.tool, _draft.input);
  }

  @override
  Widget build(BuildContext context) {
    final out = _draft.outputSize;
    return ToolFrame(
      tool: widget.tool,
      hasInput: _draft.items.isNotEmpty,
      onPicked: (files) => _add(files, undoable: false),
      actions: [
        WsChip(
          icon: Icons.undo,
          tooltip: 'Undo',
          onTap: _undo.isEmpty
              ? null
              : () => setState(() => _draft = _undo.removeLast()),
        ),
      ],
      runLabel: _combine ? 'Combine' : 'Make collage',
      runDetail: _draft.canRun
          ? '· ${out.width.round()} × ${out.height.round()} px'
          : null,
      onRun: _draft.canRun && !_loading ? _run : null,
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final out = _draft.outputSize;
    final bg = parseHexColor(_draft.background) ?? const Color(0x00000000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StagePanel(
          height: 280,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 52),
          bar: [
            StagePill(label: '${out.width.round()} × ${out.height.round()} px'),
          ],
          child: _CollagePreview(draft: _draft),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final l in CollageLayout.values) ...[
              if (l.index > 0) const SizedBox(width: 8),
              Expanded(
                child: _LayoutTile(
                  layout: l,
                  on: _draft.layout == l,
                  onTap: () => _apply(_draft.copyWith(layout: l)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 72,
          child: Row(
            children: [
              Expanded(child: _strip(c)),
              const SizedBox(width: 8),
              _AddTile(onTap: _loading ? null : _pickMore),
            ],
          ),
        ),
        if (!_draft.canRun) ...[
          const SizedBox(height: 8),
          Text(
            'Add at least one more image.',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
        ],
        const SizedBox(height: 16),
        LabeledSlider(
          title: 'Gap',
          valueLabel: '${_draft.gap} px',
          value: _draft.gap.toDouble(),
          min: 0,
          max: 48,
          divisions: 48,
          onChanged: (v) => setState(() {
            if (!_gapDragging) {
              _gapDragging = true;
              _undo.add(_draft);
            }
            _draft = _draft.copyWith(gap: v.round());
          }),
          onChangeEnd: (_) => _gapDragging = false,
        ),
        const SizedBox(height: 16),
        const SectionEyebrow('Background'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final s in collageSwatches) ...[
              _BgSwatch(
                color: s,
                selected: bg.toARGB32() == s.toARGB32(),
                onTap: () => _apply(_draft.copyWith(background: hexOf(s))),
              ),
              const SizedBox(width: 8),
            ],
            WsChip(
              icon: Icons.colorize,
              tooltip: 'Hex colour',
              onTap: _hexSheet,
            ),
            const Spacer(),
            Text(_draft.background, style: AnvilText.mono(12, color: c.muted)),
          ],
        ),
      ],
    );
  }

  Widget _strip(AnvilColors c) {
    final items = _draft.items;
    return ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorderItem: (from, to) => _apply(_draft.reorder(from, to)),
      itemBuilder: (context, i) => ReorderableDragStartListener(
        key: ObjectKey(items[i]),
        index: i,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SizedBox(
            width: 72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AnvilRadii.control),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    items[i].bytes,
                    fit: BoxFit.cover,
                    cacheWidth: 200,
                  ),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: _Badge(
                      text: '${i + 1}',
                      color: c.accent,
                      fg: c.onAccent,
                    ),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Tooltip(
                      message: 'Remove',
                      child: InkResponse(
                        onTap: () => _apply(_draft.remove(i)),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The output drawn at its real proportions: background, gap frame, and
/// each image fit-centred in its cell — the same layout as
/// `ImageChannel.grid`.
class _CollagePreview extends StatelessWidget {
  const _CollagePreview({required this.draft});

  final CollageDraft draft;

  @override
  Widget build(BuildContext context) {
    final items = draft.items;
    final out = draft.outputSize;
    if (items.isEmpty || out.isEmpty) return const SizedBox.shrink();
    final n = items.length;
    final cols = draft.layout.columns <= 0
        ? n
        : (draft.layout.columns < n ? draft.layout.columns : n);
    final gap = draft.gap.toDouble();
    final cellW = (out.width - gap * (cols + 1)) / cols;
    final rows = (n + cols - 1) ~/ cols;
    final cellH = (out.height - gap * (rows + 1)) / rows;
    final bg = parseHexColor(draft.background) ?? const Color(0x00000000);
    return FittedBox(
      child: SizedBox(
        width: out.width,
        height: out.height,
        child: CustomPaint(
          painter: _CheckerPainter(cell: out.shortestSide / 16),
          child: Container(
            color: bg,
            child: Stack(
              children: [
                for (var i = 0; i < n; i++)
                  Positioned(
                    left: gap + (i % cols) * (cellW + gap),
                    top: gap + (i ~/ cols) * (cellH + gap),
                    width: cellW,
                    height: cellH,
                    child: Image.memory(
                      items[i].bytes,
                      fit: BoxFit.contain,
                      cacheWidth: 400,
                      gaplessPlayback: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Light/grey checkerboard standing in for transparency.
class _CheckerPainter extends CustomPainter {
  _CheckerPainter({required this.cell});

  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final grey = Paint()..color = const Color(0xFFD6D6D6);
    final step = cell <= 0 ? 8.0 : cell;
    for (var y = 0; y * step < size.height; y++) {
      for (var x = y.isOdd ? 1 : 0; x * step < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * step, y * step, step, step), grey);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => old.cell != cell;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, required this.fg});

  final String text;
  final Color color;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AnvilRadii.chip),
    ),
    child: Text(text, style: AnvilText.mono(10, color: fg)),
  );
}

/// Dashed '+' tile ending the strip.
class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return Tooltip(
      message: 'Add images',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AnvilRadii.control),
        child: CustomPaint(
          painter: _DashedBorder(color: c.faint),
          child: SizedBox(
            width: 72,
            height: 72,
            child: Icon(Icons.add, color: c.iconStrong),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          const Radius.circular(AnvilRadii.control),
        ),
      );
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// A layout tile: a little picture of the arrangement over its name.
class _LayoutTile extends StatelessWidget {
  const _LayoutTile({
    required this.layout,
    required this.on,
    required this.onTap,
  });

  final CollageLayout layout;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final fg = on ? c.onAccent : c.iconStrong;
    final (rows, cols) = switch (layout) {
      CollageLayout.oneRow => (1, 3),
      CollageLayout.twoColumns => (2, 2),
      CollageLayout.threeColumns => (2, 3),
      CollageLayout.oneColumn => (3, 1),
    };
    return Tooltip(
      message: layout.label,
      child: Material(
        color: on ? c.accent : c.container,
        borderRadius: BorderRadius.circular(AnvilRadii.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                SizedBox(
                  width: 36,
                  height: 28,
                  child: Column(
                    children: [
                      for (var r = 0; r < rows; r++)
                        Expanded(
                          child: Row(
                            children: [
                              for (var k = 0; k < cols; k++)
                                Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.all(1),
                                    decoration: BoxDecoration(
                                      color: fg,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  layout.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: on ? c.onAccent : c.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A background swatch; transparent shows a checker.
class _BgSwatch extends StatelessWidget {
  const _BgSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (color.a > 0) {
      return WsSwatch(color: color, selected: selected, onTap: onTap);
    }
    final c = Theme.of(context).extension<AnvilColors>()!;
    return Tooltip(
      message: 'Transparent',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AnvilRadii.chip),
            border: Border.all(
              color: selected ? c.accent : c.faint,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(painter: _CheckerPainter(cell: 7)),
        ),
      ),
    );
  }
}

/// Small sheet to type a hex colour.
class _HexSheet extends StatefulWidget {
  const _HexSheet({required this.initial});

  final String initial;

  @override
  State<_HexSheet> createState() => _HexSheetState();
}

class _HexSheetState extends State<_HexSheet> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final parsed = parseHexColor(_ctl.text);
    return WsSheetFrame(
      title: 'Background colour',
      sub: '#RRGGBB or #AARRGGBB',
      children: [
        TextField(
          controller: _ctl,
          autofocus: true,
          style: AnvilText.mono(16, color: c.onSurface),
          decoration: InputDecoration(
            errorText: parsed == null ? 'Not a hex colour' : null,
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (parsed != null) Navigator.of(context).pop(parsed);
          },
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Use colour',
          onPressed: parsed == null
              ? null
              : () => Navigator.of(context).pop(parsed),
        ),
      ],
    );
  }
}
