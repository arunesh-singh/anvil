/// Pure helpers for the ML image tools: subject-mask compositing and
/// float32 NCHW tensor packing for the ONNX engine contract.
/// No Flutter/plugin imports — host-unit-testable (test/image_ml_test.dart).
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:anvil/engines/onnx_engine.dart' show ImageTensor;

/// How [applyMask] treats the background.
enum MaskBackground { transparent, color, blur }

/// Composites a subject-confidence [mask] (row-major, one double per pixel,
/// values 0..1) over [src]:
/// - [MaskBackground.transparent]: subject cutout on alpha.
/// - [MaskBackground.color]: subject over a solid [color] (RGBA ints).
/// - [MaskBackground.blur]: subject over a blurred copy of the photo.
/// [threshold] is the minimum confidence that counts as subject.
img.Image applyMask(
  img.Image src,
  List<double> mask, {
  required MaskBackground background,
  (int, int, int, int) color = (255, 255, 255, 255),
  int blurRadius = 12,
  double threshold = 0.5,
}) {
  final w = src.width;
  final h = src.height;
  assert(mask.length == w * h, 'mask must be one confidence per pixel');
  final out = img.Image(width: w, height: h, numChannels: 4);
  final img.Image? blurred = background == MaskBackground.blur
      ? img.gaussianBlur(src.convert(numChannels: 4), radius: blurRadius)
      : null;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      if (mask[y * w + x] >= threshold) {
        out.setPixelRgba(x, y, p.r, p.g, p.b, 255);
      } else {
        switch (background) {
          case MaskBackground.transparent:
            out.setPixelRgba(x, y, 0, 0, 0, 0);
          case MaskBackground.color:
            out.setPixelRgba(x, y, color.$1, color.$2, color.$3, color.$4);
          case MaskBackground.blur:
            final b = blurred!.getPixel(x, y);
            out.setPixelRgba(x, y, b.r, b.g, b.b, 255);
        }
      }
    }
  }
  return out;
}

/// Circle-crops the subject cutout onto a colored disc — profile pictures.
img.Image profilePhoto(
  img.Image src,
  List<double> mask, {
  (int, int, int, int) background = (229, 231, 235, 255),
}) {
  final cutout =
      applyMask(src, mask, background: MaskBackground.transparent);
  final d = cutout.width < cutout.height ? cutout.width : cutout.height;
  final out = img.Image(width: d, height: d, numChannels: 4);
  final r = d / 2.0;
  for (var y = 0; y < d; y++) {
    for (var x = 0; x < d; x++) {
      final dx = x - r + 0.5;
      final dy = y - r + 0.5;
      if (dx * dx + dy * dy <= r * r) {
        out.setPixelRgba(x, y, background.$1, background.$2, background.$3,
            background.$4);
      } else {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
  // Center the subject horizontally, bottom-aligned like a portrait.
  final ox = (d - cutout.width) ~/ 2;
  final oy = d - cutout.height;
  img.compositeImage(out, cutout, dstX: ox, dstY: oy);
  return out;
}

/// Builds a 1-channel inpainting mask (1.0 = fill) from rectangles.
ImageTensor rectMask(
    int width, int height, List<(int, int, int, int)> rects) {
  final data = Float32List(width * height);
  for (final (rx, ry, rw, rh) in rects) {
    final x0 = rx.clamp(0, width);
    final y0 = ry.clamp(0, height);
    final x1 = (rx + rw).clamp(0, width);
    final y1 = (ry + rh).clamp(0, height);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        data[y * width + x] = 1.0;
      }
    }
  }
  return ImageTensor(data, 1, height, width);
}

/// Packs an RGB image into a float32 NCHW tensor in [0,1].
ImageTensor imageToTensor(img.Image src) {
  final w = src.width;
  final h = src.height;
  final data = Float32List(3 * h * w);
  final plane = h * w;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      final i = y * w + x;
      data[i] = p.rNormalized.toDouble();
      data[plane + i] = p.gNormalized.toDouble();
      data[2 * plane + i] = p.bNormalized.toDouble();
    }
  }
  return ImageTensor(data, 3, h, w);
}

/// Unpacks a float32 NCHW tensor in [0,1] back into an RGB image.
img.Image tensorToImage(ImageTensor t) {
  final out = img.Image(width: t.width, height: t.height, numChannels: 3);
  final plane = t.height * t.width;
  for (var y = 0; y < t.height; y++) {
    for (var x = 0; x < t.width; x++) {
      final i = y * t.width + x;
      out.setPixelRgb(
        x,
        y,
        (t.data[i] * 255).round().clamp(0, 255),
        (t.data[plane + i] * 255).round().clamp(0, 255),
        (t.data[2 * plane + i] * 255).round().clamp(0, 255),
      );
    }
  }
  return out;
}

/// Parses `#RRGGBB`/`#AARRGGBB` into RGBA ints for the compositors above.
(int, int, int, int) parseColor(String hex) {
  var s = hex.startsWith('#') ? hex.substring(1) : hex;
  if (s.length == 6) s = 'FF$s';
  final v = int.tryParse(s, radix: 16);
  if (s.length != 8 || v == null) {
    throw ArgumentError.value(hex, 'hex', 'expected #RRGGBB or #AARRGGBB');
  }
  return ((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff, (v >> 24) & 0xff);
}
