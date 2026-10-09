/// "Auto-trim margins" for the workspace crop sheet: finds the inked area of a
/// rendered page. Top-level and pure so it can run in `runOffThread`.
library;

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

/// Bounds of the page content in [png] as fractions (top-left origin),
/// inflated by 1% per side and clamped to the page; null when the page has no
/// content. A pixel is content when it is visible (alpha > 16) and not
/// near-white (luminance < 235).
Rect? contentBounds(Uint8List png) {
  final image = img.decodePng(png);
  if (image == null) return null;
  final w = image.width, h = image.height;
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (final px in image) {
    if (px.a <= 16 * px.maxChannelValue / 255) continue;
    final lum = px.luminanceNormalized * 255;
    if (lum >= 235) continue;
    if (px.x < minX) minX = px.x;
    if (px.x > maxX) maxX = px.x;
    if (px.y < minY) minY = px.y;
    if (px.y > maxY) maxY = px.y;
  }
  if (maxX < 0) return null;
  double clamp(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
  return Rect.fromLTRB(
    clamp(minX / w - 0.01),
    clamp(minY / h - 0.01),
    clamp((maxX + 1) / w + 0.01),
    clamp((maxY + 1) / h + 0.01),
  );
}
