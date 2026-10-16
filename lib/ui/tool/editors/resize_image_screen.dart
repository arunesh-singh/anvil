/// Resize image (`image/resize`, design "Resize image"): starts from the
/// real decoded dimensions; percent, pixels (with an aspect lock replacing
/// "0 = auto") or long edge, plus quick sizes. The tool always receives an
/// explicit width AND height; the output size comes from running the real
/// tool ([PreviewRunner]) and rides on the Run button.
library;

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
import 'package:anvil/ui/widgets/slab.dart';

typedef PixelSize = ({int width, int height});

/// Largest side the screen will ask for: a typo like 99999 would otherwise
/// ask the native side for a multi-gigabyte bitmap.
const maxResizeSide = 16384;

int _side(num v) => v.round().clamp(1, maxResizeSide);

/// [percent] of the source on both sides.
PixelSize scaleByPercent(int srcW, int srcH, int percent) =>
    (width: _side(srcW * percent / 100), height: _side(srcH * percent / 100));

/// The source scaled so its longer side is [edge].
PixelSize fitLongEdge(int srcW, int srcH, int edge) => srcW >= srcH
    ? (width: _side(edge), height: _side(edge * srcH / srcW))
    : (width: _side(edge * srcW / srcH), height: _side(edge));

/// [current] with a new [width]; [locked] keeps the source aspect.
PixelSize withWidth(
  PixelSize current,
  int width, {
  required int srcW,
  required int srcH,
  required bool locked,
}) => (
  width: _side(width),
  height: locked ? _side(width * srcH / srcW) : current.height,
);

/// [current] with a new [height]; [locked] keeps the source aspect.
PixelSize withHeight(
  PixelSize current,
  int height, {
  required int srcW,
  required int srcH,
  required bool locked,
}) => (
  width: locked ? _side(height * srcW / srcH) : current.width,
  height: _side(height),
);

/// The width's share of the source, as the Percent box shows it.
int percentOf(PixelSize t, int srcW) => (t.width * 100 / srcW).round();

/// The side the Long edge box edits: the source's longer one.
int longEdgeOf(PixelSize t, int srcW, int srcH) =>
    srcW >= srcH ? t.width : t.height;

/// The tool params for [t] — never 0, so the output is exactly [t].
Map<String, dynamic> resizeParams(PixelSize t) => {
  'width': t.width,
  'height': t.height,
};

enum ResizeMode {
  percent('Percent'),
  pixels('Pixels'),
  longEdge('Long edge');

  const ResizeMode(this.label);
  final String label;
}

/// One-tap targets: half size, or a long-edge pixel size (4K = 3840).
enum QuickSize {
  half('50%', 0),
  edge1080('1080 px', 1080),
  edge1200('1200 px', 1200),
  edge2048('2048 px', 2048),
  uhd('4K', 3840);

  const QuickSize(this.label, this.longEdge);
  final String label;

  /// 0 = half the source instead of a long edge.
  final int longEdge;

  PixelSize apply(int srcW, int srcH) => longEdge == 0
      ? scaleByPercent(srcW, srcH, 50)
      : fitLongEdge(srcW, srcH, longEdge);
}

class ResizeImageScreen extends ConsumerStatefulWidget {
  const ResizeImageScreen({super.key, required this.tool});

  final ToolModule tool;

  @override
  ConsumerState<ResizeImageScreen> createState() => _ResizeImageScreenState();
}

class _ResizeImageScreenState extends ConsumerState<ResizeImageScreen> {
  InputFile? _file;
  LoadedImage? _image;
  String? _error;
  int _loadSeq = 0;
  ResizeMode _mode = ResizeMode.pixels;
  bool _locked = true;
  PixelSize _target = (width: 1, height: 1);
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
      setState(() {
        _image = image;
        _target = (width: image.width, height: image.height);
      });
      _measure();
    } on ToolException catch (e) {
      if (seq != _loadSeq || !mounted) return;
      setState(() => _error = e.message);
    }
  }

  void _setTarget(PixelSize t) {
    setState(() => _target = t);
    _measure();
  }

  void _measure() {
    final image = _image;
    if (image != null) _preview.request(image.file, resizeParams(_target));
  }

  void _run() {
    _preview.cancel();
    ref
        .read(jobProvider.notifier)
        .start(
          widget.tool,
          ToolInput(files: [_file!], params: resizeParams(_target)),
        );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return ListenableBuilder(
      listenable: _preview,
      builder: (context, _) {
        final size = _preview.byteLength;
        return ToolFrame(
          tool: widget.tool,
          title: 'Resize image',
          hasInput: _file != null,
          onPicked: (files) => _load(files.first),
          body: image == null ? _placeholder(context) : _body(context, image),
          runLabel: 'Resize',
          runDetail: image == null
              ? null
              : _preview.loading
              ? '· …'
              : size == null
              ? null
              : '· ~${compactBytes(size)}',
          onRun: image == null ? null : _run,
        );
      },
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
    final w = image.width;
    final h = image.height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StagePanel(
          height: 220,
          bar: [
            StagePill(label: '$w × $h → ${_target.width} × ${_target.height}'),
          ],
          child: Image.memory(image.bytes, fit: BoxFit.contain),
        ),
        const SizedBox(height: 14),
        WsSegmented(
          labels: [for (final m in ResizeMode.values) m.label],
          selected: _mode.index,
          onChanged: (i) => setState(() => _mode = ResizeMode.values[i]),
        ),
        const SizedBox(height: 12),
        switch (_mode) {
          ResizeMode.percent => NumberBox(
            key: const ValueKey('percent'),
            label: 'Scale',
            suffix: '%',
            value: percentOf(_target, w),
            onChanged: (v) => _setTarget(scaleByPercent(w, h, v)),
          ),
          ResizeMode.pixels => Row(
            children: [
              Expanded(
                child: NumberBox(
                  key: const ValueKey('width'),
                  label: 'Width',
                  value: _target.width,
                  onChanged: (v) => _setTarget(
                    withWidth(_target, v, srcW: w, srcH: h, locked: _locked),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              LinkToggle(
                on: _locked,
                onTap: () {
                  _locked = !_locked;
                  // Re-locking snaps the height back onto the source aspect.
                  _setTarget(
                    _locked
                        ? withWidth(
                            _target,
                            _target.width,
                            srcW: w,
                            srcH: h,
                            locked: true,
                          )
                        : _target,
                  );
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumberBox(
                  key: const ValueKey('height'),
                  label: 'Height',
                  value: _target.height,
                  onChanged: (v) => _setTarget(
                    withHeight(_target, v, srcW: w, srcH: h, locked: _locked),
                  ),
                ),
              ),
            ],
          ),
          ResizeMode.longEdge => NumberBox(
            key: const ValueKey('longEdge'),
            label: w >= h ? 'Long edge · width' : 'Long edge · height',
            suffix: 'px',
            value: longEdgeOf(_target, w, h),
            onChanged: (v) => _setTarget(fitLongEdge(w, h, v)),
          ),
        },
        const SizedBox(height: 14),
        const SectionEyebrow('Quick sizes'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in QuickSize.values)
              WsPill(
                label: q.label,
                on: q.apply(w, h) == _target,
                onTap: () => _setTarget(q.apply(w, h)),
              ),
          ],
        ),
      ],
    );
  }
}
