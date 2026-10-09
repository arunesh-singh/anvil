/// WYSIWYG editor for `pdf/add-images`: pick the PDF first, then add an image
/// from Photos / Camera / Files, optionally crop & rotate it, and drag/resize
/// the stamp onto the page. Only geometry is collected — the underlying
/// `_PdfPlusImage` module is unchanged. Signing lives in the PDF workspace.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart' show PdfPageInfo;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/editor_scaffold.dart';
import 'package:anvil/ui/tool/editors/image_edit_screen.dart';
import 'package:anvil/ui/tool/image_canvas.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/pdf_geometry.dart';
import 'package:anvil/ui/widgets/slab.dart';

class PdfStampEditorScreen extends ConsumerStatefulWidget {
  const PdfStampEditorScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<PdfStampEditorScreen> createState() =>
      _PdfStampEditorScreenState();
}

class _PdfStampEditorScreenState extends ConsumerState<PdfStampEditorScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();

  InputFile? _pdfFile;
  InputFile? _imageFile;
  Uint8List? _pdfBytes;
  Uint8List? _imageBytes;
  Size _imagePx = Size.zero;
  List<PdfPageInfo> _pages = const [];
  final Map<int, Uint8List> _pageCache = {};

  int _page = 0;
  Uint8List? _pagePng;
  Rect? _stamp; // canvas coords
  Rect _displayRect = Rect.zero;
  Size _pagePt = Size.zero;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final shared = ref.read(pendingSharedInputProvider);
    if (shared != null && _ext(shared.name) == 'pdf') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pendingSharedInputProvider.notifier).state = null;
      });
      _loadPdf(shared);
    }
  }

  String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  Future<void> _pickPdf() async {
    final res = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = res?.path;
    final name = res?.name;
    if (path == null || name == null) return;
    await _loadPdf(InputFile(path: path, name: name));
  }

  Future<void> _loadPdf(InputFile f) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await getIt<FileService>().readBytes(f.path) as Uint8List;
      final pages = await getIt<PdfEngine>().pageInfos(bytes);
      setState(() {
        _pdfFile = f;
        _pdfBytes = bytes;
        _pages = pages;
        _pageCache.clear();
        _page = 0;
        _pagePng = null;
        _stamp = null;
        _loading = false;
      });
      await _renderCurrentPage();
    } on ToolException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<Size> _decodeSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final size = Size(img.width.toDouble(), img.height.toDouble());
    img.dispose();
    return size;
  }

  Future<void> _renderCurrentPage() async {
    final bytes = _pdfBytes;
    if (bytes == null) return;
    final cached = _pageCache[_page];
    if (cached != null) {
      setState(() => _pagePng = cached);
      return;
    }
    setState(() {
      _loading = true;
      _pagePng = null;
    });
    try {
      final out = await getIt<PdfEngine>().renderPage(bytes, _page);
      _pageCache[_page] = out.bytes;
      setState(() {
        _pagePng = out.bytes;
        _loading = false;
      });
    } on ToolException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _goPage(int delta) {
    final next = (_page + delta).clamp(0, _pages.length - 1);
    if (next == _page) return;
    setState(() {
      _page = next;
      _stamp = null; // reposition on the new page
    });
    _renderCurrentPage();
  }

  Future<void> _addImage() async {
    final Uint8List? edited;
    try {
      edited = await pickAndEditImage(context, _picker);
    } catch (_) {
      setState(() => _error = 'Could not load the image.');
      return;
    }
    if (edited == null) return;
    await _setImage(edited);
  }

  Future<void> _setImage(Uint8List bytes) async {
    try {
      final size = await _decodeSize(bytes);
      final file = await getIt<FileService>().writeBytes('stamp.png', bytes);
      setState(() {
        _imageBytes = bytes;
        _imagePx = size;
        _imageFile = InputFile(path: file.path, name: 'stamp.png');
        _stamp = null;
      });
    } catch (_) {
      setState(() => _error = 'Could not load the image.');
    }
  }

  Offset _toCanvas(Offset global) {
    final box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
    return box.globalToLocal(global);
  }

  void _dragBody(Offset delta) {
    final r = _stamp!;
    var tl = r.topLeft + delta;
    final cx = (tl.dx + r.width / 2).clamp(
      _displayRect.left,
      _displayRect.right,
    );
    final cy = (tl.dy + r.height / 2).clamp(
      _displayRect.top,
      _displayRect.bottom,
    );
    tl = Offset(cx - r.width / 2, cy - r.height / 2);
    _stamp = tl & r.size;
  }

  void _resize(Offset global) {
    final r = _stamp!;
    final p = _toCanvas(global);
    final w = (p.dx - r.left).clamp(24.0, double.infinity);
    final aspect = _imagePx.width <= 0 ? 1.0 : _imagePx.height / _imagePx.width;
    final h = w * aspect;
    _stamp = Rect.fromLTWH(r.left, r.top, w, h);
  }

  void _run() {
    final pdf = _pdfFile;
    final image = _imageFile;
    final stamp = _stamp;
    if (pdf == null ||
        image == null ||
        stamp == null ||
        _displayRect.width <= 0) {
      return;
    }
    final r = canvasRectToPdf(stamp, _displayRect, _pagePt);
    ref
        .read(jobProvider.notifier)
        .start(
          widget.tool,
          ToolInput(
            files: [pdf, image],
            params: {
              'page': _page + 1,
              'x': r.x.round(),
              'y': r.y.round(),
              'width': r.width.round(),
              'height': r.height.round(),
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return EditorScaffold(job: ref.watch(jobProvider), builder: _buildIdle);
  }

  Widget _buildIdle(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final job = ref.watch(jobProvider);
    final hasPage = _pdfBytes != null && _pagePng != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          EditorHeader(title: widget.tool.meta.label),
          const SizedBox(height: 16),
          if (_pdfBytes == null)
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 240,
                  child: PrimaryButton(
                    label: 'Pick PDF',
                    icon: Icons.picture_as_pdf,
                    onPressed: _pickPdf,
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
                child: _loading || _pagePng == null
                    ? const Center(child: CircularProgressIndicator())
                    : ImageCanvas(
                        imageBytes: _pagePng!,
                        imagePx: Size(
                          _pages[_page].width,
                          _pages[_page].height,
                        ),
                        builder: _overlay,
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _pager(context),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: _imageFile == null ? 'Add image' : 'Change image',
                    icon: Icons.add_photo_alternate,
                    onPressed: hasPage ? _addImage : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SecondaryButton(
                    label: 'Swap PDF',
                    icon: Icons.swap_horiz,
                    onPressed: _pickPdf,
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: c.error)),
          ],
          if (job is JobFailed) ...[
            const SizedBox(height: 12),
            Text(job.message, style: TextStyle(color: c.error)),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Run',
            icon: Icons.arrow_forward,
            onPressed: _imageFile != null && _stamp != null ? _run : null,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _pager(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final n = _pages.length;
    return SlabPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            color: c.iconStrong,
            onPressed: _page > 0 ? () => _goPage(-1) : null,
          ),
          Expanded(
            child: Text(
              n == 0 ? '—' : 'Page ${_page + 1} / $n',
              textAlign: TextAlign.center,
              style: AnvilText.mono(14, color: c.onSurface),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: c.iconStrong,
            onPressed: _page < n - 1 ? () => _goPage(1) : null,
          ),
        ],
      ),
    );
  }

  Widget _overlay(BuildContext context, Rect displayRect, Size imagePx) {
    _displayRect = displayRect;
    _pagePt = imagePx;
    final c = Theme.of(context).extension<AnvilColors>()!;
    if (_stamp == null && _imagePx.width > 0) {
      final w = displayRect.width * 0.4;
      final h = w * (_imagePx.height / _imagePx.width);
      _stamp = Rect.fromCenter(center: displayRect.center, width: w, height: h);
    }
    final stamp = _stamp;
    return SizedBox.expand(
      key: _canvasKey,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (stamp != null && _imageBytes != null) ...[
            Positioned.fromRect(
              rect: stamp,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => setState(() => _dragBody(d.delta)),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Image.memory(_imageBytes!, fit: BoxFit.fill),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: c.accent, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: stamp.right - 14,
              top: stamp.bottom - 14,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => _resize(d.globalPosition)),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.open_in_full, size: 16, color: c.onAccent),
                ),
              ),
            ),
          ] else if (_imageBytes == null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: c.containerHigh.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(AnvilRadii.chip),
                ),
                child: Text(
                  'Add an image to place',
                  style: TextStyle(color: c.onSurface),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
