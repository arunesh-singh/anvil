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

/// WYSIWYG editor for `image/split`: overlays the cut grid so the user sees
/// exactly where tiles land. The underlying `split` module is unchanged.
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
  late int _rows;
  late int _cols;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _rows = _defaultFor('rows', 2);
    _cols = _defaultFor('cols', 2);
    final shared = ref.read(pendingSharedInputProvider);
    if (shared != null && _matches(shared)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pendingSharedInputProvider.notifier).state = null;
      });
      _load(shared);
    }
  }

  int _defaultFor(String key, int fallback) {
    for (final p in widget.tool.meta.params) {
      if (p.key == key) return p.defaultValue;
    }
    return fallback;
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

  void _run() {
    final f = _file;
    if (f == null) return;
    ref.read(jobProvider.notifier).start(
          widget.tool,
          ToolInput(files: [f], params: {'rows': _rows, 'cols': _cols}),
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
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 220,
                  child: PrimaryButton(
                    label: 'Pick image',
                    icon: Icons.grid_on,
                    onPressed: _pick,
                  ),
                ),
              ),
            )
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
                        builder: (ctx, rect, px) => IgnorePointer(
                          child: CustomPaint(
                            painter: _GridPainter(
                              rect: rect,
                              rows: _rows,
                              cols: _cols,
                              color: c.accent,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StepperField(
                    label: 'Rows',
                    value: _rows,
                    min: 1,
                    onChanged: (v) => setState(() => _rows = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StepperField(
                    label: 'Columns',
                    value: _cols,
                    min: 1,
                    onChanged: (v) => setState(() => _cols = v),
                  ),
                ),
              ],
            ),
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
}

/// Draws `rows-1` horizontal and `cols-1` vertical guides across [rect].
class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.rect,
    required this.rows,
    required this.cols,
    required this.color,
  });

  final Rect rect;
  final int rows;
  final int cols;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (var r = 1; r < rows; r++) {
      final y = rect.top + rect.height * r / rows;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
    for (var col = 1; col < cols; col++) {
      final x = rect.left + rect.width * col / cols;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.rect != rect ||
      old.rows != rows ||
      old.cols != cols ||
      old.color != color;
}
