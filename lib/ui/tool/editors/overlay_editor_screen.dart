import 'dart:math' as math;
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

/// One overlay placed on the base image, in canvas (display) coordinates.
class _Layer {
  _Layer(this.fileIndex);
  final int fileIndex;
  Offset? topLeft; // null until first laid out
  Size size = Size.zero;
  double rotationDeg = 0;
}

/// Flagship WYSIWYG editor for `image/add-images`: the user sees the base image
/// and drags / resizes / rotates each overlay before compositing.
class OverlayEditorScreen extends ConsumerStatefulWidget {
  const OverlayEditorScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<OverlayEditorScreen> createState() =>
      _OverlayEditorScreenState();
}

class _OverlayEditorScreenState extends ConsumerState<OverlayEditorScreen> {
  final List<InputFile> _files = [];
  final List<Uint8List> _bytes = [];
  final List<Size> _sizes = [];
  final List<_Layer> _layers = [];
  final GlobalKey _canvasKey = GlobalKey();

  int? _selected; // index into _layers
  bool _holdAspect = true;
  Rect _displayRect = Rect.zero;
  Size _baseImagePx = Size.zero;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
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
        _layers.clear();
        _selected = null;
      }
      for (final (f, b, s) in added) {
        _files.add(f);
        _bytes.add(b);
        _sizes.add(s);
      }
      _rebuildLayers();
      _loading = false;
    });
  }

  /// One layer per overlay file (indices 1..n); placements reset.
  void _rebuildLayers() {
    _layers.clear();
    for (var i = 1; i < _files.length; i++) {
      _layers.add(_Layer(i));
    }
    _selected = _layers.isEmpty ? null : _layers.length - 1;
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

  void _setAsBase(int fileIndex) {
    if (fileIndex == 0) return;
    setState(() {
      final f = _files.removeAt(fileIndex);
      final b = _bytes.removeAt(fileIndex);
      final s = _sizes.removeAt(fileIndex);
      _files.insert(0, f);
      _bytes.insert(0, b);
      _sizes.insert(0, s);
      _rebuildLayers();
    });
  }

  void _deleteSelected() {
    final i = _selected;
    if (i == null) return;
    setState(() {
      final fileIndex = _layers[i].fileIndex;
      _files.removeAt(fileIndex);
      _bytes.removeAt(fileIndex);
      _sizes.removeAt(fileIndex);
      _rebuildLayers();
    });
  }

  void _bringToFront() {
    final i = _selected;
    if (i == null || i == _layers.length - 1) return;
    setState(() {
      final l = _layers.removeAt(i);
      _layers.add(l);
      _selected = _layers.length - 1;
    });
  }

  Offset _toCanvas(Offset global) {
    final box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
    return box.globalToLocal(global);
  }

  void _run() {
    if (_files.length < 2 || _displayRect.width <= 0) return;
    final scale = _baseImagePx.width / _displayRect.width;
    final layers = <Map<String, Object?>>[];
    for (final l in _layers) {
      final tl = l.topLeft;
      if (tl == null || l.size.width <= 0 || l.size.height <= 0) continue;
      final rel = tl - _displayRect.topLeft;
      layers.add({
        'fileIndex': l.fileIndex,
        'x': (rel.dx * scale).round(),
        'y': (rel.dy * scale).round(),
        'width': (l.size.width * scale).round(),
        'height': (l.size.height * scale).round(),
        'rotation': l.rotationDeg,
      });
    }
    ref.read(jobProvider.notifier).start(
          widget.tool,
          ToolInput(files: List.of(_files), params: {'layers': layers}),
        );
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(jobProvider);
    return EditorScaffold(job: job, builder: _buildIdle);
  }

  Widget _buildIdle(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.extension<AnvilColors>()!;
    final job = ref.watch(jobProvider);
    final hasBase = _files.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          EditorHeader(title: widget.tool.meta.label),
          const SizedBox(height: 16),
          if (!hasBase)
            _pickPrompt(context)
          else ...[
            _thumbnails(context),
            const SizedBox(height: 12),
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
                        imageBytes: _bytes.first,
                        imagePx: _sizes.first,
                        builder: _canvasOverlay,
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _controls(context),
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



  Widget _pickPrompt(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pick a base image and one or more overlays.',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 220,
              child: PrimaryButton(
                label: 'Pick images',
                icon: Icons.add_photo_alternate,
                onPressed: _pick,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnails(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _files.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isBase = i == 0;
          final layerIndex = _layers.indexWhere((l) => l.fileIndex == i);
          final selected = layerIndex != -1 && layerIndex == _selected;
          return GestureDetector(
            onTap: () => setState(() {
              if (layerIndex != -1) _selected = layerIndex;
            }),
            child: Container(
              width: 68,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AnvilRadii.chip),
                border: Border.all(
                  color: selected ? c.accent : c.faint,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(_bytes[i], fit: BoxFit.cover),
                  if (isBase)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: c.accent.withValues(alpha: 0.85),
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text('BASE',
                            textAlign: TextAlign.center,
                            style: AnvilText.mono(9, color: c.onAccent)),
                      ),
                    )
                  else
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => _setAsBase(i),
                        child: Container(
                          color: c.container.withValues(alpha: 0.8),
                          padding: const EdgeInsets.all(2),
                          child: Icon(Icons.push_pin,
                              size: 14, color: c.iconStrong),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final hasSel = _selected != null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(context, Icons.add_photo_alternate, 'Add', _pick),
        _chip(context, Icons.delete_outline, 'Delete',
            hasSel ? _deleteSelected : null),
        _chip(context, Icons.flip_to_front, 'To front',
            hasSel ? _bringToFront : null),
        _chip(
          context,
          _holdAspect ? Icons.lock : Icons.lock_open,
          _holdAspect ? 'Aspect' : 'Free',
          () => setState(() => _holdAspect = !_holdAspect),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label,
      VoidCallback? onTap) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final enabled = onTap != null;
    return Material(
      color: c.container,
      borderRadius: BorderRadius.circular(AnvilRadii.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18, color: enabled ? c.iconStrong : c.faint),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: enabled ? c.onSurface : c.faint, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _canvasOverlay(BuildContext context, Rect displayRect, Size imagePx) {
    _displayRect = displayRect;
    _baseImagePx = imagePx;
    // Place any not-yet-laid-out layers now that the display rect is known.
    for (final l in _layers) {
      if (l.topLeft == null) {
        final px = _sizes[l.fileIndex];
        final w = displayRect.width * 0.4;
        final h = px.width <= 0 ? w : w * (px.height / px.width);
        l.size = Size(w, h);
        l.topLeft = displayRect.center - Offset(w / 2, h / 2);
      }
    }
    return SizedBox.expand(
      key: _canvasKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = null),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < _layers.length; i++)
              _buildLayer(context, i),
          ],
        ),
      ),
    );
  }

  Widget _buildLayer(BuildContext context, int i) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final l = _layers[i];
    final tl = l.topLeft!;
    final selected = i == _selected;
    return Positioned(
      left: tl.dx,
      top: tl.dy,
      width: l.size.width,
      height: l.size.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = i),
        onPanUpdate: (d) => setState(() => _dragBody(l, d.delta)),
        child: Transform.rotate(
          angle: l.rotationDeg * math.pi / 180,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Image.memory(_bytes[l.fileIndex], fit: BoxFit.fill),
              ),
              if (selected) ...[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: c.accent, width: 2),
                    ),
                  ),
                ),
                // Resize (bottom-right)
                Positioned(
                  right: -14,
                  bottom: -14,
                  child: _handle(context, Icons.open_in_full,
                      (d) => setState(() => _resize(l, d.globalPosition))),
                ),
                // Rotate (top-right)
                Positioned(
                  right: -14,
                  top: -14,
                  child: _handle(context, Icons.rotate_right,
                      (d) => setState(() => _rotate(l, d.globalPosition))),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle(BuildContext context, IconData icon,
      void Function(DragUpdateDetails) onPanUpdate) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return GestureDetector(
      onPanUpdate: onPanUpdate,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: c.accent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: c.onAccent),
      ),
    );
  }

  void _dragBody(_Layer l, Offset delta) {
    var tl = l.topLeft! + delta;
    final center = tl + Offset(l.size.width / 2, l.size.height / 2);
    final cx = center.dx.clamp(_displayRect.left, _displayRect.right);
    final cy = center.dy.clamp(_displayRect.top, _displayRect.bottom);
    tl = Offset(cx, cy) - Offset(l.size.width / 2, l.size.height / 2);
    l.topLeft = tl;
  }

  void _resize(_Layer l, Offset globalPos) {
    final p = _toCanvas(globalPos);
    final center = l.topLeft! + Offset(l.size.width / 2, l.size.height / 2);
    final v = p - center;
    final rad = -l.rotationDeg * math.pi / 180;
    final lx = v.dx * math.cos(rad) - v.dy * math.sin(rad);
    final ly = v.dx * math.sin(rad) + v.dy * math.cos(rad);
    var w = (lx.abs() * 2).clamp(24.0, double.infinity);
    var h = (ly.abs() * 2).clamp(24.0, double.infinity);
    if (_holdAspect) {
      final px = _sizes[l.fileIndex];
      h = px.width <= 0 ? w : w * (px.height / px.width);
    }
    l.size = Size(w, h);
    l.topLeft = center - Offset(w / 2, h / 2);
  }

  void _rotate(_Layer l, Offset globalPos) {
    final p = _toCanvas(globalPos);
    final center = l.topLeft! + Offset(l.size.width / 2, l.size.height / 2);
    final v = p - center;
    l.rotationDeg = math.atan2(v.dy, v.dx) * 180 / math.pi + 90;
  }
}
