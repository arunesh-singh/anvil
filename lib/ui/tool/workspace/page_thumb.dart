/// One page tile of the PDF workspace: the source thumbnail with every pending
/// edit applied visually — rotation, crop, placed text and signatures — so the
/// grid shows the document as it will export.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anvil/ui/tokens.dart';
import 'package:anvil/ui/tool/editors/pdf_doc_model.dart' show flutterFamily;
import 'package:anvil/ui/tool/workspace/workspace_controller.dart';
import 'package:anvil/ui/tool/workspace/workspace_model.dart';

class PageThumb extends ConsumerStatefulWidget {
  const PageThumb({
    super.key,
    required this.pageRef,
    required this.label,
    this.selected = false,
    this.showLabel = true,
  });

  final PageRef pageRef;

  /// 1-based position, shown as `p<label>`.
  final int label;
  final bool selected;
  final bool showLabel;

  @override
  ConsumerState<PageThumb> createState() => _PageThumbState();
}

class _PageThumbState extends ConsumerState<PageThumb> {
  /// Decoded images by their future, so each future is awaited once.
  final Map<Future<ui.Image>, ui.Image?> _images = {};

  ui.Image? _resolve(Future<ui.Image>? f) {
    if (f == null) return null;
    if (!_images.containsKey(f)) {
      _images[f] = null;
      f.then((img) {
        if (mounted) setState(() => _images[f] = img);
      }, onError: (_) {});
    }
    return _images[f];
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AnvilColors>()!;
    final st = ref.watch(pdfWorkspaceProvider);
    final ctl = ref.read(pdfWorkspaceProvider.notifier);
    final r = widget.pageRef;
    final doc = st.doc;
    final size = pageSizeOf(st.sources, r);
    final crop = doc.crop[r] ?? const Rect.fromLTRB(0, 0, 1, 1);
    final quarter = (doc.rotation[r] ?? 0) ~/ 90;
    final signs = doc.signs[r] ?? const <SignEdit>[];
    final painter = _ThumbPainter(
      thumb: _resolve(ctl.thumbImage(r)),
      pageWidthPt: size.w,
      crop: crop,
      texts: doc.texts[r] ?? const [],
      signs: [
        for (final g in signs)
          (rect: g.rect, image: _resolve(ctl.fileImage(g.imagePath))),
      ],
    );
    final visW = size.w * crop.width, visH = size.h * crop.height;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AnvilRadii.chip),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AnvilRadii.chip),
        border: Border.all(
          color: widget.selected ? c.accent : c.containerHigh,
          width: widget.selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: LayoutBuilder(
                builder: (context, cons) {
                  final turned = quarter.isOdd;
                  final aspect = turned ? visH / visW : visW / visH;
                  var bw = cons.maxWidth, bh = bw / aspect;
                  if (bh > cons.maxHeight) {
                    bh = cons.maxHeight;
                    bw = bh * aspect;
                  }
                  return Center(
                    child: SizedBox(
                      width: bw,
                      height: bh,
                      child: RotatedBox(
                        quarterTurns: quarter,
                        child: CustomPaint(painter: painter),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (widget.showLabel)
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Text(
                  'p${widget.label}',
                  style: AnvilText.mono(10, color: c.onAccent),
                ),
              ),
            ),
          if (widget.selected)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 15, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints the visible (cropped) part of an unrotated page into its size:
/// white sheet, thumbnail, then texts and signatures at their fractions.
class _ThumbPainter extends CustomPainter {
  _ThumbPainter({
    required this.thumb,
    required this.pageWidthPt,
    required this.crop,
    required this.texts,
    required this.signs,
  });

  final ui.Image? thumb;
  final double pageWidthPt;
  final Rect crop;
  final List<TextEdit> texts;
  final List<({Rect rect, ui.Image? image})> signs;

  @override
  void paint(Canvas canvas, Size size) {
    final page = Rect.fromLTWH(
      -crop.left * size.width / crop.width,
      -crop.top * size.height / crop.height,
      size.width / crop.width,
      size.height / crop.height,
    );
    Rect frac(Rect f) => Rect.fromLTRB(
      page.left + f.left * page.width,
      page.top + f.top * page.height,
      page.left + f.right * page.width,
      page.top + f.bottom * page.height,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final t = thumb;
    if (t != null) {
      canvas.drawImageRect(
        t,
        Rect.fromLTWH(0, 0, t.width.toDouble(), t.height.toDouble()),
        page,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    final scale = pageWidthPt <= 0 ? 0.0 : page.width / pageWidthPt;
    for (final e in texts) {
      final tp = TextPainter(
        text: TextSpan(
          text: e.text,
          style: TextStyle(
            fontFamily: flutterFamily(e.family),
            fontSize: e.size * scale,
            fontWeight: e.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: e.italic ? FontStyle.italic : FontStyle.normal,
            color: Color(e.color),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final baseline = tp.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      tp.paint(
        canvas,
        Offset(
          page.left + e.anchor.dx * page.width,
          page.top + e.anchor.dy * page.height - baseline,
        ),
      );
    }
    for (final s in signs) {
      final img = s.image;
      if (img == null) continue;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        frac(s.rect),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.thumb != thumb ||
      old.crop != crop ||
      old.pageWidthPt != pageWidthPt ||
      !identical(old.texts, texts) ||
      old.signs.length != signs.length ||
      Iterable.generate(signs.length).any((i) => old.signs[i] != signs[i]);
}
