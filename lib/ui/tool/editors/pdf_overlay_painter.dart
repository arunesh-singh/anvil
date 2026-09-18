import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:anvil/ui/tool/editors/pdf_doc_model.dart';

/// Renders a [DocPage]'s elements — both on-canvas (via [DocPagePainter]) and
/// flattened to a transparent PNG for stamping (via [renderOverlayPng]).

/// Draws every element of [page] onto [canvas], assuming the canvas is already
/// in page-point space (origin top-left). [lookup] resolves an image's decoded
/// [ui.Image] by its bytes; missing images are skipped.
void paintDoc(Canvas canvas, DocPage page, ui.Image? Function(Uint8List) lookup) {
  for (final el in page.elements) {
    switch (el) {
      case TextEl t:
        final tp = TextPainter(
          text: TextSpan(
            text: t.text,
            style: TextStyle(
              color: t.color.withValues(alpha: t.opacity.clamp(0.0, 1.0)),
              fontSize: t.sizePt,
              fontFamily: flutterFamily(t.family),
              fontWeight: t.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
              height: 1.0,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, t.posPt);
      case ImageEl im:
        final image = lookup(im.png);
        if (image == null) break;
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(
              0, 0, image.width.toDouble(), image.height.toDouble()),
          im.rectPt,
          Paint()..filterQuality = FilterQuality.medium,
        );
      case StrokeEl s:
        if (s.pointsPt.isEmpty) break;
        final paint = Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.widthPt
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        if (s.pointsPt.length == 1) {
          canvas.drawCircle(
              s.pointsPt.first, s.widthPt / 2, Paint()..color = s.color);
          break;
        }
        final path = Path()
          ..moveTo(s.pointsPt.first.dx, s.pointsPt.first.dy);
        for (final p in s.pointsPt.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      case HighlightEl hg:
        canvas.drawRect(hg.rectPt, Paint()..color = hg.color);
      case BlackoutEl b:
        canvas.drawRect(b.rectPt, Paint()..color = b.color);
      case ShapeEl sh:
        final paint = Paint()..color = sh.color;
        if (sh.kind == ShapeKind.line) {
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = sh.strokePt
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(sh.rectPt.topLeft, sh.rectPt.bottomRight, paint);
        } else if (sh.filled) {
          canvas.drawRect(sh.rectPt, paint);
        } else {
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = sh.strokePt;
          canvas.drawRect(sh.rectPt, paint);
        }
    }
  }
}

/// Flattens [page]'s elements into a transparent PNG sized to the page (scaled
/// by [exportScale], capped so neither dimension exceeds 3000 px). Returns null
/// when the page has no elements (caller skips stamping it).
Future<Uint8List?> renderOverlayPng(DocPage page,
    {double exportScale = 2.0}) async {
  if (page.elements.isEmpty) return null;
  final w = page.sizePt.w;
  final h = page.sizePt.h;
  if (w <= 0 || h <= 0) return null;
  var scale = exportScale;
  if (w * scale > 3000) scale = 3000 / w;
  if (h * scale > 3000) scale = 3000 / h;

  // Pre-decode every image so paintDoc can stay synchronous.
  final images = <Uint8List, ui.Image>{};
  for (final el in page.elements) {
    if (el is ImageEl && !images.containsKey(el.png)) {
      images[el.png] = await decodeImage(el.png);
    }
  }

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(scale);
  paintDoc(canvas, page, (bytes) => images[bytes]);
  final picture = recorder.endRecording();
  final img = await picture.toImage((w * scale).round(), (h * scale).round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  img.dispose();
  for (final image in images.values) {
    image.dispose();
  }
  return data?.buffer.asUint8List();
}

/// Decodes PNG/JPEG [bytes] into a [ui.Image].
Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// On-canvas painter: maps page points into [displayRect] and paints elements
/// using the already-decoded [images] cache.
class DocPagePainter extends CustomPainter {
  DocPagePainter({
    required this.page,
    required this.displayRect,
    required this.images,
  });

  final DocPage page;
  final Rect displayRect;
  final Map<Uint8List, ui.Image> images;

  @override
  void paint(Canvas canvas, Size size) {
    if (displayRect.width <= 0 || page.sizePt.w <= 0) return;
    final s = displayRect.width / page.sizePt.w;
    canvas.save();
    canvas.clipRect(displayRect);
    canvas.translate(displayRect.left, displayRect.top);
    canvas.scale(s);
    paintDoc(canvas, page, (bytes) => images[bytes]);
    canvas.restore();
  }

  @override
  bool shouldRepaint(DocPagePainter old) => true;
}
