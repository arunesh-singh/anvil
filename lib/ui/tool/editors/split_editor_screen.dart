/// The Split screen (design `explorations/tools-workspace.html`, frame "Split
/// into grid"): the photo with the live cut grid and tile numbers, named
/// presets for feeds and carousels, each tile's size and the file count
/// spelled out, and Run saying how many files it makes.
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
import 'package:anvil/ui/tool/editors/split_presets.dart';
import 'package:anvil/ui/tool/editors/tool_frame.dart';
import 'package:anvil/ui/tool/editors/tool_stage.dart';
import 'package:anvil/ui/tool/image_canvas.dart';
import 'package:anvil/ui/tool/input/input_picker.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

class SplitEditorScreen extends ConsumerStatefulWidget {
  const SplitEditorScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<SplitEditorScreen> createState() => _SplitEditorScreenState();
}

class _SplitEditorScreenState extends ConsumerState<SplitEditorScreen> {
  InputFile? _file;
  Uint8List? _bytes;
  Size _imagePx = Size.zero;
  SplitPreset _preset = SplitPreset.grid3x3;
  int _customRows = 2;
  int _customCols = 2;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    final shared = takeSharedInput(ref, widget.tool.meta);
    if (shared != null) _load(shared);
  }

  Future<void> _load(InputFile f) async {
    final seq = ++_loadSeq;
    final b = Uint8List.fromList(await getIt<FileService>().readBytes(f.path));
    final codec = await ui.instantiateImageCodec(b);
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    codec.dispose();
    if (seq != _loadSeq || !mounted) return;
    setState(() {
      _file = f;
      _bytes = b;
      _imagePx = size;
    });
  }

  SplitPlan get _plan => SplitPlan(
    width: _imagePx.width.round(),
    height: _imagePx.height.round(),
    rows: _preset == SplitPreset.custom ? _customRows : _preset.rows,
    cols: _preset == SplitPreset.custom ? _customCols : _preset.cols,
  );

  void _run() {
    final f = _file;
    if (f == null) return;
    ref
        .read(jobProvider.notifier)
        .start(widget.tool, ToolInput(files: [f], params: _plan.params));
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final ready = _bytes != null;
    return ToolFrame(
      tool: widget.tool,
      hasInput: ready,
      onPicked: (files) => _load(files.first),
      scroll: false,
      runLabel: 'Split into ${plan.files}',
      onRun: ready && plan.files > 1 ? _run : null,
      body: ready ? _body(context, plan) : const SizedBox.shrink(),
    );
  }

  Widget _body(BuildContext context, SplitPlan plan) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: StagePanel(
            child: ImageCanvas(
              imageBytes: _bytes!,
              imagePx: _imagePx,
              builder: (ctx, rect, px) => IgnorePointer(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _GridPainter(
                    rect: rect,
                    rows: plan.rows,
                    cols: plan.cols,
                    line: Colors.white,
                    badge: c.accent,
                    badgeText: c.onAccent,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        WsPillRail(
          children: [
            for (final p in SplitPreset.values)
              WsPill(
                label: p.label,
                on: _preset == p,
                onTap: () => setState(() => _preset = p),
              ),
          ],
        ),
        if (_preset == SplitPreset.custom) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StepperField(
                  label: 'Rows',
                  value: _customRows,
                  min: 1,
                  max: 20,
                  onChanged: (v) => setState(() => _customRows = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StepperField(
                  label: 'Columns',
                  value: _customCols,
                  min: 1,
                  max: 20,
                  onChanged: (v) => setState(() => _customCols = v),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text(plan.readout, style: AnvilText.mono(13, color: c.onSurface)),
        if (_preset.feed) ...[
          const SizedBox(height: 4),
          Text(
            'Numbered in posting order — upload ${plan.files} first for a '
            'grid feed.',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
        ] else if (_preset != SplitPreset.custom) ...[
          const SizedBox(height: 4),
          Text(
            'Swipe order — tile 1 opens the carousel.',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
        ],
      ],
    );
  }
}

/// The cut lines across [rect] and a numbered badge in each tile
/// (row-major, matching the output file names).
class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.rect,
    required this.rows,
    required this.cols,
    required this.line,
    required this.badge,
    required this.badgeText,
  });

  final Rect rect;
  final int rows;
  final int cols;
  final Color line;
  final Color badge;
  final Color badgeText;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1.5;
    for (var r = 1; r < rows; r++) {
      final y = rect.top + rect.height * r / rows;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
    for (var col = 1; col < cols; col++) {
      final x = rect.left + rect.width * col / cols;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    }
    final cellW = rect.width / cols;
    final cellH = rect.height / rows;
    // Badges only while they fit their tile.
    if (cellW < 22 || cellH < 22) return;
    final fill = Paint()..color = badge;
    for (var r = 0; r < rows; r++) {
      for (var col = 0; col < cols; col++) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${r * cols + col + 1}',
            style: AnvilText.mono(11, color: badgeText),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final center = Offset(
          rect.left + cellW * (col + 0.5),
          rect.top + cellH * (r + 0.5),
        );
        final w = tp.width + 12 < 20 ? 20.0 : tp.width + 12;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: w, height: 20),
            const Radius.circular(10),
          ),
          fill,
        );
        tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
        tp.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.rect != rect ||
      old.rows != rows ||
      old.cols != cols ||
      old.line != line ||
      old.badge != badge ||
      old.badgeText != badgeText;
}
