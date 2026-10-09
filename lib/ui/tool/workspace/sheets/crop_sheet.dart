/// Crop op: drag the kept area (or use a preset / auto-trim) and apply it to
/// this page, the selection or every page. Per-page crops over an all-pages
/// crop are counted as "overridden" and can be reset in one tap.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/core/isolate_runner.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/rect_handles.dart';
import 'package:anvil/ui/tool/workspace/auto_trim.dart';
import 'package:anvil/ui/tool/workspace/page_preview.dart';
import 'package:anvil/ui/tool/workspace/workspace_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_model.dart';
import 'package:anvil/ui/tool/workspace/workspace_widgets.dart';
import 'package:anvil/ui/widgets/slab.dart';

enum _Preset { trim, a4, square, free }

class CropSheet extends ConsumerStatefulWidget {
  const CropSheet({super.key});

  @override
  ConsumerState<CropSheet> createState() => _CropSheetState();
}

class _CropSheetState extends ConsumerState<CropSheet> {
  late PageRef _page;
  late Rect _rect; // kept area, fractions, top-left origin
  _Preset _preset = _Preset.free;
  ScopeChoice _scope = ScopeChoice.all;
  bool _trimming = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    final st = ref.read(pdfWorkspaceProvider);
    _page = st.focused ?? st.doc.order.first;
    _rect = st.doc.crop[_page] ?? const Rect.fromLTRB(0.05, 0.05, 0.95, 0.95);
  }

  ({double w, double h}) get _pt =>
      pageSizeOf(ref.read(pdfWorkspaceProvider).sources, _page);

  /// Largest centred rect of aspect [aspect] (w/h, in points) inside the page.
  Rect _centred(double aspect) {
    final pt = _pt;
    var w = pt.w, h = w / aspect;
    if (h > pt.h) {
      h = pt.h;
      w = h * aspect;
    }
    final l = (pt.w - w) / 2 / pt.w, t = (pt.h - h) / 2 / pt.h;
    return Rect.fromLTWH(l, t, w / pt.w, h / pt.h);
  }

  Future<void> _autoTrim() async {
    setState(() {
      _preset = _Preset.trim;
      _trimming = true;
      _note = null;
    });
    Rect? bounds;
    try {
      final Uint8List png = await ref
          .read(pdfWorkspaceProvider.notifier)
          .pageRender(_page);
      bounds = await runOffThread(() => contentBounds(png));
    } on ToolException {
      bounds = null;
    }
    if (!mounted) return;
    setState(() {
      _trimming = false;
      if (bounds != null) _rect = bounds;
      // Inline, not a SnackBar: the modal sheet would cover a SnackBar.
      if (bounds == null) _note = 'No content found to trim.';
    });
  }

  Widget _overlay(Rect display, Size pagePt) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final r = Rect.fromLTRB(
      display.left + _rect.left * display.width,
      display.top + _rect.top * display.height,
      display.left + _rect.right * display.width,
      display.top + _rect.bottom * display.height,
    );
    void drag(RectGrip g, Offset delta) {
      final next = dragRect(r, g, delta, display, minSize: 24);
      setState(() {
        _preset = _Preset.free;
        _rect = Rect.fromLTRB(
          (next.left - display.left) / display.width,
          (next.top - display.top) / display.height,
          (next.right - display.left) / display.width,
          (next.bottom - display.top) / display.height,
        );
      });
    }

    Widget handle(RectGrip g, Offset at) => Positioned(
      left: at.dx - 14,
      top: at.dy - 14,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => drag(g, d.delta),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Container(width: 12, height: 12, color: c.accent),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _Dim(display: display, hole: r),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: r,
          child: GestureDetector(
            onPanUpdate: (d) => drag(RectGrip.move, d.delta),
            child: Container(
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.08),
                border: Border.all(color: c.accent, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        handle(RectGrip.tl, r.topLeft),
        handle(RectGrip.tr, r.topRight),
        handle(RectGrip.bl, r.bottomLeft),
        handle(RectGrip.br, r.bottomRight),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final text = Theme.of(context).textTheme;
    final st = ref.watch(pdfWorkspaceProvider);
    final doc = st.doc;
    if (!doc.order.contains(_page)) _page = doc.order.first;
    final pt = _pt;
    String r(double v) => v.round().toString();
    final scope = resolveScope(_scope, doc, _page, st.selection);

    final cropEdits = st.edits.whereType<CropEdit>().toList();
    final overridden = cropEdits.any((e) => e.all)
        ? doc.cropFrom.values.where((e) => !e.all).length
        : 0;

    WsPill preset(_Preset p, String label, VoidCallback onTap) =>
        WsPill(label: label, small: true, on: _preset == p, onTap: onTap);

    return WsSheetFrame(
      title: 'Crop',
      sub:
          '${r(pt.w)}×${r(pt.h)}pt → '
          '${r(_rect.width * pt.w)}×${r(_rect.height * pt.h)}pt',
      children: [
        PagePreview(
          pageRef: _page,
          overlay: _overlay,
          onPage: (p) => setState(() => _page = p),
        ),
        const SizedBox(height: 8),
        WsPillRail(
          children: [
            preset(
              _Preset.trim,
              'Auto-trim margins',
              _trimming ? () {} : _autoTrim,
            ),
            preset(_Preset.a4, 'A4', () {
              setState(() {
                _preset = _Preset.a4;
                _rect = _centred(pt.h >= pt.w ? 1 / math.sqrt2 : math.sqrt2);
              });
            }),
            preset(_Preset.square, 'Square', () {
              setState(() {
                _preset = _Preset.square;
                _rect = _centred(1);
              });
            }),
            preset(
              _Preset.free,
              'Free',
              () => setState(() => _preset = _Preset.free),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'left ${r(_rect.left * pt.w)}pt · top ${r(_rect.top * pt.h)}pt\n'
          'right ${r((1 - _rect.right) * pt.w)}pt · '
          'bottom ${r((1 - _rect.bottom) * pt.h)}pt',
          style: AnvilText.mono(12, color: c.muted),
        ),
        if (_note != null) ...[
          const SizedBox(height: 6),
          Text(_note!, style: text.bodyMedium!.copyWith(color: c.error)),
        ],
        const SizedBox(height: 14),
        ScopeSegment(
          selectionLabels: doc.labelsOf(st.selection),
          total: doc.order.length,
          value: _scope,
          onChanged: (v) => setState(() => _scope = v),
        ),
        if (overridden > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  overridden == 1
                      ? '1 page overridden'
                      : '$overridden pages overridden',
                  style: text.bodyMedium!.copyWith(color: c.muted),
                ),
              ),
              WsPill(
                icon: Icons.undo,
                label: 'Reset',
                small: true,
                onTap: () {
                  final ctl = ref.read(pdfWorkspaceProvider.notifier);
                  for (final e in cropEdits.where((e) => !e.all)) {
                    ctl.removeEdit(e);
                  }
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        PrimaryButton(
          label: 'Apply crop',
          icon: Icons.check,
          onPressed: () {
            ref
                .read(pdfWorkspaceProvider.notifier)
                .addEdit(
                  CropEdit(
                    pages: scope.pages,
                    labels: doc.labelsOf(scope.pages),
                    all: scope.all,
                    rect: _rect,
                  ),
                );
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

/// Dims the page outside the kept area.
class _Dim extends CustomPainter {
  _Dim({required this.display, required this.hole});
  final Rect display;
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(display)
      ..addRect(hole);
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_Dim old) => old.display != display || old.hole != hole;
}
