import 'dart:convert';
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
import 'package:anvil/ui/tool/editors/pdf_doc_model.dart';
import 'package:anvil/ui/tool/editors/pdf_overlay_painter.dart';
import 'package:anvil/ui/tool/image_canvas.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Whether the editor builds a new document or edits an existing one.
enum PdfDocMode { create, edit }

enum _Tool {
  select,
  text,
  image,
  draw,
  highlight,
  blackout,
  rect,
  line,
  date,
  time,
}

/// Full WYSIWYG editor for `pdf/create` and `pdf/edit`. Placed elements are
/// flattened per page to a transparent PNG overlay stamped onto the page
/// (Create builds blank pages; Edit preserves the base document beneath).
/// Drives the `_PdfCompose` module.
class PdfDocEditorScreen extends ConsumerStatefulWidget {
  const PdfDocEditorScreen({super.key, required this.tool, required this.mode});

  final ToolModule tool;
  final PdfDocMode mode;

  @override
  ConsumerState<PdfDocEditorScreen> createState() =>
      _PdfDocEditorScreenState();
}

const _palette = <Color>[
  Colors.black,
  Colors.white,
  Color(0xFFE53935),
  Color(0xFFFB8C00),
  Color(0xFFFDD835),
  Color(0xFF43A047),
  Color(0xFF1E88E5),
  Color(0xFF8E24AA),
];

class _PdfDocEditorScreenState extends ConsumerState<PdfDocEditorScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();
  final TransformationController _transform = TransformationController();

  InputFile? _pdfFile; // edit mode
  DocModel? _doc;
  int _page = 0;

  final List<DocModel> _undo = [];
  final List<DocModel> _redo = [];
  final Map<Uint8List, ui.Image> _imageCache = {};

  _Tool _tool = _Tool.select;
  Color _color = const Color(0xFFE53935);
  DocElement? _selected;

  Rect _displayRect = Rect.zero;
  Size _pagePt = Size.zero;
  Uint8List? _white;

  // Transient drag state.
  Offset? _dragStartPt;
  Offset? _lastPt;
  Rect? _pendingRect;
  StrokeEl? _pendingStroke;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _makeWhite();
    if (widget.mode == PdfDocMode.edit) {
      final shared = ref.read(pendingSharedInputProvider);
      if (shared != null && _ext(shared.name) == 'pdf') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(pendingSharedInputProvider.notifier).state = null;
        });
        _loadPdf(shared);
      }
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    for (final img in _imageCache.values) {
      img.dispose();
    }
    super.dispose();
  }

  Future<void> _makeWhite() async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.white);
    final pic = rec.endRecording();
    final img = await pic.toImage(8, 8);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    pic.dispose();
    img.dispose();
    if (mounted) setState(() => _white = data!.buffer.asUint8List());
  }

  String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  // ── Document setup ─────────────────────────────────────────────────────────

  void _startCreate(double w, double h) {
    setState(() {
      _doc = DocModel([
        DocPage(sizePt: (w: w, h: h)),
      ]);
      _page = 0;
      _undo.clear();
      _redo.clear();
      _selected = null;
    });
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
      final e = getIt<PdfEngine>();
      final infos = await e.pageInfos(bytes);
      final pages = <DocPage>[];
      for (var i = 0; i < infos.length; i++) {
        final PdfPageInfo info = infos[i];
        Uint8List? bg;
        try {
          bg = (await e.renderPage(bytes, i)).bytes;
        } catch (_) {}
        pages.add(DocPage(
          sizePt: (w: info.width, h: info.height),
          background: bg,
        ));
      }
      setState(() {
        _pdfFile = f;
        _doc = DocModel(pages);
        _page = 0;
        _undo.clear();
        _redo.clear();
        _selected = null;
        _loading = false;
      });
    } on ToolException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  DocPage get _cur => _doc!.pages[_page];

  // ── Undo / redo ──────────────────────────────────────────────────────────

  void _pushUndo() {
    _undo.add(_doc!.copy());
    if (_undo.length > 50) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoAction() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_doc!.copy());
      _doc = _undo.removeLast();
      if (_page >= _doc!.pages.length) _page = _doc!.pages.length - 1;
      _selected = null;
    });
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_doc!.copy());
      _doc = _redo.removeLast();
      if (_page >= _doc!.pages.length) _page = _doc!.pages.length - 1;
      _selected = null;
    });
  }

  // ── Coordinate mapping ─────────────────────────────────────────────────────

  double get _s =>
      _displayRect.width <= 0 || _pagePt.width <= 0
          ? 1.0
          : _displayRect.width / _pagePt.width;

  Offset _toPt(Offset canvas) => Offset(
        (canvas.dx - _displayRect.left) / _s,
        (canvas.dy - _displayRect.top) / _s,
      );

  Offset _toCanvas(Offset pt) => Offset(
        pt.dx * _s + _displayRect.left,
        pt.dy * _s + _displayRect.top,
      );

  Rect _ptBounds(DocElement el) => switch (el) {
        TextEl t => _textBounds(t),
        ImageEl i => i.rectPt,
        HighlightEl h => h.rectPt,
        BlackoutEl b => b.rectPt,
        ShapeEl sh => sh.rectPt,
        StrokeEl s => _strokeBounds(s),
      };

  Rect _textBounds(TextEl t) {
    final tp = TextPainter(
      text: TextSpan(
        text: t.text.isEmpty ? ' ' : t.text,
        style: TextStyle(
          fontSize: t.sizePt,
          fontFamily: flutterFamily(t.family),
          fontWeight: t.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return Rect.fromLTWH(t.posPt.dx, t.posPt.dy, tp.width, tp.height);
  }

  Rect _strokeBounds(StrokeEl s) {
    if (s.pointsPt.isEmpty) return Rect.zero;
    var minX = s.pointsPt.first.dx, maxX = minX;
    var minY = s.pointsPt.first.dy, maxY = minY;
    for (final p in s.pointsPt) {
      minX = p.dx < minX ? p.dx : minX;
      maxX = p.dx > maxX ? p.dx : maxX;
      minY = p.dy < minY ? p.dy : minY;
      maxY = p.dy > maxY ? p.dy : maxY;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(s.widthPt);
  }

  DocElement? _hitTest(Offset pt) {
    for (final el in _cur.elements.reversed) {
      if (_ptBounds(el).inflate(4 / _s).contains(pt)) return el;
    }
    return null;
  }

  void _translate(DocElement el, Offset d) {
    switch (el) {
      case TextEl t:
        t.posPt += d;
      case ImageEl i:
        i.rectPt = i.rectPt.shift(d);
      case HighlightEl h:
        h.rectPt = h.rectPt.shift(d);
      case BlackoutEl b:
        b.rectPt = b.rectPt.shift(d);
      case ShapeEl sh:
        sh.rectPt = sh.rectPt.shift(d);
      case StrokeEl s:
        s.pointsPt = [for (final p in s.pointsPt) p + d];
    }
  }

  void _resizeTo(DocElement el, Offset pt) {
    Rect fix(Rect r) => Rect.fromLTRB(
          r.left,
          r.top,
          pt.dx.clamp(r.left + 8, double.infinity),
          pt.dy.clamp(r.top + 8, double.infinity),
        );
    switch (el) {
      case ImageEl i:
        i.rectPt = fix(i.rectPt);
      case HighlightEl h:
        h.rectPt = fix(h.rectPt);
      case BlackoutEl b:
        b.rectPt = fix(b.rectPt);
      case ShapeEl sh:
        sh.rectPt = sh.kind == ShapeKind.line
            ? Rect.fromPoints(sh.rectPt.topLeft, pt)
            : fix(sh.rectPt);
      case TextEl t:
        t.sizePt = (pt.dy - t.posPt.dy).clamp(6.0, 400.0);
      case StrokeEl _:
        break;
    }
  }

  // ── Gestures ───────────────────────────────────────────────────────────────

  void _onTapUp(TapUpDetails d) {
    if (_displayRect.width <= 0) return;
    final pt = _toPt(d.localPosition);
    if (!_inPage(pt)) return;
    switch (_tool) {
      case _Tool.select:
        setState(() => _selected = _hitTest(pt));
      case _Tool.text:
        _insertText(pt, '');
      case _Tool.date:
        _insertText(pt, DateTime.now().toString().substring(0, 10));
      case _Tool.time:
        _insertText(pt, DateTime.now().toString().substring(11, 16));
      case _Tool.image:
        _addImageAt(pt);
      default:
        break;
    }
  }

  bool _inPage(Offset pt) =>
      pt.dx >= 0 &&
      pt.dy >= 0 &&
      pt.dx <= _pagePt.width &&
      pt.dy <= _pagePt.height;

  void _onPanStart(DragStartDetails d) {
    if (_displayRect.width <= 0) return;
    final pt = _toPt(d.localPosition);
    switch (_tool) {
      case _Tool.draw:
        _pushUndo();
        _pendingStroke =
            StrokeEl(pointsPt: [pt], color: _color, widthPt: 2.5);
      case _Tool.highlight:
      case _Tool.blackout:
      case _Tool.rect:
      case _Tool.line:
        _dragStartPt = pt;
        setState(() => _pendingRect = Rect.fromPoints(pt, pt));
      case _Tool.select:
        final hit = _hitTest(pt);
        _selected = hit;
        _lastPt = pt;
        if (hit != null) _pushUndo();
        setState(() {});
      default:
        break;
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_displayRect.width <= 0) return;
    final pt = _toPt(d.localPosition);
    switch (_tool) {
      case _Tool.draw:
        final s = _pendingStroke;
        if (s != null) setState(() => s.pointsPt.add(pt));
      case _Tool.highlight:
      case _Tool.blackout:
      case _Tool.rect:
      case _Tool.line:
        final start = _dragStartPt;
        if (start != null) setState(() => _pendingRect = Rect.fromPoints(start, pt));
      case _Tool.select:
        final sel = _selected;
        final last = _lastPt;
        if (sel != null && last != null) {
          setState(() {
            _translate(sel, pt - last);
            _lastPt = pt;
          });
        }
      default:
        break;
    }
  }

  void _onPanEnd(DragEndDetails d) {
    switch (_tool) {
      case _Tool.draw:
        final s = _pendingStroke;
        if (s != null && s.pointsPt.length > 1) {
          setState(() {
            _cur.elements.add(s);
            _selected = s;
          });
        }
        _pendingStroke = null;
      case _Tool.highlight:
      case _Tool.blackout:
      case _Tool.rect:
      case _Tool.line:
        final r = _pendingRect;
        if (r != null && (r.width > 3 || r.height > 3)) {
          _pushUndo();
          setState(() {
            final el = _makeRectEl(r);
            _cur.elements.add(el);
            _selected = el;
          });
        }
        _pendingRect = null;
        _dragStartPt = null;
      default:
        _lastPt = null;
    }
  }

  DocElement _makeRectEl(Rect r) => switch (_tool) {
        _Tool.highlight =>
          HighlightEl(rectPt: r, color: _color.withValues(alpha: 0.35)),
        _Tool.blackout => BlackoutEl(rectPt: r, color: Colors.black),
        _Tool.line => ShapeEl(
            kind: ShapeKind.line,
            rectPt: r,
            color: _color,
            strokePt: 2.5,
            filled: false),
        _ => ShapeEl(
            kind: ShapeKind.rect,
            rectPt: r,
            color: _color,
            strokePt: 2.5,
            filled: false),
      };

  void _insertText(Offset pt, String initial) {
    _pushUndo();
    final el = TextEl(
      text: initial,
      posPt: pt,
      sizePt: 16,
      family: 'Helvetica',
      bold: false,
      italic: false,
      color: Colors.black,
      opacity: 1,
    );
    setState(() {
      _cur.elements.add(el);
      _selected = el;
      _tool = _Tool.select;
    });
    if (initial.isEmpty) _editText(el);
  }

  Future<void> _addImageAt(Offset pt) async {
    final bytes = await _pickImageBytes();
    if (bytes == null || !mounted) return;
    try {
      final img = await decodeImage(bytes);
      _imageCache[bytes] = img;
      final aspect = img.width <= 0 ? 1.0 : img.height / img.width;
      final w = _pagePt.width * 0.4;
      final h = w * aspect;
      _pushUndo();
      setState(() {
        final el = ImageEl(
          png: bytes,
          rectPt: Rect.fromCenter(center: pt, width: w, height: h),
        );
        _cur.elements.add(el);
        _selected = el;
        _tool = _Tool.select;
      });
    } catch (_) {
      setState(() => _error = 'Could not load the image.');
    }
  }

  Future<Uint8List?> _pickImageBytes() async {
    final source = await showModalBottomSheet<_ImgSource>(
      context: context,
      builder: (ctx) {
        final c = Theme.of(ctx).extension<AnvilColors>()!;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library, color: c.iconStrong),
                title: const Text('Photos'),
                onTap: () => Navigator.pop(ctx, _ImgSource.gallery),
              ),
              ListTile(
                leading: Icon(Icons.photo_camera, color: c.iconStrong),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(ctx, _ImgSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.folder_open, color: c.iconStrong),
                title: const Text('Files'),
                onTap: () => Navigator.pop(ctx, _ImgSource.files),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) return null;
    try {
      if (source == _ImgSource.files) {
        final res = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['png', 'jpg', 'jpeg'],
        );
        final path = res?.path;
        if (path == null) return null;
        return await getIt<FileService>().readBytes(path) as Uint8List;
      }
      final x = await _picker.pickImage(
        source: source == _ImgSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
      );
      return x == null ? null : await x.readAsBytes();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the image.');
      return null;
    }
  }

  void _deleteSelected() {
    final sel = _selected;
    if (sel == null) return;
    _pushUndo();
    setState(() {
      _cur.elements.remove(sel);
      _selected = null;
    });
  }

  // ── Page management ────────────────────────────────────────────────────────

  void _goPage(int delta) {
    final next = (_page + delta).clamp(0, _doc!.pages.length - 1);
    if (next == _page) return;
    setState(() {
      _page = next;
      _selected = null;
    });
  }

  void _addPage() {
    _pushUndo();
    setState(() {
      _doc!.pages.add(DocPage(sizePt: _cur.sizePt));
      _page = _doc!.pages.length - 1;
      _selected = null;
    });
  }

  void _deletePage() {
    if (_doc!.pages.length <= 1) return;
    _pushUndo();
    setState(() {
      _doc!.pages.removeAt(_page);
      if (_page >= _doc!.pages.length) _page = _doc!.pages.length - 1;
      _selected = null;
    });
  }

  // ── Export ─────────────────────────────────────────────────────────────────

  Future<void> _run() async {
    final doc = _doc;
    if (doc == null) return;
    if (widget.mode == PdfDocMode.edit && _pdfFile == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fs = getIt<FileService>();
      final overlayFiles = <InputFile>[];
      final indices = <int>[];
      for (var i = 0; i < doc.pages.length; i++) {
        final png = await renderOverlayPng(doc.pages[i]);
        if (png == null) continue;
        final file = await fs.writeBytes('overlay_$i.png', png);
        overlayFiles.add(InputFile(path: file.path, name: 'overlay_$i.png'));
        indices.add(i);
      }
      final Map<String, dynamic> params;
      final List<InputFile> files;
      if (widget.mode == PdfDocMode.create) {
        files = overlayFiles;
        params = {
          'mode': 'create',
          'pageSizesJson': jsonEncode(
              [for (final p in doc.pages) [p.sizePt.w, p.sizePt.h]]),
          'overlayIndexJson': jsonEncode(indices),
        };
      } else {
        files = [_pdfFile!, ...overlayFiles];
        params = {
          'mode': 'edit',
          'overlayIndexJson': jsonEncode(indices),
        };
      }
      if (!mounted) return;
      ref
          .read(jobProvider.notifier)
          .start(widget.tool, ToolInput(files: files, params: params));
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Could not prepare the document.';
      });
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return EditorScaffold(job: ref.watch(jobProvider), builder: _buildIdle);
  }

  Widget _buildIdle(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final job = ref.watch(jobProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          EditorHeader(title: widget.tool.meta.label),
          const SizedBox(height: 12),
          if (_doc == null)
            Expanded(child: _setup(context))
          else ...[
            _toolbar(c),
            const SizedBox(height: 8),
            Expanded(child: _canvas(c)),
            const SizedBox(height: 8),
            _pageBar(c),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: c.error)),
          ],
          if (job is JobFailed) ...[
            const SizedBox(height: 10),
            Text(job.message, style: TextStyle(color: c.error)),
          ],
          if (_doc != null) ...[
            const SizedBox(height: 10),
            PrimaryButton(
              label: 'Run',
              icon: Icons.arrow_forward,
              onPressed: _run,
            ),
          ],
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _setup(BuildContext context) {
    if (widget.mode == PdfDocMode.edit) {
      return Center(
        child: SizedBox(
          width: 220,
          child: _loading
              ? const CircularProgressIndicator()
              : PrimaryButton(
                  label: 'Pick PDF',
                  icon: Icons.picture_as_pdf,
                  onPressed: _pickPdf,
                ),
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose a page size', style: text.titleMedium),
          const SizedBox(height: 16),
          SizedBox(
            width: 240,
            child: PrimaryButton(
              label: 'A4',
              icon: Icons.description,
              onPressed: () => _startCreate(595, 842),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 240,
            child: SecondaryButton(
              label: 'US Letter',
              icon: Icons.description_outlined,
              onPressed: () => _startCreate(612, 792),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(AnvilColors c) {
    Widget chip(IconData icon, _Tool t, String tip) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Tooltip(
            message: tip,
            child: Material(
              color: _tool == t ? c.accent : c.container,
              borderRadius: BorderRadius.circular(AnvilRadii.chip),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _tool = t),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(icon,
                      size: 20,
                      color: _tool == t ? c.onAccent : c.iconStrong),
                ),
              ),
            ),
          ),
        );
    Widget action(IconData icon, VoidCallback? onTap, String tip) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Tooltip(
            message: tip,
            child: Material(
              color: c.container,
              borderRadius: BorderRadius.circular(AnvilRadii.chip),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(icon,
                      size: 20,
                      color: onTap == null ? c.faint : c.iconStrong),
                ),
              ),
            ),
          ),
        );
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip(Icons.touch_app, _Tool.select, 'Select'),
              chip(Icons.text_fields, _Tool.text, 'Text'),
              chip(Icons.image, _Tool.image, 'Image'),
              chip(Icons.gesture, _Tool.draw, 'Draw / sign'),
              chip(Icons.highlight, _Tool.highlight, 'Highlight'),
              chip(Icons.rectangle, _Tool.blackout, 'Blackout'),
              chip(Icons.crop_square, _Tool.rect, 'Rectangle'),
              chip(Icons.horizontal_rule, _Tool.line, 'Line'),
              chip(Icons.event, _Tool.date, 'Date'),
              chip(Icons.schedule, _Tool.time, 'Time'),
              action(Icons.undo, _undo.isEmpty ? null : _undoAction, 'Undo'),
              action(Icons.redo, _redo.isEmpty ? null : _redoAction, 'Redo'),
              action(Icons.delete_outline,
                  _selected == null ? null : _deleteSelected, 'Delete'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final color in _palette)
                GestureDetector(
                  onTap: () => setState(() => _color = color),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == color ? c.accent : c.faint,
                        width: _color == color ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _canvas(AnvilColors c) {
    final bg = _cur.background ?? _white;
    if (bg == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      decoration: BoxDecoration(
        color: c.containerHigh,
        borderRadius: BorderRadius.circular(AnvilRadii.panel),
      ),
      clipBehavior: Clip.antiAlias,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 5,
              panEnabled: false,
              child: ImageCanvas(
                imageBytes: bg,
                imagePx: Size(_cur.sizePt.w, _cur.sizePt.h),
                background: Colors.white,
                builder: _overlay,
              ),
            ),
    );
  }

  Widget _overlay(BuildContext context, Rect displayRect, Size imagePx) {
    _displayRect = displayRect;
    _pagePt = imagePx;
    final c = Theme.of(context).extension<AnvilColors>()!;
    return SizedBox.expand(
      key: _canvasKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              size: Size.infinite,
              painter: DocPagePainter(
                page: _cur,
                displayRect: displayRect,
                images: _imageCache,
              ),
            ),
            if (_pendingRect != null)
              Positioned.fromRect(
                rect: Rect.fromPoints(
                  _toCanvas(_pendingRect!.topLeft),
                  _toCanvas(_pendingRect!.bottomRight),
                ),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: c.accent, width: 1.5),
                    ),
                  ),
                ),
              ),
            ..._selectionHandles(c),
          ],
        ),
      ),
    );
  }

  List<Widget> _selectionHandles(AnvilColors c) {
    final sel = _selected;
    if (sel == null) return const [];
    final b = _ptBounds(sel);
    final tl = _toCanvas(b.topLeft);
    final br = _toCanvas(b.bottomRight);
    final rect = Rect.fromPoints(tl, br);
    return [
      Positioned.fromRect(
        rect: rect.inflate(4),
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: c.accent, width: 1.5),
            ),
          ),
        ),
      ),
      // Bottom-right resize handle (except freehand strokes).
      if (sel is! StrokeEl)
        Positioned(
          left: rect.right - 12,
          top: rect.bottom - 12,
          child: GestureDetector(
            onPanStart: (_) => _pushUndo(),
            onPanUpdate: (d) {
              final box =
                  _canvasKey.currentContext!.findRenderObject() as RenderBox;
              final local = box.globalToLocal(d.globalPosition);
              setState(() => _resizeTo(sel, _toPt(local)));
            },
            child: Container(
              width: 26,
              height: 26,
              decoration:
                  BoxDecoration(color: c.accent, shape: BoxShape.circle),
              child: Icon(Icons.open_in_full, size: 14, color: c.onAccent),
            ),
          ),
        ),
      // Edit affordance for text.
      if (sel is TextEl)
        Positioned(
          left: rect.left - 12,
          top: rect.top - 12,
          child: GestureDetector(
            onTap: () => _editText(sel),
            child: Container(
              width: 26,
              height: 26,
              decoration:
                  BoxDecoration(color: c.accent, shape: BoxShape.circle),
              child: Icon(Icons.edit, size: 14, color: c.onAccent),
            ),
          ),
        ),
    ];
  }

  Widget _pageBar(AnvilColors c) {
    final n = _doc!.pages.length;
    final isCreate = widget.mode == PdfDocMode.create;
    return SlabPanel(
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
          if (isCreate) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: n > 1 ? c.iconStrong : c.faint,
              tooltip: 'Delete page',
              onPressed: n > 1 ? _deletePage : null,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              color: c.iconStrong,
              tooltip: 'Add page',
              onPressed: _addPage,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editText(TextEl el) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = Theme.of(ctx).extension<AnvilColors>()!;
        final ctl = TextEditingController(text: el.text);
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: ctl,
                    autofocus: true,
                    onChanged: (v) => setState(() => el.text = v),
                    decoration: InputDecoration(
                      hintText: 'Text',
                      filled: true,
                      fillColor: c.container,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AnvilRadii.control),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final f in const ['Helvetica', 'Times', 'Courier'])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Material(
                              color: el.family == f ? c.accent : c.container,
                              borderRadius:
                                  BorderRadius.circular(AnvilRadii.chip),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  setSheet(() => el.family = f);
                                  setState(() {});
                                },
                                child: SizedBox(
                                  height: 42,
                                  child: Center(
                                    child: Text(f,
                                        style: TextStyle(
                                          color: el.family == f
                                              ? c.onAccent
                                              : c.onSurface,
                                          fontFamily: flutterFamily(f),
                                        )),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  StepperField(
                    label: 'Size (pt)',
                    value: el.sizePt.round(),
                    min: 6,
                    max: 400,
                    onChanged: (v) {
                      setSheet(() => el.sizePt = v.toDouble());
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final color in _palette)
                        GestureDetector(
                          onTap: () {
                            setSheet(() => el.color = color);
                            setState(() {});
                          },
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    el.color == color ? c.accent : c.faint,
                                width: el.color == color ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _sheetToggle(c, 'Bold', el.bold, () {
                          setSheet(() => el.bold = !el.bold);
                          setState(() {});
                        }),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _sheetToggle(c, 'Italic', el.italic, () {
                          setSheet(() => el.italic = !el.italic);
                          setState(() {});
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'Done',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    // Drop empty text elements the user never filled in.
    if (el.text.trim().isEmpty) {
      setState(() {
        _cur.elements.remove(el);
        if (_selected == el) _selected = null;
      });
    }
  }

  Widget _sheetToggle(AnvilColors c, String label, bool on, VoidCallback onTap) {
    return Material(
      color: on ? c.accent : c.container,
      borderRadius: BorderRadius.circular(AnvilRadii.chip),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Text(label,
                style: TextStyle(color: on ? c.onAccent : c.onSurface)),
          ),
        ),
      ),
    );
  }
}

enum _ImgSource { gallery, camera, files }
