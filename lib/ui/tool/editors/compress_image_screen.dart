/// Compress image (`image/compress`, design "Compress image"): a before/after
/// split at 100% zoom so the quality can be judged on real pixels, three
/// named presets that set the quality slider, and the output size measured
/// by running the real tool ([PreviewRunner]) — stated before Run.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/preview_runner.dart';
import 'package:anvil/ui/tool/editors/tool_frame.dart';
import 'package:anvil/ui/tool/editors/tool_stage.dart';
import 'package:anvil/ui/tool/editors/video_math.dart';
import 'package:anvil/ui/tool/input/input_picker.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';

/// The named quality presets, in segment order.
enum CompressPreset {
  smallest('Smallest', 40),
  balanced('Balanced', 75),
  sharpest('Sharpest', 90);

  const CompressPreset(this.label, this.quality);
  final String label;
  final int quality;

  /// The preset [quality] reads as, or null when the slider is off-preset.
  static CompressPreset? of(int quality) {
    for (final p in values) {
      if (p.quality == quality) return p;
    }
    return null;
  }
}

/// The estimate box: `4.8 MB → 1.1 MB` with delta `−77%`. While measuring the
/// after side reads `…`; after a failed measurement `?`.
({String value, String? delta}) compressEstimate(
  int before,
  int? after, {
  bool failed = false,
}) => (
  value:
      '${compactBytes(before)} → '
      '${after != null ? compactBytes(after) : (failed ? '?' : '…')}',
  delta: after == null ? null : savingsLabel(before, after),
);

/// `PNG has no quality setting — saves as JPG.` when the tool changed the
/// format from [inputName]'s to [outputName]'s; null when it kept it.
String? formatChangeNote(String inputName, String? outputName) {
  if (outputName == null) return null;
  final from = imageExt(inputName);
  final to = imageExt(outputName);
  if (from == to || from.isEmpty || to.isEmpty) return null;
  return '${from.toUpperCase()} has no quality setting — '
      'saves as ${to.toUpperCase()}.';
}

class CompressImageScreen extends ConsumerStatefulWidget {
  const CompressImageScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<CompressImageScreen> createState() =>
      _CompressImageScreenState();
}

class _CompressImageScreenState extends ConsumerState<CompressImageScreen> {
  InputFile? _file;
  LoadedImage? _image;
  String? _error;
  int _loadSeq = 0;
  int _quality = CompressPreset.balanced.quality;
  late final PreviewRunner _preview = PreviewRunner(widget.tool);

  @override
  void initState() {
    super.initState();
    final shared = takeSharedInput(ref, widget.tool.meta);
    if (shared != null) _load(shared);
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Future<void> _load(InputFile f) async {
    final seq = ++_loadSeq;
    setState(() {
      _file = f;
      _image = null;
      _error = null;
    });
    try {
      final image = await loadImageFile(f);
      if (seq != _loadSeq || !mounted) return;
      setState(() => _image = image);
      _measure();
    } on ToolException catch (e) {
      if (seq != _loadSeq || !mounted) return;
      setState(() => _error = e.message);
    }
  }

  Map<String, dynamic> get _params => {'quality': _quality};

  void _measure() {
    final image = _image;
    if (image != null) _preview.request(image.file, _params);
  }

  void _setQuality(int q) {
    setState(() => _quality = q);
    _measure();
  }

  void _run() {
    _preview.cancel();
    ref
        .read(jobProvider.notifier)
        .start(widget.tool, ToolInput(files: [_file!], params: _params));
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return ToolFrame(
      tool: widget.tool,
      title: 'Compress image',
      hasInput: _file != null,
      onPicked: (files) => _load(files.first),
      body: image == null ? _placeholder(context) : _body(context, image),
      runLabel: 'Compress',
      onRun: image == null ? null : _run,
    );
  }

  Widget _placeholder(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Text(_error!, style: TextStyle(color: c.error)),
      ),
    );
  }

  Widget _body(BuildContext context, LoadedImage image) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final preset = CompressPreset.of(_quality);
    return ListenableBuilder(
      listenable: _preview,
      builder: (context, _) {
        final est = compressEstimate(
          image.bytes.length,
          _preview.loading ? null : _preview.byteLength,
          failed: _preview.failed,
        );
        final note = formatChangeNote(image.file.name, _preview.outputName);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StagePanel(
              height: 300,
              padding: EdgeInsets.zero,
              bar: const [StagePill(label: 'zoom 100%')],
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AnvilRadii.panel),
                child: SizedBox.expand(
                  child: SplitCompare(
                    before: image,
                    after: _preview.bytes,
                    afterTag: '$_quality',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            WsSegmented(
              labels: [for (final p in CompressPreset.values) p.label],
              selected: preset?.index ?? -1,
              onChanged: (i) => _setQuality(CompressPreset.values[i].quality),
            ),
            const SizedBox(height: 14),
            LabeledSlider(
              title: 'Quality',
              valueLabel: '$_quality',
              value: _quality.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              onChanged: (v) => setState(() => _quality = v.round()),
              onChangeEnd: (_) => _measure(),
              startLabel: 'smaller',
              endLabel: 'sharper',
            ),
            const SizedBox(height: 12),
            WsEstimate(label: 'Estimated', value: est.value, delta: est.delta),
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(
                note,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium!.copyWith(color: c.muted),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Before/after at 100% zoom (one image pixel per device pixel): the
/// original left of a draggable divider, [after] (the compressed preview)
/// right of it. Dragging away from the divider pans both together.
class SplitCompare extends StatefulWidget {
  const SplitCompare({
    super.key,
    required this.before,
    required this.after,
    required this.afterTag,
  });

  final LoadedImage before;

  /// Null until the first preview lands; the original stands in.
  final Uint8List? after;
  final String afterTag;

  @override
  State<SplitCompare> createState() => _SplitCompareState();
}

/// Scrim behind the tags — on the photo, so theme-independent.
final _tagScrim = Colors.black.withValues(alpha: 0.6);

class _SplitCompareState extends State<SplitCompare> {
  double _split = 0.5;

  /// The image pixel at the viewport centre; null = image centre.
  Offset? _center;
  bool _draggingSplit = false;

  Offset _clampCenter(Offset c, Size view, double scale) {
    final w = widget.before.width.toDouble();
    final h = widget.before.height.toDouble();
    double clampAxis(double v, double half, double size) =>
        half * 2 >= size ? size / 2 : v.clamp(half, size - half);
    return Offset(
      clampAxis(c.dx, view.width / scale / 2, w),
      clampAxis(c.dy, view.height / scale / 2, h),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final scale = 1 / MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final view = box.biggest;
        final img = widget.before;
        final centre = _clampCenter(
          _center ?? Offset(img.width / 2, img.height / 2),
          view,
          scale,
        );
        final rect = Rect.fromLTWH(
          view.width / 2 - centre.dx * scale,
          view.height / 2 - centre.dy * scale,
          img.width * scale,
          img.height * scale,
        );
        final splitX = _split * view.width;
        Widget layer(Uint8List bytes) => Positioned.fromRect(
          rect: rect,
          child: Image.memory(
            bytes,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            filterQuality: FilterQuality.none,
          ),
        );
        return GestureDetector(
          onPanStart: (d) =>
              _draggingSplit = (d.localPosition.dx - splitX).abs() < 28,
          onPanUpdate: (d) => setState(() {
            if (_draggingSplit) {
              _split = (d.localPosition.dx / view.width).clamp(0.05, 0.95);
            } else {
              _center = _clampCenter(centre - d.delta / scale, view, scale);
            }
          }),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: c.containerHigh),
              Stack(children: [layer(img.bytes)]),
              ClipRect(
                clipper: _RightOf(splitX),
                child: Stack(children: [layer(widget.after ?? img.bytes)]),
              ),
              Positioned(
                left: splitX - 1,
                top: 0,
                bottom: 0,
                width: 2,
                child: const ColoredBox(color: Colors.white),
              ),
              Positioned(
                left: splitX - 16,
                top: view.height / 2 - 16,
                width: 32,
                height: 32,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: Colors.black87,
                  ),
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: _Tag('ORIGINAL', bg: _tagScrim, fg: Colors.white),
              ),
              Positioned(
                right: 10,
                top: 10,
                child: _Tag(widget.afterTag, bg: c.accent, fg: c.onAccent),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RightOf extends CustomClipper<Rect> {
  _RightOf(this.x);
  final double x;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(x, 0, size.width, size.height);

  @override
  bool shouldReclip(_RightOf old) => old.x != x;
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.bg, required this.fg});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(AnvilRadii.chip),
    ),
    child: Text(text, style: AnvilText.mono(11, color: fg)),
  );
}
