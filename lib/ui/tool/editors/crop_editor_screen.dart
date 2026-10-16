/// The Crop screen (design `explorations/tools-workspace.html`, frame "Crop"):
/// the photo in its current orientation with a rule-of-thirds box, ratio
/// presets that snap it, rotate/flip on the stage bar, the size as two
/// editable numbers, and Run saying the output size. Geometry lives in
/// [CropDraft].
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
import 'package:anvil/ui/tool/editors/crop_geometry.dart';
import 'package:anvil/ui/tool/editors/tool_frame.dart';
import 'package:anvil/ui/tool/editors/tool_stage.dart';
import 'package:anvil/ui/tool/input/input_picker.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';

class CropEditorScreen extends ConsumerStatefulWidget {
  const CropEditorScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<CropEditorScreen> createState() => _CropEditorScreenState();
}

class _CropEditorScreenState extends ConsumerState<CropEditorScreen> {
  InputFile? _file;
  Uint8List? _bytes;
  CropDraft? _draft;
  final List<CropDraft> _undo = [];
  int _loadSeq = 0;

  /// The stage mapping from the last layout, for converting drag deltas.
  CropMapping? _mapping;

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
      _draft = CropDraft.initial(size);
      _undo.clear();
    });
  }

  void _apply(CropDraft next) {
    setState(() {
      _undo.add(_draft!);
      _draft = next;
    });
  }

  void _run() {
    final f = _file;
    final d = _draft;
    if (f == null || d == null) return;
    ref
        .read(jobProvider.notifier)
        .start(widget.tool, ToolInput(files: [f], params: d.params));
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    final px = d?.pixels;
    return ToolFrame(
      tool: widget.tool,
      hasInput: d != null,
      onPicked: (files) => _load(files.first),
      actions: [
        WsChip(
          icon: Icons.undo,
          tooltip: 'Undo',
          onTap: _undo.isEmpty
              ? null
              : () => setState(() => _draft = _undo.removeLast()),
        ),
      ],
      scroll: false,
      runLabel: 'Crop',
      runDetail: px == null ? null : '· ${px.width} × ${px.height} px',
      onRun: d == null ? null : _run,
      body: d == null ? const SizedBox.shrink() : _body(context, d),
    );
  }

  Widget _body(BuildContext context, CropDraft d) {
    final px = d.pixels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: StagePanel(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 56),
            bar: [
              StagePill(
                icon: Icons.rotate_left,
                tooltip: 'Rotate left',
                onTap: () => _apply(d.rotateLeft()),
              ),
              StagePill(
                icon: Icons.flip,
                tooltip: 'Flip',
                onTap: () => _apply(d.toggleFlip()),
              ),
              StagePill(label: d.ratioLabel),
            ],
            child: _stage(context, d),
          ),
        ),
        const SizedBox(height: 12),
        WsPillRail(
          children: [
            for (final r in CropRatio.values)
              WsPill(
                label: r.label,
                on: d.ratio == r,
                onTap: () => _apply(d.withRatio(r)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: NumberBox(
                label: 'Width',
                value: px.width,
                suffix: 'px',
                onChanged: (v) => _apply(d.resize(width: v)),
              ),
            ),
            const SizedBox(width: 8),
            LinkToggle(on: d.locked, onTap: () => _apply(d.toggleLock())),
            const SizedBox(width: 8),
            Expanded(
              child: NumberBox(
                label: 'Height',
                value: px.height,
                suffix: 'px',
                onChanged: (v) => _apply(d.resize(height: v)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stage(BuildContext context, CropDraft d) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return LayoutBuilder(
      builder: (context, box) {
        final b = d.bounds;
        final fit = (box.maxWidth / b.width) < (box.maxHeight / b.height)
            ? box.maxWidth / b.width
            : box.maxHeight / b.height;
        final display = Rect.fromCenter(
          center: Offset(box.maxWidth / 2, box.maxHeight / 2),
          width: b.width * fit,
          height: b.height * fit,
        );
        final mapping = _mapping = CropMapping(display, b);
        final crop = mapping.toCanvas(d.rect);
        return SizedBox(
          width: box.maxWidth,
          height: box.maxHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: display,
                child: Transform.flip(
                  flipX: d.flip,
                  child: RotatedBox(
                    quarterTurns: d.rotate ~/ 90,
                    child: Image.memory(
                      _bytes!,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _CropPainter(
                      clip: display,
                      hole: crop,
                      line: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: crop,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => _undo.add(_draft!),
                  onPanUpdate: (e) => setState(
                    () => _draft = _draft!.move(mapping.deltaToPixel(e.delta)),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: c.accent, width: 2),
                    ),
                  ),
                ),
              ),
              for (final corner in CropCorner.values)
                _handle(crop, corner, mapping, c),
            ],
          ),
        );
      },
    );
  }

  Widget _handle(
    Rect crop,
    CropCorner corner,
    CropMapping mapping,
    AnvilColors c,
  ) {
    final at = switch (corner) {
      CropCorner.topLeft => crop.topLeft,
      CropCorner.topRight => crop.topRight,
      CropCorner.bottomLeft => crop.bottomLeft,
      CropCorner.bottomRight => crop.bottomRight,
    };
    // 24 stage px is the smallest box a thumb can still grab.
    final minSide = mapping.deltaToPixel(const Offset(24, 0)).dx;
    return Positioned(
      left: at.dx - 16,
      top: at.dy - 16,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _undo.add(_draft!),
        onPanUpdate: (e) => setState(
          () => _draft = _draft!.dragCorner(
            corner,
            _mapping!.deltaToPixel(e.delta),
            minSide: minSide,
          ),
        ),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dims the photo outside [hole] and draws rule-of-thirds lines inside it.
class _CropPainter extends CustomPainter {
  _CropPainter({required this.clip, required this.hole, required this.line});

  final Rect clip;
  final Rect hole;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(clip),
      Path()..addRect(hole),
    );
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    final p = Paint()
      ..color = line.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = hole.left + hole.width * i / 3;
      final y = hole.top + hole.height * i / 3;
      canvas.drawLine(Offset(x, hole.top), Offset(x, hole.bottom), p);
      canvas.drawLine(Offset(hole.left, y), Offset(hole.right, y), p);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.clip != clip || old.hole != hole || old.line != line;
}
