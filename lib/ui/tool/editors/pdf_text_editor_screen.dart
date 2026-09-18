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

/// WYSIWYG editor for `pdf/add-text`: type text, drag it onto the actual page,
/// pinch to zoom, and format it (font family, size, color, bold/italic,
/// opacity). Vector/selectable output via the `_textOverlay` module (keys
/// `text,page,x,y,fontSize,opacity,fontFamily,bold,italic,color`; `page == 0`
/// means every page).
class PdfTextEditorScreen extends ConsumerStatefulWidget {
  const PdfTextEditorScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<PdfTextEditorScreen> createState() =>
      _PdfTextEditorScreenState();
}

class _PdfTextEditorScreenState extends ConsumerState<PdfTextEditorScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  final TextEditingController _textCtl = TextEditingController();
  final TransformationController _transform = TransformationController();

  InputFile? _file;
  Uint8List? _pdfBytes;
  List<PdfPageInfo> _pages = const [];
  final Map<int, Uint8List> _pageCache = {};

  int _page = 0;
  Uint8List? _pagePng;
  late int _fontSize;
  late int _opacity;
  bool _allPages = false;

  // Formatting.
  String _family = 'Helvetica';
  bool _bold = false;
  bool _italic = false;
  Color _color = Colors.black;
  bool _showFormat = false;

  Offset? _anchor; // canvas coords: bottom-left of the text box
  Rect _displayRect = Rect.zero;
  Size _pagePt = Size.zero;

  bool _loading = false;
  String? _error;

  static const _families = ['Helvetica', 'Times', 'Courier'];
  static const _palette = <Color>[
    Colors.black,
    Colors.white,
    Color(0xFF444444),
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
    Color(0xFF6D4C41),
  ];

  @override
  void initState() {
    super.initState();
    _fontSize = _defaultInt('fontSize', 18);
    _opacity = _defaultInt('opacity', 100);
    final shared = ref.read(pendingSharedInputProvider);
    if (shared != null && _matches(shared)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pendingSharedInputProvider.notifier).state = null;
      });
      _load(shared);
    }
  }

  @override
  void dispose() {
    _textCtl.dispose();
    _transform.dispose();
    super.dispose();
  }

  int _defaultInt(String key, int fallback) {
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
      final bytes = await getIt<FileService>().readBytes(f.path) as Uint8List;
      final pages = await getIt<PdfEngine>().pageInfos(bytes);
      setState(() {
        _file = f;
        _pdfBytes = bytes;
        _pages = pages;
        _pageCache.clear();
        _page = 0;
        _pagePng = null;
        _anchor = null;
        _transform.value = Matrix4.identity();
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
    setState(() => _page = next);
    _renderCurrentPage();
  }

  double get _scale =>
      _displayRect.width <= 0 ? 1.0 : _pagePt.width / _displayRect.width;

  double get _fontPx => _fontSize / _scale;

  void _dragAnchor(Offset delta) {
    final a = (_anchor ?? _displayRect.center) + delta;
    _anchor = Offset(
      a.dx.clamp(_displayRect.left, _displayRect.right),
      a.dy.clamp(_displayRect.top, _displayRect.bottom),
    );
  }

  String _hex(Color color) {
    int ch(double v) => (v * 255).round().clamp(0, 255);
    String h(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${h(ch(color.r))}${h(ch(color.g))}${h(ch(color.b))}';
  }

  String? _flutterFamily(String f) => switch (f) {
        'Times' => 'serif',
        'Courier' => 'monospace',
        _ => null,
      };

  void _run() {
    final f = _file;
    final anchor = _anchor;
    if (f == null || anchor == null || _displayRect.width <= 0) return;
    if (_textCtl.text.trim().isEmpty) return;
    final a = canvasPointToPdf(anchor, _displayRect, _pagePt);
    ref.read(jobProvider.notifier).start(
          widget.tool,
          ToolInput(files: [f], params: {
            'text': _textCtl.text,
            'page': _allPages ? 0 : _page + 1,
            'x': a.dx.round(),
            'y': a.dy.round(),
            'fontSize': _fontSize,
            'opacity': _opacity,
            'fontFamily': _family,
            'bold': _bold ? 1 : 0,
            'italic': _italic ? 1 : 0,
            'color': _hex(_color),
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
    final canRun =
        _file != null && _anchor != null && _textCtl.text.trim().isNotEmpty;
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
                    : InteractiveViewer(
                        transformationController: _transform,
                        minScale: 1,
                        maxScale: 5,
                        panEnabled: false,
                        child: ImageCanvas(
                          imageBytes: _pagePng!,
                          imagePx:
                              Size(_pages[_page].width, _pages[_page].height),
                          builder: _overlay,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _controls(context),
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
            onPressed: canRun ? _run : null,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final n = _pages.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _textCtl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Text to place',
            filled: true,
            fillColor: c.container,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AnvilRadii.control),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(AnvilRadii.control),
          onTap: () => setState(() => _showFormat = !_showFormat),
          child: SlabPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.text_format, size: 20, color: c.iconStrong),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Format', style: TextStyle(color: c.onSurface)),
                ),
                Icon(_showFormat ? Icons.expand_less : Icons.expand_more,
                    color: c.iconStrong),
              ],
            ),
          ),
        ),
        if (_showFormat) ...[
          const SizedBox(height: 8),
          _familyChips(c),
          const SizedBox(height: 8),
          StepperField(
            label: 'Font size (pt)',
            value: _fontSize,
            min: 4,
            onChanged: (v) => setState(() => _fontSize = v),
          ),
          const SizedBox(height: 8),
          _colorRow(c),
          const SizedBox(height: 8),
          Row(
            children: [
              _toggle(c, 'Bold', _bold, () => setState(() => _bold = !_bold),
                  weight: FontWeight.bold),
              const SizedBox(width: 8),
              _toggle(c, 'Italic', _italic,
                  () => setState(() => _italic = !_italic),
                  style: FontStyle.italic),
            ],
          ),
          const SizedBox(height: 8),
          StepperField(
            label: 'Opacity (%)',
            value: _opacity,
            min: 1,
            max: 100,
            onChanged: (v) => setState(() => _opacity = v),
          ),
        ],
        const SizedBox(height: 8),
        SlabPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                color: c.iconStrong,
                onPressed: !_allPages && _page > 0 ? () => _goPage(-1) : null,
              ),
              Expanded(
                child: Text(
                  _allPages
                      ? 'All pages'
                      : (n == 0 ? '—' : 'Page ${_page + 1} / $n'),
                  textAlign: TextAlign.center,
                  style: AnvilText.mono(13, color: c.onSurface),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                color: c.iconStrong,
                onPressed:
                    !_allPages && _page < n - 1 ? () => _goPage(1) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Switch(
              value: _allPages,
              onChanged: (v) => setState(() {
                _allPages = v;
                if (v) {
                  _page = 0;
                  _renderCurrentPage();
                }
              }),
            ),
            const SizedBox(width: 8),
            Text('Apply to all pages', style: TextStyle(color: c.onSurface)),
            const Spacer(),
            SecondaryButton(
              label: 'Swap',
              icon: Icons.swap_horiz,
              onPressed: _pick,
            ),
          ],
        ),
      ],
    );
  }

  Widget _familyChips(AnvilColors c) {
    return Row(
      children: [
        for (final f in _families) ...[
          Expanded(
            child: Material(
              color: _family == f ? c.accent : c.container,
              borderRadius: BorderRadius.circular(AnvilRadii.chip),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _family = f),
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(
                      f,
                      style: TextStyle(
                        color: _family == f ? c.onAccent : c.onSurface,
                        fontFamily: _flutterFamily(f),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (f != _families.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _colorRow(AnvilColors c) {
    return SlabPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final color in _palette)
            GestureDetector(
              onTap: () => setState(() => _color = color),
              child: Container(
                width: 30,
                height: 30,
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
    );
  }

  Widget _toggle(AnvilColors c, String label, bool on, VoidCallback onTap,
      {FontWeight? weight, FontStyle? style}) {
    return Expanded(
      child: Material(
        color: on ? c.accent : c.container,
        borderRadius: BorderRadius.circular(AnvilRadii.chip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: on ? c.onAccent : c.onSurface,
                  fontWeight: weight,
                  fontStyle: style,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(BuildContext context, Rect displayRect, Size imagePx) {
    _displayRect = displayRect;
    _pagePt = imagePx;
    _anchor ??= displayRect.center;
    final c = Theme.of(context).extension<AnvilColors>()!;
    final anchor = _anchor!;
    final text = _textCtl.text.isEmpty ? 'Text' : _textCtl.text;
    final fontPx = _fontPx;
    return SizedBox.expand(
      key: _canvasKey,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Anchor is the text's bottom-left; place the label above it.
          Positioned(
            left: anchor.dx,
            top: anchor.dy - fontPx.clamp(6.0, 400.0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() => _dragAnchor(d.delta)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: c.accent, width: 1.5),
                ),
                child: Text(
                  text,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: _color
                        .withValues(alpha: (_opacity / 100).clamp(0.1, 1.0)),
                    fontSize: fontPx.clamp(6.0, 400.0),
                    height: 1.0,
                    fontFamily: _flutterFamily(_family),
                    fontWeight: _bold ? FontWeight.bold : FontWeight.normal,
                    fontStyle: _italic ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
