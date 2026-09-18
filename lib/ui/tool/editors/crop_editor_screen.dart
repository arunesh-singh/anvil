import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/editor_scaffold.dart';
import 'package:anvil/ui/tool/image_canvas.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// WYSIWYG editor for `image/crop`: drag/resize a rectangle over the image;
/// only the geometry is collected — the underlying `crop` module is unchanged.
class CropEditorScreen extends ConsumerStatefulWidget {
  const CropEditorScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<CropEditorScreen> createState() => _CropEditorScreenState();
}

enum _Grip { move, tl, tr, bl, br }

class _CropEditorScreenState extends ConsumerState<CropEditorScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  InputFile? _file;
  Uint8List? _bytes;
  Size _imagePx = Size.zero;
  Rect? _crop; // canvas coords
  Rect _displayRect = Rect.zero;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final shared = ref.read(pendingSharedInputProvider);
    if (shared != null && _matches(shared)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pendingSharedInputProvider.notifier).state = null;
      });
      _load(shared);
    }
  }

  bool _matches(InputFile f) {
    final dot = f.name.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = f.name.substring(dot + 1).toLowerCase();
    return widget.tool.meta.acceptedExtensions.contains(ext);
  }

  Future<void> _load(InputFile f) async {
    setState(() => _loading = true);
    final b = await getIt<FileService>().readBytes(f.path) as Uint8List;
    final codec = await ui.instantiateImageCodec(b);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final size = Size(img.width.toDouble(), img.height.toDouble());
    img.dispose();
    setState(() {
      _file = f;
      _bytes = b;
      _imagePx = size;
      _crop = null;
      _loading = false;
    });
  }

  Future<void> _pick() async {
    final res = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: widget.tool.meta.acceptedExtensions,
    );
    final path = res?.path;
    final name = res?.name;
    if (path == null || name == null) return;
    await _load(InputFile(path: path, name: name));
  }

  void _drag(_Grip grip, Offset delta) {
    var r = _crop!;
    switch (grip) {
      case _Grip.move:
        r = r.shift(delta);
      case _Grip.tl:
        r = Rect.fromLTRB(r.left + delta.dx, r.top + delta.dy, r.right, r.bottom);
      case _Grip.tr:
        r = Rect.fromLTRB(r.left, r.top + delta.dy, r.right + delta.dx, r.bottom);
      case _Grip.bl:
        r = Rect.fromLTRB(r.left + delta.dx, r.top, r.right, r.bottom + delta.dy);
      case _Grip.br:
        r = Rect.fromLTRB(r.left, r.top, r.right + delta.dx, r.bottom + delta.dy);
    }
    // Enforce a 24px min and clamp inside the image display rect.
    const minSz = 24.0;
    var l = r.left.clamp(_displayRect.left, _displayRect.right - minSz);
    var t = r.top.clamp(_displayRect.top, _displayRect.bottom - minSz);
    var rt = r.right.clamp(l + minSz, _displayRect.right);
    var b = r.bottom.clamp(t + minSz, _displayRect.bottom);
    if (grip == _Grip.move) {
      // Preserve size when moving: reclamp as a translation.
      final w = _crop!.width;
      final h = _crop!.height;
      l = r.left.clamp(_displayRect.left, _displayRect.right - w);
      t = r.top.clamp(_displayRect.top, _displayRect.bottom - h);
      rt = l + w;
      b = t + h;
    }
    _crop = Rect.fromLTRB(l, t, rt, b);
  }

  void _run() {
    final f = _file;
    final crop = _crop;
    if (f == null || crop == null || _displayRect.width <= 0) return;
    final scale = _imagePx.width / _displayRect.width;
    final rel = crop.topLeft - _displayRect.topLeft;
    ref.read(jobProvider.notifier).start(
          widget.tool,
          ToolInput(files: [f], params: {
            'x': (rel.dx * scale).round(),
            'y': (rel.dy * scale).round(),
            'width': (crop.width * scale).round(),
            'height': (crop.height * scale).round(),
          }),
        );
  }

  @override
  Widget build(BuildContext context) {
    return EditorScaffold(job: ref.watch(jobProvider), builder: _buildIdle);
  }

  Widget _buildIdle(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final job = ref.watch(jobProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          EditorHeader(title: widget.tool.meta.label),
          const SizedBox(height: 16),
          if (_bytes == null)
            Expanded(child: Center(child: _pickButton()))
          else ...[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: c.container,
                  borderRadius: BorderRadius.circular(AnvilRadii.panel),
                ),
                clipBehavior: Clip.antiAlias,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ImageCanvas(
                        imageBytes: _bytes!,
                        imagePx: _imagePx,
                        builder: _overlay,
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _readout(context),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Swap image',
              icon: Icons.swap_horiz,
              onPressed: _pick,
            ),
          ],
          if (job is JobFailed) ...[
            const SizedBox(height: 12),
            Text(job.message, style: TextStyle(color: c.error)),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Run',
            icon: Icons.arrow_forward,
            onPressed: _bytes != null ? _run : null,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _pickButton() => SizedBox(
        width: 220,
        child: PrimaryButton(
          label: 'Pick image',
          icon: Icons.image,
          onPressed: _pick,
        ),
      );

  Widget _readout(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final crop = _crop;
    String text = '—';
    if (crop != null && _displayRect.width > 0) {
      final scale = _imagePx.width / _displayRect.width;
      text =
          '${(crop.width * scale).round()} × ${(crop.height * scale).round()} px';
    }
    return SlabPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.crop, size: 18, color: c.iconStrong),
          const SizedBox(width: 10),
          Text('Selection: $text',
              style: AnvilText.mono(14, color: c.onSurface)),
        ],
      ),
    );
  }

  Widget _overlay(BuildContext context, Rect displayRect, Size imagePx) {
    _displayRect = displayRect;
    _crop ??= Rect.fromCenter(
      center: displayRect.center,
      width: displayRect.width * 0.6,
      height: displayRect.height * 0.6,
    );
    final crop = _crop!;
    final c = Theme.of(context).extension<AnvilColors>()!;
    return SizedBox.expand(
      key: _canvasKey,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Dim outside the crop rect.
          Positioned.fill(
            child: CustomPaint(
              painter: _DimPainter(crop, Colors.black.withValues(alpha: 0.5)),
            ),
          ),
          Positioned.fromRect(
            rect: crop,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() => _drag(_Grip.move, d.delta)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: c.accent, width: 2),
                ),
              ),
            ),
          ),
          _corner(crop.topLeft, _Grip.tl, c),
          _corner(crop.topRight, _Grip.tr, c),
          _corner(crop.bottomLeft, _Grip.bl, c),
          _corner(crop.bottomRight, _Grip.br, c),
        ],
      ),
    );
  }

  Widget _corner(Offset at, _Grip grip, AnvilColors c) {
    return Positioned(
      left: at.dx - 14,
      top: at.dy - 14,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _drag(grip, d.delta)),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// Dims everything outside [hole].
class _DimPainter extends CustomPainter {
  _DimPainter(this.hole, this.color);
  final Rect hole;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRect(hole);
    final outside = Path.combine(PathOperation.difference, full, inner);
    canvas.drawPath(outside, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DimPainter old) =>
      old.hole != hole || old.color != color;
}
