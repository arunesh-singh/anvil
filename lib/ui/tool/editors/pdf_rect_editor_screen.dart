import 'dart:convert';
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
import 'package:anvil/ui/tool/image_canvas.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/pdf_geometry.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Which region op the editor drives.
enum PdfRectMode { crop, erase }

/// WYSIWYG editor for `pdf/crop` and `pdf/remove-watermark`. Erase (watermark)
/// drags one rectangle applied to every page (whole-doc `eraseRegionAllPages`).
/// Crop stores the rectangle as page fractions so a shared rect maps across
/// differently-sized pages, supports a per-page override, and a page subset;
/// it drives the `_PdfCrop` module via `marginsJson`.
class PdfRectEditorScreen extends ConsumerStatefulWidget {
  const PdfRectEditorScreen({
    super.key,
    required this.tool,
    required this.mode,
  });

  final ToolModule tool;
  final PdfRectMode mode;

  @override
  ConsumerState<PdfRectEditorScreen> createState() =>
      _PdfRectEditorScreenState();
}

enum _Grip { move, tl, tr, bl, br }

class _PdfRectEditorScreenState extends ConsumerState<PdfRectEditorScreen> {
  final GlobalKey _canvasKey = GlobalKey();

  InputFile? _file;
  Uint8List? _pdfBytes;
  Uint8List? _pagePng;
  List<PdfPageInfo> _pages = const [];
  final Map<int, Uint8List> _pageCache = {};
  List<Uint8List> _thumbs = const [];

  int _page = 0;
  Rect? _rect; // canvas coords, current page working rect
  Rect _displayRect = Rect.zero;
  Size _pagePt = Size.zero;

  // Crop-only: rects stored as page fractions (Rect.fromLTWH in 0..1 space).
  Rect? _sharedFrac;
  final Map<int, Rect> _perPageFrac = {};
  Set<int> _cropPages = {};

  bool _loading = false;
  String? _error;

  bool get _isCrop => widget.mode == PdfRectMode.crop;

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
      final thumbs = _isCrop
          ? [for (final t in await e.renderThumbnails(bytes)) t.bytes]
          : const <Uint8List>[];
      final page = await e.renderPage(bytes, 0);
      setState(() {
        _file = f;
        _pdfBytes = bytes;
        _pages = pages;
        _thumbs = thumbs;
        _pageCache
          ..clear()
          ..[0] = page.bytes;
        _page = 0;
        _pagePng = page.bytes;
        _rect = null;
        _sharedFrac = null;
        _perPageFrac.clear();
        _cropPages = {for (var i = 0; i < pages.length; i++) i};
        _loading = false;
      });
    } on ToolException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
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
      _rect = null; // re-init from stored fraction for the new page
    });
    _renderCurrentPage();
  }

  bool get _override => _perPageFrac.containsKey(_page);

  Rect _fracOf(Rect r) => Rect.fromLTWH(
        (r.left - _displayRect.left) / _displayRect.width,
        (r.top - _displayRect.top) / _displayRect.height,
        r.width / _displayRect.width,
        r.height / _displayRect.height,
      );

  Rect _rectFromFrac(Rect f) => Rect.fromLTWH(
        _displayRect.left + f.left * _displayRect.width,
        _displayRect.top + f.top * _displayRect.height,
        f.width * _displayRect.width,
        f.height * _displayRect.height,
      );

  void _persistFrac() {
    if (!_isCrop || _rect == null || _displayRect.width <= 0) return;
    final f = _fracOf(_rect!);
    if (_override) {
      _perPageFrac[_page] = f;
    } else {
      _sharedFrac = f;
    }
  }

  void _drag(_Grip grip, Offset delta) {
    var r = _rect!;
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
    const minSz = 24.0;
    var l = r.left.clamp(_displayRect.left, _displayRect.right - minSz);
    var t = r.top.clamp(_displayRect.top, _displayRect.bottom - minSz);
    var rt = r.right.clamp(l + minSz, _displayRect.right);
    var b = r.bottom.clamp(t + minSz, _displayRect.bottom);
    if (grip == _Grip.move) {
      final w = _rect!.width;
      final h = _rect!.height;
      l = r.left.clamp(_displayRect.left, _displayRect.right - w);
      t = r.top.clamp(_displayRect.top, _displayRect.bottom - h);
      rt = l + w;
      b = t + h;
    }
    _rect = Rect.fromLTRB(l, t, rt, b);
    _persistFrac();
  }

  void _toggleOverride(bool v) {
    setState(() {
      if (v) {
        _perPageFrac[_page] = _rect != null
            ? _fracOf(_rect!)
            : (_sharedFrac ?? Rect.fromLTWH(0.1, 0.1, 0.8, 0.8));
      } else {
        _perPageFrac.remove(_page);
        _rect = null; // re-init from shared
      }
    });
  }

  void _run() {
    final f = _file;
    final rect = _rect;
    if (f == null || rect == null || _displayRect.width <= 0) return;
    if (widget.mode == PdfRectMode.erase) {
      final r = canvasRectToPdf(rect, _displayRect, _pagePt);
      ref.read(jobProvider.notifier).start(
            widget.tool,
            ToolInput(files: [f], params: {
              'x': r.x.round(),
              'y': r.y.round(),
              'width': r.width.round(),
              'height': r.height.round(),
            }),
          );
      return;
    }
    // Crop: build per-page margins from fractions.
    final margins = <Map<String, double>?>[];
    for (var i = 0; i < _pages.length; i++) {
      final frac = !_cropPages.contains(i)
          ? null
          : (_perPageFrac[i] ?? _sharedFrac);
      if (frac == null) {
        margins.add(null);
        continue;
      }
      final w = _pages[i].width;
      final h = _pages[i].height;
      margins.add({
        'l': frac.left * w,
        't': frac.top * h,
        'r': (1 - (frac.left + frac.width)) * w,
        'b': (1 - (frac.top + frac.height)) * h,
      });
    }
    ref.read(jobProvider.notifier).start(
          widget.tool,
          ToolInput(files: [f], params: {'marginsJson': jsonEncode(margins)}),
        );
  }

  bool get _canRun {
    if (_file == null || _rect == null) return false;
    if (widget.mode == PdfRectMode.erase) return true;
    return _cropPages.isNotEmpty;
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
                        imagePx:
                            Size(_pages[_page].width, _pages[_page].height),
                        builder: _overlay,
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _readout(context),
            if (_isCrop) ...[
              const SizedBox(height: 8),
              _cropControls(c),
            ],
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

  Widget _cropControls(AnvilColors c) {
    final n = _pages.length;
    final selLabel = _cropPages.length == n
        ? 'All pages'
        : '${_cropPages.length} of $n';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SlabPanel(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                color: c.iconStrong,
                onPressed: _page > 0 ? () => _goPage(-1) : null,
              ),
              Expanded(
                child: Text('Page ${_page + 1} / $n',
                    textAlign: TextAlign.center,
                    style: AnvilText.mono(13, color: c.onSurface)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                color: c.iconStrong,
                onPressed: _page < n - 1 ? () => _goPage(1) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Switch(value: _override, onChanged: _toggleOverride),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Override this page',
                  style: TextStyle(color: c.onSurface)),
            ),
            SecondaryButton(
              label: 'Pages: $selLabel',
              icon: Icons.checklist,
              onPressed: _selectPages,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _selectPages() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = Theme.of(ctx).extension<AnvilColors>()!;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            void toggle(int i) => setSheet(() {
                  if (!_cropPages.remove(i)) _cropPages.add(i);
                  setState(() {});
                });
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Crop which pages?',
                              style: Theme.of(ctx).textTheme.titleMedium),
                        ),
                        TextButton(
                          onPressed: () => setSheet(() {
                            _cropPages = {
                              for (var i = 0; i < _pages.length; i++) i
                            };
                            setState(() {});
                          }),
                          child: const Text('All'),
                        ),
                        TextButton(
                          onPressed: () => setSheet(() {
                            _cropPages.clear();
                            setState(() {});
                          }),
                          child: const Text('None'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: GridView.builder(
                        shrinkWrap: true,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 110,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: _thumbs.length,
                        itemBuilder: (ctx, i) {
                          final on = _cropPages.contains(i);
                          return GestureDetector(
                            onTap: () => toggle(i),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(AnvilRadii.chip),
                                border: Border.all(
                                  color: on ? c.accent : c.faint,
                                  width: on ? 2.5 : 1,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Container(
                                    color: c.containerHigh,
                                    child: Image.memory(_thumbs[i],
                                        fit: BoxFit.contain),
                                  ),
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    child: Container(
                                      color:
                                          c.accent.withValues(alpha: 0.85),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      child: Text('${i + 1}',
                                          style: AnvilText.mono(10,
                                              color: c.onAccent)),
                                    ),
                                  ),
                                  if (on)
                                    Positioned(
                                      right: 4,
                                      top: 4,
                                      child: Icon(Icons.check_circle,
                                          size: 18, color: c.accent),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Done',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _readout(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final rect = _rect;
    String text = '—';
    if (rect != null && _displayRect.width > 0) {
      if (_isCrop) {
        final m = canvasRectToMargins(rect, _displayRect, _pagePt);
        text = 'L ${m.left.round()}  T ${m.top.round()}  '
            'R ${m.right.round()}  B ${m.bottom.round()} pt'
            '${_override ? '  · override' : ''}';
      } else {
        final r = canvasRectToPdf(rect, _displayRect, _pagePt);
        text = '${r.width.round()} × ${r.height.round()} pt @ '
            '(${r.x.round()}, ${r.y.round()})';
      }
    }
    return SlabPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(_isCrop ? Icons.crop : Icons.layers_clear,
              size: 18, color: c.iconStrong),
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
    if (_rect == null) {
      final frac = _isCrop
          ? (_perPageFrac[_page] ?? _sharedFrac)
          : null;
      _rect = frac != null
          ? _rectFromFrac(frac)
          : Rect.fromCenter(
              center: displayRect.center,
              width: displayRect.width * (_isCrop ? 0.8 : 0.4),
              height: displayRect.height * (_isCrop ? 0.8 : 0.4),
            );
      if (_isCrop) _persistFrac();
    }
    final rect = _rect!;
    final c = Theme.of(context).extension<AnvilColors>()!;
    return SizedBox.expand(
      key: _canvasKey,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_isCrop)
            Positioned.fill(
              child: CustomPaint(
                painter: _DimPainter(rect, Colors.black.withValues(alpha: 0.5)),
              ),
            ),
          Positioned.fromRect(
            rect: rect,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() => _drag(_Grip.move, d.delta)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.mode == PdfRectMode.erase
                      ? c.accent.withValues(alpha: 0.35)
                      : null,
                  border: Border.all(color: c.accent, width: 2),
                ),
              ),
            ),
          ),
          _corner(rect.topLeft, _Grip.tl, c),
          _corner(rect.topRight, _Grip.tr, c),
          _corner(rect.bottomLeft, _Grip.bl, c),
          _corner(rect.bottomRight, _Grip.br, c),
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
  bool shouldRepaint(_DimPainter old) => old.hole != hole || old.color != color;
}
