/// WYSIWYG editor for `pdf/remove-watermark`: drag one rectangle on the first
/// page and erase that region on every page (whole-doc `eraseRegionAllPages`).
/// Crop moved to the PDF workspace; this screen only drives erase.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart' show PdfPageInfo;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/ui/providers.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/editor_scaffold.dart';
import 'package:anvil/ui/tool/editors/rect_handles.dart';
import 'package:anvil/ui/tool/image_canvas.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/pdf_geometry.dart';
import 'package:anvil/ui/widgets/slab.dart';

class PdfRectEditorScreen extends ConsumerStatefulWidget {
  const PdfRectEditorScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<PdfRectEditorScreen> createState() =>
      _PdfRectEditorScreenState();
}

class _PdfRectEditorScreenState extends ConsumerState<PdfRectEditorScreen> {
  final GlobalKey _canvasKey = GlobalKey();

  InputFile? _file;
  Uint8List? _pdfBytes;
  Uint8List? _pagePng;
  List<PdfPageInfo> _pages = const [];

  Rect? _rect; // canvas coords
  Rect _displayRect = Rect.zero;
  Size _pagePt = Size.zero;

  bool _loading = false;
  String? _error;

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

  Future<void> _load(InputFile f) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final e = getIt<PdfEngine>();
      final bytes = await getIt<FileService>().readBytes(f.path) as Uint8List;
      final pages = await e.pageInfos(bytes);
      final page = await e.renderPage(bytes, 0);
      setState(() {
        _file = f;
        _pdfBytes = bytes;
        _pages = pages;
        _pagePng = page.bytes;
        _rect = null;
        _loading = false;
      });
    } on ToolException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _drag(RectGrip grip, Offset delta) {
    _rect = dragRect(_rect!, grip, delta, _displayRect);
  }

  void _run() {
    final f = _file;
    final rect = _rect;
    if (f == null || rect == null || _displayRect.width <= 0) return;
    final r = canvasRectToPdf(rect, _displayRect, _pagePt);
    ref
        .read(jobProvider.notifier)
        .start(
          widget.tool,
          ToolInput(
            files: [f],
            params: {
              'x': r.x.round(),
              'y': r.y.round(),
              'width': r.width.round(),
              'height': r.height.round(),
            },
          ),
        );
  }

  bool get _canRun => _file != null && _rect != null;

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
          if (_pdfBytes == null)
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 220,
                  child: PrimaryButton(
                    label: 'Pick PDF',
                    icon: Icons.picture_as_pdf,
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
                child: _loading || _pagePng == null
                    ? const Center(child: CircularProgressIndicator())
                    : ImageCanvas(
                        imageBytes: _pagePng!,
                        imagePx: Size(_pages[0].width, _pages[0].height),
                        builder: _overlay,
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _readout(context),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Swap PDF',
              icon: Icons.swap_horiz,
              onPressed: _pick,
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
            onPressed: _canRun ? _run : null,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _readout(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final rect = _rect;
    String text = '—';
    if (rect != null && _displayRect.width > 0) {
      final r = canvasRectToPdf(rect, _displayRect, _pagePt);
      text =
          '${r.width.round()} × ${r.height.round()} pt @ '
          '(${r.x.round()}, ${r.y.round()})';
    }
    return SlabPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.layers_clear, size: 18, color: c.iconStrong),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: AnvilText.mono(13, color: c.onSurface)),
          ),
        ],
      ),
    );
  }

  Widget _overlay(BuildContext context, Rect displayRect, Size imagePx) {
    _displayRect = displayRect;
    _pagePt = imagePx;
    _rect ??= Rect.fromCenter(
      center: displayRect.center,
      width: displayRect.width * 0.4,
      height: displayRect.height * 0.4,
    );
    final rect = _rect!;
    final c = Theme.of(context).extension<AnvilColors>()!;
    return SizedBox.expand(
      key: _canvasKey,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fromRect(
            rect: rect,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() => _drag(RectGrip.move, d.delta)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.35),
                  border: Border.all(color: c.accent, width: 2),
                ),
              ),
            ),
          ),
          _corner(rect.topLeft, RectGrip.tl, c),
          _corner(rect.topRight, RectGrip.tr, c),
          _corner(rect.bottomLeft, RectGrip.bl, c),
          _corner(rect.bottomRight, RectGrip.br, c),
        ],
      ),
    );
  }

  Widget _corner(Offset at, RectGrip grip, AnvilColors c) {
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
