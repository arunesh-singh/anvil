/// The Translate image screen (design `explorations/tools-workspace.html`,
/// frame "Translate image") for `image/translate`: the photo with its
/// recognised text outlined, the source language auto-detected and both
/// languages shown by name (never ISO codes), and a preview of the first
/// recognised lines translated so the result can be trusted before Run.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/languages.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/mlkit_engine.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/tool_frame.dart';
import 'package:anvil/ui/tool/editors/tool_stage.dart';
import 'package:anvil/ui/tool/image_canvas.dart';
import 'package:anvil/ui/tool/input/input_picker.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';

/// How many recognised lines the preview translates.
const _previewLines = 3;

/// Non-empty recognised lines, in reading order.
List<String> ocrLines(OcrResult ocr) => [
  for (final line in ocr.text.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

class TranslateImageScreen extends ConsumerStatefulWidget {
  const TranslateImageScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<TranslateImageScreen> createState() =>
      _TranslateImageScreenState();
}

class _TranslateImageScreenState extends ConsumerState<TranslateImageScreen> {
  InputFile? _file;
  Uint8List? _bytes;
  Size? _imagePx;
  OcrResult? _ocr;
  String? _error;
  int _loadSeq = 0;

  /// Language ML Kit identified in the text (raw code), null = undetermined.
  String? _detected;
  bool _detecting = false;

  /// User-chosen source; null = use [_detected].
  String? _from;
  late String _to = _defaultTarget();

  List<(String, String)>? _preview;
  String? _previewError;
  String? _previewStatus;
  int _previewSeq = 0;

  static String _defaultTarget() {
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    final code = canonicalLanguageCode(device.languageCode);
    return isTranslatable(code) ? code : 'en';
  }

  @override
  void initState() {
    super.initState();
    final shared = takeSharedInput(ref, widget.tool.meta);
    if (shared != null) _load(shared);
  }

  /// The source the tool will use, or null when there is none to use yet.
  String? get _source {
    final from = _from;
    if (from != null) return from;
    final detected = _detected;
    if (detected == null || !isTranslatable(detected)) return null;
    return canonicalLanguageCode(detected);
  }

  Future<void> _load(InputFile f) async {
    final seq = ++_loadSeq;
    _file = f;
    _bytes = null;
    _imagePx = null;
    _ocr = null;
    _error = null;
    _detected = null;
    _from = null;
    _preview = null;
    _previewError = null;
    if (mounted) setState(() {});
    try {
      final bytes = await File(f.path).readAsBytes();
      final image = await decodeImageFromList(bytes);
      final px = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      final ocr = await getIt<MlKitEngine>().recognizeText(f.path);
      if (seq != _loadSeq || !mounted) return;
      setState(() {
        _bytes = bytes;
        _imagePx = px;
        _ocr = ocr;
        _detecting = ocr.text.trim().isNotEmpty;
      });
      if (ocr.text.trim().isEmpty) return;
      final detected = await getIt<MlKitEngine>().identifyLanguage(ocr.text);
      if (seq != _loadSeq || !mounted) return;
      setState(() {
        _detected = detected;
        _detecting = false;
      });
      unawaited(_refreshPreview());
    } catch (e) {
      if (seq != _loadSeq || !mounted) return;
      setState(() {
        _detecting = false;
        _error = e is ToolException ? e.message : 'Could not read this photo.';
      });
    }
  }

  Future<void> _refreshPreview() async {
    final ocr = _ocr;
    final from = _source;
    final to = _to;
    final seq = ++_previewSeq;
    if (ocr == null || from == null) {
      setState(() {
        _preview = null;
        _previewStatus = null;
      });
      return;
    }
    final lines = ocrLines(ocr).take(_previewLines).toList();
    if (from == to) {
      setState(() {
        _preview = [for (final l in lines) (l, l)];
        _previewStatus = null;
        _previewError = null;
      });
      return;
    }
    final mlkit = getIt<MlKitEngine>();
    setState(() {
      _preview = null;
      _previewError = null;
      _previewStatus = 'Translating…';
    });
    try {
      if (!await mlkit.translationModelsReady(from, to)) {
        if (seq != _previewSeq || !mounted) return;
        setState(
          () => _previewStatus =
              'Downloading ${languageName(from)} and ${languageName(to)}…',
        );
      }
      final out = <(String, String)>[];
      for (final line in lines) {
        out.add((line, await mlkit.translate(line, from: from, to: to)));
      }
      if (seq != _previewSeq || !mounted) return;
      setState(() {
        _preview = out;
        _previewStatus = null;
      });
    } catch (e) {
      if (seq != _previewSeq || !mounted) return;
      setState(() {
        _previewStatus = null;
        _previewError = e is ToolException ? e.message : 'Preview failed.';
      });
    }
  }

  Future<void> _choose({required bool source}) async {
    final picked = await showWsSheet<String>(
      context,
      _LanguageSheet(
        title: source ? 'Translate from' : 'Translate to',
        source: source,
        selected: source ? _from : _to,
        detected: source && _detected != null && isTranslatable(_detected!)
            ? canonicalLanguageCode(_detected!)
            : null,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (source) {
        _from = picked == _LanguageSheet.auto ? null : picked;
      } else {
        _to = picked;
      }
    });
    unawaited(_refreshPreview());
  }

  void _swap() {
    final source = _source;
    if (source == null) return;
    setState(() {
      _from = _to;
      _to = source;
    });
    unawaited(_refreshPreview());
  }

  void _run() {
    final f = _file;
    final source = _source;
    if (f == null || source == null) return;
    ref
        .read(jobProvider.notifier)
        .start(
          widget.tool,
          ToolInput(files: [f], params: {'from': source, 'to': _to}),
        );
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final hasText = _ocr != null && _ocr!.text.trim().isNotEmpty;
    return ToolFrame(
      tool: widget.tool,
      title: 'Translate image',
      hasInput: _file != null,
      onPicked: (files) => _load(files.first),
      body: _body(context),
      runLabel: 'Translate',
      runDetail: source == null
          ? null
          : '· ${languageName(source)} → ${languageName(_to)}',
      onRun: hasText && source != null ? _run : null,
    );
  }

  Widget _body(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Text(_error!, style: TextStyle(color: c.error)),
      );
    }
    final bytes = _bytes;
    final px = _imagePx;
    final ocr = _ocr;
    if (bytes == null || px == null || ocr == null) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final lineCount = ocrLines(ocr).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StagePanel(
          height: 240,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 52),
          bar: [
            StagePill(
              label: lineCount == 0
                  ? 'no text found'
                  : '$lineCount line${lineCount == 1 ? '' : 's'} found',
            ),
          ],
          child: ImageCanvas(
            imageBytes: bytes,
            imagePx: px,
            builder: (context, rect, imagePx) => Positioned.fromRect(
              rect: rect,
              child: CustomPaint(
                painter: _OcrBoxes(
                  blocks: ocr.blocks,
                  scale: rect.width / imagePx.width,
                  color: c.accent,
                ),
              ),
            ),
          ),
        ),
        if (lineCount > 0) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _fromButton()),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Swap languages',
                child: Material(
                  color: c.container,
                  borderRadius: BorderRadius.circular(AnvilRadii.control),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _source == null ? null : _swap,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.swap_horiz,
                        size: 20,
                        color: _source == null ? c.faint : c.iconStrong,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LanguageButton(
                  eyebrow: 'to',
                  name: languageName(_to),
                  sub: 'tap to change',
                  on: true,
                  onTap: () => _choose(source: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _previewPanel(context),
        ],
      ],
    );
  }

  Widget _fromButton() {
    final from = _from;
    final detected = _detected;
    final (String name, String sub) = switch ((from, detected)) {
      (final String code, _) => (languageName(code), 'tap to change'),
      (null, _) when _detecting => ('Detecting…', 'auto'),
      (null, null) => ('Choose', 'not detected'),
      (null, final String code) when isTranslatable(code) => (
        languageName(code),
        'detected',
      ),
      (null, final String code) => (languageName(code), 'not supported'),
    };
    return _LanguageButton(
      eyebrow: 'from',
      name: name,
      sub: sub,
      on: false,
      onTap: () => _choose(source: true),
    );
  }

  Widget _previewPanel(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final preview = _preview;
    final Widget content;
    if (_previewError != null) {
      content = Text(_previewError!, style: TextStyle(color: c.error));
    } else if (_source == null) {
      content = Text(
        _detecting
            ? 'Detecting the language…'
            : 'Choose the language the text is in.',
        style: text.bodyMedium!.copyWith(color: c.muted),
      );
    } else if (preview == null) {
      content = Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _previewStatus ?? 'Translating…',
              style: text.bodyMedium!.copyWith(color: c.muted),
            ),
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (src, out) in preview)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: src,
                      style: TextStyle(color: c.muted),
                    ),
                    const TextSpan(text: '  →  '),
                    TextSpan(text: out),
                  ],
                ),
                style: text.bodyMedium,
              ),
            ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.container,
        borderRadius: BorderRadius.circular(AnvilRadii.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PREVIEW',
            style: text.labelSmall?.copyWith(color: c.muted, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          content,
        ],
      ),
    );
  }
}

/// The mock's `.langb`: eyebrow, language name, mono sub.
class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    required this.eyebrow,
    required this.name,
    required this.sub,
    required this.on,
    required this.onTap,
  });

  final String eyebrow;
  final String name;
  final String sub;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    return Material(
      color: on ? c.accentContainer : c.container,
      borderRadius: BorderRadius.circular(AnvilRadii.row),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: text.labelSmall?.copyWith(
                  color: c.muted,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: text.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                sub,
                style: AnvilText.mono(11, color: c.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searchable list of the translation languages, by name. Pops the chosen
/// code, or [auto] for "Auto-detect" on the source side ([detected] names
/// what it found).
class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({
    required this.title,
    required this.source,
    required this.selected,
    this.detected,
  });

  static const auto = 'auto';

  final String title;

  /// Source side: offers "Auto-detect" first.
  final bool source;
  final String? selected;
  final String? detected;

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final q = _query.trim().toLowerCase();
    final matches = [
      for (final e in translateLanguages.entries)
        if (q.isEmpty || e.value.toLowerCase().contains(q)) e,
    ];
    return WsSheetFrame(
      title: widget.title,
      sub: '${translateLanguages.length} languages',
      children: [
        TextField(
          autofocus: false,
          decoration: InputDecoration(
            hintText: 'Search languages',
            prefixIcon: Icon(Icons.search, color: c.muted),
            filled: true,
            fillColor: c.containerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AnvilRadii.search),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 10),
        if (widget.source && q.isEmpty)
          _LanguageTile(
            name: 'Auto-detect',
            sub: widget.detected == null
                ? null
                : languageName(widget.detected!),
            selected: widget.selected == null,
            onTap: () => Navigator.pop(context, _LanguageSheet.auto),
          ),
        for (final e in matches)
          _LanguageTile(
            name: e.value,
            selected: widget.selected == e.key,
            onTap: () => Navigator.pop(context, e.key),
          ),
        if (matches.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No language matches “$_query”.',
              style: TextStyle(color: c.muted),
            ),
          ),
      ],
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.name,
    required this.selected,
    required this.onTap,
    this.sub,
  });

  final String name;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return InkWell(
      borderRadius: BorderRadius.circular(AnvilRadii.control),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(name, style: Theme.of(context).textTheme.titleSmall),
            ),
            if (sub != null) ...[
              Text(sub!, style: AnvilText.mono(12, color: c.muted)),
              const SizedBox(width: 8),
            ],
            if (selected) Icon(Icons.check, size: 18, color: c.accent),
          ],
        ),
      ),
    );
  }
}

/// Recognised text blocks outlined over the photo (the mock's `.ocr`).
class _OcrBoxes extends CustomPainter {
  const _OcrBoxes({
    required this.blocks,
    required this.scale,
    required this.color,
  });

  final List<OcrBlock> blocks;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color.withValues(alpha: 0.25);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final b in blocks) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          b.left * scale,
          b.top * scale,
          b.width * scale,
          b.height * scale,
        ),
        const Radius.circular(3),
      );
      canvas
        ..drawRRect(r, fill)
        ..drawRRect(r, stroke);
    }
  }

  @override
  bool shouldRepaint(_OcrBoxes old) =>
      old.blocks != blocks || old.scale != scale || old.color != color;
}
