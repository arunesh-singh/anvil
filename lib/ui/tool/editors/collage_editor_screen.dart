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
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// WYSIWYG editor for `image/collage-maker` and `image/combine-maker`: reorder
/// thumbnails and pick a column count, with a live Flutter-side preview that
/// replicates the native grid layout. The underlying grid module is unchanged.
class CollageEditorScreen extends ConsumerStatefulWidget {
  const CollageEditorScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<CollageEditorScreen> createState() =>
      _CollageEditorScreenState();
}

class _CollageEditorScreenState extends ConsumerState<CollageEditorScreen> {
  final List<InputFile> _files = [];
  final List<Uint8List> _bytes = [];
  final List<Size> _sizes = [];
  late int _columns;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.tool.meta.params;
    _columns = p.isNotEmpty ? p.first.defaultValue : 2;
    final shared = ref.read(pendingSharedInputProvider);
    if (shared != null && _matches(shared)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pendingSharedInputProvider.notifier).state = null;
      });
      _load([shared]);
    }
  }

  bool _matches(InputFile f) {
    final dot = f.name.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = f.name.substring(dot + 1).toLowerCase();
    return widget.tool.meta.acceptedExtensions.contains(ext);
  }

  Future<Size> _decodeSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final size = Size(img.width.toDouble(), img.height.toDouble());
    img.dispose();
    return size;
  }

  Future<void> _load(List<InputFile> picked, {bool append = false}) async {
    setState(() => _loading = true);
    final fs = getIt<FileService>();
    final added = <(InputFile, Uint8List, Size)>[];
    for (final f in picked) {
      final b = await fs.readBytes(f.path) as Uint8List;
      added.add((f, b, await _decodeSize(b)));
    }
    setState(() {
      if (!append) {
        _files.clear();
        _bytes.clear();
        _sizes.clear();
      }
      for (final (f, b, s) in added) {
        _files.add(f);
        _bytes.add(b);
        _sizes.add(s);
      }
      _loading = false;
    });
  }

  Future<void> _pick({bool append = false}) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.tool.meta.acceptedExtensions,
    );
    final picked = [
      for (final f in files)
        if (f.path != null) InputFile(path: f.path!, name: f.name),
    ];
    if (picked.isEmpty) return;
    await _load(picked, append: append);
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      _files.insert(newIndex, _files.removeAt(oldIndex));
      _bytes.insert(newIndex, _bytes.removeAt(oldIndex));
      _sizes.insert(newIndex, _sizes.removeAt(oldIndex));
    });
  }

  void _run() {
    if (_files.length < 2) return;
    ref.read(jobProvider.notifier).start(
          widget.tool,
          ToolInput(files: List.of(_files), params: {'columns': _columns}),
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
          if (_files.isEmpty)
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 220,
                  child: PrimaryButton(
                    label: 'Pick images',
                    icon: Icons.dashboard,
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
                padding: const EdgeInsets.all(12),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Center(child: _preview(context)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(height: 76, child: _reorderStrip(context)),
            const SizedBox(height: 12),
            StepperField(
              label: 'Columns (0 = one row)',
              value: _columns,
              min: 0,
              onChanged: (v) => setState(() => _columns = v),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Add images',
              icon: Icons.add_photo_alternate,
              onPressed: () => _pick(append: true),
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
            onPressed: _files.length >= 2 ? _run : null,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Live layout preview matching `ImageChannel.grid`: cellW×cellH cells (max
  /// thumbnail dims), fit-centered images, rows = ceil(n/cols).
  Widget _preview(BuildContext context) {
    final n = _bytes.length;
    if (n == 0) return const SizedBox.shrink();
    final cols = _columns <= 0 ? n : (_columns < n ? _columns : n);
    final rows = (n + cols - 1) ~/ cols;
    final cellW = _sizes.map((s) => s.width).reduce((a, b) => a > b ? a : b);
    final cellH = _sizes.map((s) => s.height).reduce((a, b) => a > b ? a : b);
    final totalW = cellW * cols;
    final totalH = cellH * rows;
    final c = Theme.of(context).extension<AnvilColors>()!;
    return AspectRatio(
      aspectRatio: totalW <= 0 || totalH <= 0 ? 1 : totalW / totalH,
      child: Column(
        children: [
          for (var r = 0; r < rows; r++)
            Expanded(
              child: Row(
                children: [
                  for (var col = 0; col < cols; col++)
                    Expanded(
                      child: Builder(builder: (_) {
                        final i = r * cols + col;
                        if (i >= n) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.all(1),
                          child: Container(
                            color: c.containerHigh,
                            child: Image.memory(_bytes[i], fit: BoxFit.contain),
                          ),
                        );
                      }),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _reorderStrip(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      itemCount: _files.length,
      onReorderItem: _reorder,
      itemBuilder: (context, i) {
        return ReorderableDelayedDragStartListener(
          key: ValueKey(_files[i].path + i.toString()),
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              width: 68,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AnvilRadii.chip),
                border: Border.all(color: c.faint),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(_bytes[i], fit: BoxFit.cover),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      color: c.accent.withValues(alpha: 0.85),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      child: Text('${i + 1}',
                          style: AnvilText.mono(10, color: c.onAccent)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
