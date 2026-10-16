/// Add border (`image/border`, design "Add border"): the result is drawn
/// live in Flutter (photo + border per style and colour, the px border
/// scaled to the display), the size is a slider scaled to the photo, colour
/// comes from swatches or an eyedropper sampling the photo itself, and the
/// output dimensions ride on the Run button.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/preview_runner.dart';
import 'package:anvil/ui/tool/editors/tool_frame.dart';
import 'package:anvil/ui/tool/editors/tool_stage.dart';
import 'package:anvil/ui/tool/input/input_picker.dart';
import 'package:anvil/ui/tool/job_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

/// Where the border goes; [param] is the tool's `style` value.
enum BorderLayout {
  even('Even', 'even'),
  polaroid('Polaroid', 'polaroid'),
  square('Square fit', 'square');

  const BorderLayout(this.label, this.param);
  final String label;
  final String param;
}

/// Swatch presets: white, near-black, beige, blue.
const borderSwatches = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFF1A1B1E),
  Color(0xFFD9C7A8),
  Color(0xFF4D67FF),
];

/// Slider range in px for a [width]×[height] photo: 1 to 10% of the long
/// edge (at least 2 so the slider always has travel).
({int min, int max}) borderRange(int width, int height) =>
    (min: 1, max: math.max(2, (math.max(width, height) * 0.10).round()));

/// Starting border: 4% of the long edge, inside [borderRange].
int borderDefault(int width, int height) {
  final r = borderRange(width, height);
  return (math.max(width, height) * 0.04).round().clamp(r.min, r.max);
}

/// The output canvas and where the photo sits on it, mirroring the native
/// tool: even = [sizePx] all round; polaroid = [sizePx] sides/top and 4×
/// at the bottom; square = a `max(w, h) + 2·sizePx` square, photo centred.
({int width, int height, double left, double top}) borderGeometry(
  int width,
  int height,
  int sizePx,
  BorderLayout layout,
) => switch (layout) {
  BorderLayout.even => (
    width: width + 2 * sizePx,
    height: height + 2 * sizePx,
    left: sizePx.toDouble(),
    top: sizePx.toDouble(),
  ),
  BorderLayout.polaroid => (
    width: width + 2 * sizePx,
    height: height + 5 * sizePx,
    left: sizePx.toDouble(),
    top: sizePx.toDouble(),
  ),
  BorderLayout.square => () {
    final side = math.max(width, height) + 2 * sizePx;
    return (
      width: side,
      height: side,
      left: (side - width) / 2,
      top: (side - height) / 2,
    );
  }(),
};

/// The tool params for the chosen border.
Map<String, dynamic> borderParams(
  int sizePx,
  Color color,
  BorderLayout layout,
) => {'sizePx': sizePx, 'color': hexOf(color), 'style': layout.param};

/// The opaque colour at fractional position ([fx], [fy]) of a [width]×
/// [height] RGBA buffer (clamped to the edges).
Color sampleRgba(Uint8List rgba, int width, int height, double fx, double fy) {
  final x = (fx * width).floor().clamp(0, width - 1);
  final y = (fy * height).floor().clamp(0, height - 1);
  final i = (y * width + x) * 4;
  return Color.fromARGB(0xFF, rgba[i], rgba[i + 1], rgba[i + 2]);
}

/// `#RRGGBB` — the trailing label next to the swatches.
String rgbHex(Color c) => '#${hexOf(c).substring(3)}';

/// Long edge of the eyedropper's sample buffer: plenty for picking a colour
/// without holding a full-size RGBA copy of a 12 MP photo.
const _sampleEdge = 1024;

class BorderImageScreen extends ConsumerStatefulWidget {
  const BorderImageScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<BorderImageScreen> createState() => _BorderImageScreenState();
}

class _BorderImageScreenState extends ConsumerState<BorderImageScreen> {
  InputFile? _file;
  LoadedImage? _image;
  String? _error;
  int _loadSeq = 0;
  int _sizePx = 1;
  Color _color = borderSwatches.first;
  BorderLayout _layout = BorderLayout.even;
  bool _picking = false;

  /// The photo decoded once (downscaled) for the eyedropper, on first use.
  Future<({Uint8List rgba, int width, int height})>? _samples;

  @override
  void initState() {
    super.initState();
    final shared = takeSharedInput(ref, widget.tool.meta);
    if (shared != null) _load(shared);
  }

  Future<void> _load(InputFile f) async {
    final seq = ++_loadSeq;
    setState(() {
      _file = f;
      _image = null;
      _error = null;
      _samples = null;
      _picking = false;
    });
    try {
      final image = await loadImageFile(f);
      if (seq != _loadSeq || !mounted) return;
      setState(() {
        _image = image;
        _sizePx = borderDefault(image.width, image.height);
      });
    } on ToolException catch (e) {
      if (seq != _loadSeq || !mounted) return;
      setState(() => _error = e.message);
    }
  }

  /// Decodes on the engine's image threads (not the UI isolate) at most
  /// [_sampleEdge] on the long side.
  static Future<({Uint8List rgba, int width, int height})> _decodeSamples(
    LoadedImage image,
  ) async {
    final landscape = image.width >= image.height;
    final codec = await ui.instantiateImageCodec(
      image.bytes,
      targetWidth: landscape ? math.min(image.width, _sampleEdge) : null,
      targetHeight: landscape ? null : math.min(image.height, _sampleEdge),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    final decoded = frame.image;
    try {
      final data = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw const ToolException('Could not read the photo’s colours.');
      }
      return (
        rgba: data.buffer.asUint8List(),
        width: decoded.width,
        height: decoded.height,
      );
    } finally {
      decoded.dispose();
    }
  }

  void _toggleEyedropper() {
    final image = _image;
    if (image == null) return;
    setState(() {
      _picking = !_picking;
      if (_picking) _samples ??= _decodeSamples(image);
    });
  }

  Future<void> _sampleAt(double fx, double fy) async {
    final pending = _samples;
    if (pending == null) return;
    try {
      final s = await pending;
      if (!mounted) return;
      setState(() {
        _color = sampleRgba(s.rgba, s.width, s.height, fx, fy);
        _picking = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _samples = null;
        _picking = false;
      });
    }
  }

  void _run() {
    ref
        .read(jobProvider.notifier)
        .start(
          widget.tool,
          ToolInput(
            files: [_file!],
            params: borderParams(_sizePx, _color, _layout),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final out = image == null
        ? null
        : borderGeometry(image.width, image.height, _sizePx, _layout);
    return ToolFrame(
      tool: widget.tool,
      title: 'Add border',
      hasInput: _file != null,
      onPicked: (files) => _load(files.first),
      body: image == null ? _placeholder(context) : _body(context, image),
      runLabel: 'Add border',
      runDetail: out == null ? null : '· ${out.width} × ${out.height} px',
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
    final range = borderRange(image.width, image.height);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StagePanel(
          height: 280,
          bar: [
            if (_picking)
              const StagePill(
                icon: Icons.colorize,
                label: 'Tap the photo to pick',
              ),
          ],
          child: BorderPreview(
            image: image,
            sizePx: _sizePx,
            color: _color,
            layout: _layout,
            onImageTap: _picking ? _sampleAt : null,
          ),
        ),
        const SizedBox(height: 14),
        LabeledSlider(
          title: 'Border',
          valueLabel: '$_sizePx px',
          value: _sizePx.toDouble(),
          min: range.min.toDouble(),
          max: range.max.toDouble(),
          divisions: range.max - range.min,
          onChanged: (v) => setState(() => _sizePx = v.round()),
          startLabel: 'thin',
          endLabel: 'thick',
        ),
        const SizedBox(height: 12),
        const SectionEyebrow('Colour'),
        const SizedBox(height: 8),
        SwatchRow(
          colors: borderSwatches,
          selected: _color,
          onSelected: (c) => setState(() {
            _color = c;
            _picking = false;
          }),
          onEyedropper: _toggleEyedropper,
          eyedropperActive: _picking,
          trailing: rgbHex(_color),
        ),
        const SizedBox(height: 14),
        WsSegmented(
          labels: [for (final l in BorderLayout.values) l.label],
          selected: _layout.index,
          onChanged: (i) => setState(() => _layout = BorderLayout.values[i]),
        ),
      ],
    );
  }
}

/// The bordered result drawn live: a [color] canvas of the output's aspect
/// with the photo placed per [layout], all scaled to fit. [onImageTap]
/// receives the tap as a fraction of the photo (border taps are ignored).
class BorderPreview extends StatelessWidget {
  const BorderPreview({
    super.key,
    required this.image,
    required this.sizePx,
    required this.color,
    required this.layout,
    this.onImageTap,
  });

  final LoadedImage image;
  final int sizePx;
  final Color color;
  final BorderLayout layout;
  final void Function(double fx, double fy)? onImageTap;

  @override
  Widget build(BuildContext context) {
    final g = borderGeometry(image.width, image.height, sizePx, layout);
    return LayoutBuilder(
      builder: (context, box) {
        final scale = math.min(
          box.maxWidth / g.width,
          box.maxHeight / g.height,
        );
        final photo = Rect.fromLTWH(
          g.left * scale,
          g.top * scale,
          image.width * scale,
          image.height * scale,
        );
        return SizedBox(
          width: g.width * scale,
          height: g.height * scale,
          child: GestureDetector(
            onTapUp: onImageTap == null
                ? null
                : (d) {
                    if (!photo.contains(d.localPosition)) return;
                    onImageTap!(
                      (d.localPosition.dx - photo.left) / photo.width,
                      (d.localPosition.dy - photo.top) / photo.height,
                    );
                  },
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: color)),
                Positioned.fromRect(
                  rect: photo,
                  child: Image.memory(
                    image.bytes,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
