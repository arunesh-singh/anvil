/// The Background screen (design `explorations/tools-workspace.html`, frame
/// "Background"): one screen for blur-background, remove-bg and
/// change-bg-photo. The subject is detected once when the photo loads; the
/// Blur / Remove / Colour treatments then preview live over that mask, the
/// mask itself can be shown and hand-fixed with a brush, and Apply runs the
/// registered tool for the chosen treatment.
///
/// A hand-fixed mask travels to the tool as an 8-bit PNG via the undeclared
/// `maskPath` param ([maskPathParam]); an untouched mask is not sent, so the
/// tool re-detects and the output matches an agent call.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/isolate_runner.dart';
import 'package:anvil/core/registry.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/mlkit_engine.dart';
import 'package:anvil/tools/image/image_ml_helpers.dart' as ml;
import 'package:anvil/tools/image/image_ml_tools.dart' show maskPathParam;
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/tool_frame.dart';
import 'package:anvil/ui/tool/editors/tool_stage.dart';
import 'package:anvil/ui/tool/input/input_picker.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// The three treatments and the registered tool each one runs.
enum BackgroundMode {
  blur('Blur', 'image/blur-background'),
  remove('Remove', 'image/remove-bg'),
  colour('Colour', 'image/change-bg-photo');

  const BackgroundMode(this.label, this.toolId);
  final String label;
  final String toolId;

  /// The mode for an opened tool id; Blur for anything else.
  static BackgroundMode forTool(String qualifiedId) => values.firstWhere(
    (m) => m.toolId == qualifiedId,
    orElse: () => BackgroundMode.blur,
  );
}

/// Blur slider range, in the tool's `blurRadius` pixels (default 12).
const blurRadiusMin = 2;
const blurRadiusMax = 40;
const blurRadiusDefault = 12;

/// Named strength for a `blurRadius` (the slider's value label).
String blurStrengthLabel(int radius) => switch (radius) {
  <= 5 => 'Subtle',
  <= 9 => 'Light',
  <= 15 => 'Medium',
  <= 25 => 'Strong',
  _ => 'Max',
};

/// Background colour presets: white, black, light grey, blue.
const backgroundSwatches = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFFE5E7EB),
  Color(0xFF4D67FF),
];

/// Preview long edge: big enough to judge an edge, small enough to recompose
/// in a blink after each brush stroke.
const _previewEdge = 1024;

/// The decoded photo at preview size plus its detected mask.
class _Stage {
  const _Stage({
    required this.width,
    required this.height,
    required this.previewWidth,
    required this.previewHeight,
    required this.previewPng,
    required this.previewRgba,
    required this.fullMask,
    required this.previewMask,
    required this.subjectFound,
  });

  /// Full image size (the tool's decode size; strokes live in this space).
  final int width;
  final int height;
  final int previewWidth;
  final int previewHeight;
  final Uint8List previewPng;
  final Uint8List previewRgba;
  final Uint8List fullMask;
  final Uint8List previewMask;
  final bool subjectFound;

  double get previewScale => previewWidth / width;
}

/// Decodes [bytes]: (full width, full height, preview w, preview h, preview
/// PNG, preview RGBA).
Future<(int, int, int, int, Uint8List, Uint8List)> _decodeForStage(
  Uint8List bytes,
) => runOffThread(() {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const ToolException('Could not read the image.');
  }
  final long = decoded.width > decoded.height ? decoded.width : decoded.height;
  final preview = long <= _previewEdge
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? _previewEdge : null,
          height: decoded.height > decoded.width ? _previewEdge : null,
          interpolation: img.Interpolation.average,
        );
  final rgba = preview
      .convert(format: img.Format.uint8, numChannels: 4)
      .getBytes(order: img.ChannelOrder.rgba);
  return (
    decoded.width,
    decoded.height,
    preview.width,
    preview.height,
    img.encodePng(preview, level: 1),
    Uint8List.fromList(rgba),
  );
});

/// Quantizes the detected mask and scales it for the preview: (full mask,
/// preview mask, any subject pixel).
Future<(Uint8List, Uint8List, bool)> _prepareMasks(
  List<double>? confidence,
  int w,
  int h,
  int pw,
  int ph,
) => runOffThread(() {
  final full = confidence == null
      ? Uint8List(w * h)
      : ml.maskToBytes(confidence);
  final preview = ml.resizeMask(full, w, h, pw, ph);
  return (full, preview, full.any((v) => v >= 128));
});

/// Preview layers for the current strokes: (subject cutout PNG, mask
/// overlay PNG).
Future<(Uint8List, Uint8List)> _previewLayers(
  Uint8List rgba,
  int pw,
  int ph,
  Uint8List baseMask,
  List<ml.MaskStroke> strokes,
  (int, int, int) tint,
) => runOffThread(() {
  final mask = Uint8List.fromList(baseMask);
  ml.paintStrokes(mask, pw, ph, strokes);
  final photo = img.Image.fromBytes(
    width: pw,
    height: ph,
    bytes: rgba.buffer,
    numChannels: 4,
  );
  final cutout = ml.applyMask(
    photo,
    ml.maskConfidence(mask),
    background: ml.MaskBackground.transparent,
  );
  final overlay = img.Image.fromBytes(
    width: pw,
    height: ph,
    bytes: ml.maskOverlayRgba(mask, pw, ph, tint).buffer,
    numChannels: 4,
  );
  return (img.encodePng(cutout, level: 1), img.encodePng(overlay, level: 1));
});

/// The edited full-size mask as the `maskPath` PNG.
Future<Uint8List> _editedMaskPng(
  Uint8List fullMask,
  int w,
  int h,
  List<ml.MaskStroke> strokes,
) => runOffThread(() {
  final mask = Uint8List.fromList(fullMask);
  ml.paintStrokes(mask, w, h, strokes);
  return ml.encodeMaskPng(mask, w, h);
});

class BackgroundScreen extends ConsumerStatefulWidget {
  const BackgroundScreen({super.key, required this.tool});

  /// The tool that was opened; picks the initial treatment.
  final ToolModule tool;

  @override
  ConsumerState<BackgroundScreen> createState() => _BackgroundScreenState();
}

class _BackgroundScreenState extends ConsumerState<BackgroundScreen> {
  InputFile? _file;
  _Stage? _stage;
  String? _error;
  int _loadSeq = 0;

  late BackgroundMode _mode = BackgroundMode.forTool(
    widget.tool.meta.qualifiedId,
  );
  int _blurRadius = blurRadiusDefault;
  Color _color = backgroundSwatches.first;
  bool _eyedropper = false;

  bool _showMask = false;
  bool _painting = false;
  bool _brushAdd = true;

  /// Brush radius in on-screen pixels; converted to mask pixels per stroke.
  double _brushSize = 16;

  /// Committed strokes in full-image mask pixels.
  final List<ml.MaskStroke> _strokes = [];

  /// The stroke being drawn, in on-screen stage coordinates.
  List<Offset>? _live;
  Uint8List? _cutoutPng;
  Uint8List? _overlayPng;
  int _layerSeq = 0;
  bool _preparingRun = false;

  @override
  void initState() {
    super.initState();
    final shared = takeSharedInput(ref, widget.tool.meta);
    if (shared != null) _load(shared);
  }

  Future<void> _load(InputFile f) async {
    final seq = ++_loadSeq;
    _file = f;
    _stage = null;
    _error = null;
    _strokes.clear();
    _cutoutPng = null;
    _overlayPng = null;
    _painting = false;
    if (mounted) setState(() {});
    try {
      final bytes = await File(f.path).readAsBytes();
      final (w, h, pw, ph, png, rgba) = await _decodeForStage(bytes);
      if (seq != _loadSeq) return;
      List<double>? confidence;
      try {
        final mask = await getIt<MlKitEngine>().subjectMask(f.path, w, h);
        confidence = mask.confidence;
      } on NoSubjectException {
        // No subject: show the photo anyway; the brush can paint one in.
        confidence = null;
      }
      if (confidence != null && confidence.length != w * h) {
        throw const ToolException(
          'Subject segmentation returned an unexpected mask size.',
        );
      }
      final (full, preview, found) = await _prepareMasks(
        confidence,
        w,
        h,
        pw,
        ph,
      );
      if (seq != _loadSeq || !mounted) return;
      setState(() {
        _stage = _Stage(
          width: w,
          height: h,
          previewWidth: pw,
          previewHeight: ph,
          previewPng: png,
          previewRgba: rgba,
          fullMask: full,
          previewMask: preview,
          subjectFound: found,
        );
      });
      await _refreshLayers();
    } catch (e) {
      if (seq != _loadSeq || !mounted) return;
      setState(() {
        _error = e is ToolException ? e.message : 'Could not open this photo.';
      });
    }
  }

  (int, int, int) get _tint {
    final a = Theme.of(context).extension<AnvilColors>()!.accent;
    return ((a.r * 255).round(), (a.g * 255).round(), (a.b * 255).round());
  }

  Future<void> _refreshLayers() async {
    final stage = _stage;
    if (stage == null) return;
    final seq = ++_layerSeq;
    final strokes = [for (final s in _strokes) s.scaled(stage.previewScale)];
    final (cutout, overlay) = await _previewLayers(
      stage.previewRgba,
      stage.previewWidth,
      stage.previewHeight,
      stage.previewMask,
      strokes,
      _tint,
    );
    if (seq != _layerSeq || !mounted) return;
    setState(() {
      _cutoutPng = cutout;
      _overlayPng = overlay;
    });
  }

  bool get _hasSubject =>
      (_stage?.subjectFound ?? false) || _strokes.any((s) => s.add);

  ToolModule _toolFor(BackgroundMode mode) =>
      getIt<ToolRegistry>().byId(mode.toolId) ?? widget.tool;

  Future<void> _run() async {
    final f = _file;
    final stage = _stage;
    if (f == null || stage == null) return;
    final params = <String, dynamic>{
      ...switch (_mode) {
        BackgroundMode.blur => {'blurRadius': _blurRadius},
        BackgroundMode.remove => const <String, dynamic>{},
        BackgroundMode.colour => {'color': hexOf(_color)},
      },
    };
    if (_strokes.isNotEmpty) {
      setState(() => _preparingRun = true);
      try {
        final png = await _editedMaskPng(
          stage.fullMask,
          stage.width,
          stage.height,
          List.of(_strokes),
        );
        final dir = await getTemporaryDirectory();
        final file = File(
          p.join(
            dir.path,
            'bg_mask_${DateTime.now().millisecondsSinceEpoch}.png',
          ),
        );
        await file.writeAsBytes(png);
        params[maskPathParam] = file.path;
      } finally {
        if (mounted) setState(() => _preparingRun = false);
      }
      if (!mounted) return;
    }
    ref
        .read(jobProvider.notifier)
        .start(_toolFor(_mode), ToolInput(files: [f], params: params));
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
    _refreshLayers();
  }

  // ── Stage gestures ─────────────────────────────────────────────────────────

  void _pickColourAt(Offset local, Size box) {
    final stage = _stage!;
    final x = (local.dx / box.width * stage.previewWidth).floor().clamp(
      0,
      stage.previewWidth - 1,
    );
    final y = (local.dy / box.height * stage.previewHeight).floor().clamp(
      0,
      stage.previewHeight - 1,
    );
    final o = (y * stage.previewWidth + x) * 4;
    final px = stage.previewRgba;
    setState(() {
      _color = Color.fromARGB(255, px[o], px[o + 1], px[o + 2]);
      _eyedropper = false;
    });
  }

  void _endStroke(Size box) {
    final stage = _stage!;
    final live = _live;
    if (live == null || live.isEmpty) return;
    final toMask = stage.width / box.width;
    setState(() {
      _strokes.add(
        ml.MaskStroke(
          add: _brushAdd,
          radius: _brushSize * toMask,
          points: [for (final o in live) (o.dx * toMask, o.dy * toMask)],
        ),
      );
      _live = null;
    });
    _refreshLayers();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    final busy = stage == null || _preparingRun;
    return ToolFrame(
      tool: widget.tool,
      title: 'Background',
      hasInput: _file != null,
      onPicked: (files) => _load(files.first),
      actions: [
        if (_strokes.isNotEmpty)
          WsChip(icon: Icons.undo, tooltip: 'Undo stroke', onTap: _undo),
      ],
      body: _body(context),
      runLabel: 'Apply',
      runDetail: stage == null
          ? null
          : '· ${stage.width} × ${stage.height} PNG',
      onRun: busy || !_hasSubject || _painting ? null : _run,
      scroll: !_painting,
    );
  }

  Widget _body(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final stage = _stage;
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Text(_error!, style: TextStyle(color: c.error)),
      );
    }
    if (stage == null) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final found = stage.subjectFound || _strokes.isNotEmpty;
    final panel = StagePanel(
      height: _painting ? null : 320,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 52),
      bar: [
        StagePill(
          icon: _showMask || _painting
              ? Icons.visibility
              : Icons.visibility_off,
          tooltip: 'Show the subject mask',
          onTap: _painting
              ? null
              : () => setState(() => _showMask = !_showMask),
        ),
        StagePill(
          label: _strokes.isNotEmpty
              ? 'subject edited'
              : (found ? 'subject found' : 'no subject found'),
        ),
      ],
      child: AspectRatio(
        aspectRatio: stage.previewWidth / stage.previewHeight,
        child: LayoutBuilder(
          builder: (context, box) =>
              _stageLayers(context, stage, Size(box.maxWidth, box.maxHeight)),
        ),
      ),
    );
    // Paint mode drops the scroll view (ToolFrame.scroll) so brush drags are
    // never stolen by vertical scrolling; the stage flexes instead.
    if (_painting) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: panel),
          const SizedBox(height: 14),
          ..._paintControls(context),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panel,
        const SizedBox(height: 14),
        ..._treatment(context),
        const SizedBox(height: 10),
        const InfoCard('Runs on-device. First use downloads a 9 MB model.'),
      ],
    );
  }

  Widget _stageLayers(BuildContext context, _Stage stage, Size box) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    // The tool blurs with sigma = radius·⅔ in full-image pixels; scale that to
    // the on-screen photo so the preview matches the output.
    final sigma = _blurRadius * 2 / 3 * box.width / stage.width;
    final photo = Image.memory(
      stage.previewPng,
      fit: BoxFit.fill,
      gaplessPlayback: true,
    );
    final background = switch (_mode) {
      BackgroundMode.blur => ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        ),
        child: photo,
      ),
      BackgroundMode.remove => const CustomPaint(painter: _Checkerboard()),
      BackgroundMode.colour => ColoredBox(color: _color),
    };
    final cutout = _cutoutPng;
    final overlay = _overlayPng;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AnvilRadii.chip),
      child: Stack(
        fit: StackFit.expand,
        children: [
          background,
          if (cutout != null)
            Image.memory(cutout, fit: BoxFit.fill, gaplessPlayback: true)
          else
            photo,
          if ((_showMask || _painting) && overlay != null)
            Image.memory(overlay, fit: BoxFit.fill, gaplessPlayback: true),
          if (_live != null)
            CustomPaint(
              painter: _LiveStroke(
                points: _live!,
                radius: _brushSize,
                color: (_brushAdd ? c.accent : c.error).withValues(alpha: 0.5),
              ),
            ),
          if (_painting)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => setState(() => _live = [d.localPosition]),
              onPanUpdate: (d) =>
                  setState(() => _live = [...?_live, d.localPosition]),
              onPanEnd: (_) => _endStroke(box),
              onTapUp: (d) {
                _live = [d.localPosition];
                _endStroke(box);
              },
            )
          else if (_eyedropper)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _pickColourAt(d.localPosition, box),
            ),
        ],
      ),
    );
  }

  List<Widget> _treatment(BuildContext context) => [
    WsSegmented(
      labels: [for (final m in BackgroundMode.values) m.label],
      selected: _mode.index,
      onChanged: (i) => setState(() {
        _mode = BackgroundMode.values[i];
        _eyedropper = false;
      }),
    ),
    const SizedBox(height: 14),
    ...switch (_mode) {
      BackgroundMode.blur => [
        LabeledSlider(
          title: 'Strength',
          valueLabel: '${blurStrengthLabel(_blurRadius)} · $_blurRadius',
          value: _blurRadius.toDouble(),
          min: blurRadiusMin.toDouble(),
          max: blurRadiusMax.toDouble(),
          divisions: blurRadiusMax - blurRadiusMin,
          onChanged: (v) => setState(() => _blurRadius = v.round()),
          startLabel: 'subtle',
          endLabel: 'strong',
        ),
      ],
      BackgroundMode.remove => const <Widget>[],
      BackgroundMode.colour => [
        SwatchRow(
          colors: backgroundSwatches,
          selected: _color,
          onSelected: (col) => setState(() {
            _color = col;
            _eyedropper = false;
          }),
          onEyedropper: () => setState(() => _eyedropper = !_eyedropper),
          eyedropperActive: _eyedropper,
          trailing: _eyedropper ? 'tap the photo' : hexOf(_color),
        ),
      ],
    },
    const SizedBox(height: 12),
    _FixEdgeRow(
      onTap: () => setState(() {
        _painting = true;
        _eyedropper = false;
      }),
    ),
  ];

  List<Widget> _paintControls(BuildContext context) => [
    WsSegmented(
      labels: const ['Add', 'Erase'],
      selected: _brushAdd ? 0 : 1,
      onChanged: (i) => setState(() => _brushAdd = i == 0),
    ),
    const SizedBox(height: 14),
    LabeledSlider(
      title: 'Brush',
      valueLabel: '${_brushSize.round()} px',
      value: _brushSize,
      min: 4,
      max: 48,
      divisions: 44,
      onChanged: (v) => setState(() => _brushSize = v),
      startLabel: 'fine',
      endLabel: 'broad',
    ),
    const SizedBox(height: 12),
    SecondaryButton(
      label: 'Done',
      icon: Icons.check,
      onPressed: () => setState(() => _painting = false),
    ),
  ];
}

class _FixEdgeRow extends StatelessWidget {
  const _FixEdgeRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AnvilRadii.row),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: WsRow(
          leading: Icon(Icons.brush, color: c.iconStrong),
          title: 'Fix the edge',
          trailing: Text(
            'paint to add / erase',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: c.muted),
          ),
        ),
      ),
    );
  }
}

/// Transparency checkerboard behind a cut-out preview (content, not theme).
class _Checkerboard extends CustomPainter {
  const _Checkerboard();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 10.0;
    final light = Paint()..color = const Color(0xFFF2F2F2);
    final dark = Paint()..color = const Color(0xFFD9D9D9);
    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = (y.isEven ? 1 : 0); x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(_Checkerboard oldDelegate) => false;
}

/// The stroke in progress, before it is rasterised into the mask.
class _LiveStroke extends CustomPainter {
  const _LiveStroke({
    required this.points,
    required this.radius,
    required this.color,
  });
  final List<Offset> points;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = radius * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (points.length == 1) {
      canvas.drawCircle(
        points.first,
        radius,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final o in points.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LiveStroke old) =>
      old.points != points || old.radius != radius || old.color != color;
}
