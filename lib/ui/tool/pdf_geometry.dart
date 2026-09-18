import 'package:flutter/widgets.dart';

/// Pure canvas↔PDF coordinate mapping for the PDF WYSIWYG editors.
///
/// The editors fit a page PNG into [ImageCanvas] passing the page's
/// point-size as `imagePx`, so the on-screen `displayRect` and the page in
/// points share one uniform scale `s = pagePt.width / displayRect.width`
/// (points per canvas pixel). PDF user space is origin bottom-left, so the
/// Y axis flips relative to the canvas (origin top-left).
///
/// No engine or widget-state dependencies — unit-testable in isolation.

/// Canvas-space rect (inside [displayRect]) → PDF rect in points, origin
/// bottom-left. Used by the image-stamp and erase editors.
({double x, double y, double width, double height}) canvasRectToPdf(
    Rect canvasRect, Rect displayRect, Size pagePt) {
  final s = pagePt.width / displayRect.width;
  final wPt = canvasRect.width * s;
  final hPt = canvasRect.height * s;
  final leftPt = (canvasRect.left - displayRect.left) * s;
  final topFromTop = (canvasRect.top - displayRect.top) * s;
  return (x: leftPt, y: pagePt.height - topFromTop - hPt, width: wPt, height: hPt);
}

/// Canvas-space crop rect → per-edge margins in points (distance from each
/// page edge to the crop rect). Used by the crop editor.
({double left, double top, double right, double bottom}) canvasRectToMargins(
    Rect cropRect, Rect displayRect, Size pagePt) {
  final s = pagePt.width / displayRect.width;
  return (
    left: (cropRect.left - displayRect.left) * s,
    top: (cropRect.top - displayRect.top) * s,
    right: (displayRect.right - cropRect.right) * s,
    bottom: (displayRect.bottom - cropRect.bottom) * s,
  );
}

/// Canvas-space point → PDF point (origin bottom-left). Used by the text editor
/// for the text box's bottom-left anchor.
Offset canvasPointToPdf(Offset p, Rect displayRect, Size pagePt) {
  final s = pagePt.width / displayRect.width;
  return Offset((p.dx - displayRect.left) * s,
      pagePt.height - (p.dy - displayRect.top) * s);
}
