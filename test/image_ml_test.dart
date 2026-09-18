import 'dart:typed_data';

import 'package:anvil/engines/onnx_engine.dart' show ImageTensor;
import 'package:anvil/tools/image/image_ml_helpers.dart' as ml;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 4×4 red image; mask marks the left half as subject.
img.Image _src() {
  final im = img.Image(width: 4, height: 4, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 0, 0, 255));
  return im;
}

List<double> _leftHalfMask() => [
      for (var y = 0; y < 4; y++) ...[1.0, 1.0, 0.0, 0.0],
    ];

void main() {
  group('applyMask', () {
    test('transparent background keeps subject pixels, clears the rest', () {
      final out = ml.applyMask(_src(), _leftHalfMask(),
          background: ml.MaskBackground.transparent);
      expect(out.getPixel(0, 0).a, 255);
      expect(out.getPixel(0, 0).r, 255);
      expect(out.getPixel(3, 0).a, 0);
    });

    test('color background paints non-subject pixels', () {
      final out = ml.applyMask(_src(), _leftHalfMask(),
          background: ml.MaskBackground.color, color: (0, 0, 255, 255));
      expect(out.getPixel(3, 3).b, 255);
      expect(out.getPixel(3, 3).r, 0);
      expect(out.getPixel(0, 0).r, 255);
    });

    test('blur background keeps subject sharp', () {
      final out = ml.applyMask(_src(), _leftHalfMask(),
          background: ml.MaskBackground.blur, blurRadius: 2);
      // Uniform red image: blurred background is still red; the invariant we
      // assert is full opacity everywhere and unchanged subject.
      expect(out.getPixel(0, 0).r, 255);
      expect(out.getPixel(3, 3).a, 255);
    });
  });

  test('profilePhoto returns a square disc with transparent corners', () {
    final out = ml.profilePhoto(_src(), _leftHalfMask(),
        background: (10, 20, 30, 255));
    expect(out.width, out.height);
    // Right corner: outside the disc AND not covered by the subject cutout.
    expect(out.getPixel(out.width - 1, 0).a, 0,
        reason: 'non-subject corner outside the disc stays transparent');
    final c = out.getPixel(out.width ~/ 2, out.height ~/ 2);
    expect(c.a, 255, reason: 'disc center is opaque');
    // Subject pixels stay opaque even where they overflow the disc.
    expect(out.getPixel(0, out.height - 1).a, 255);
  });

  group('tensors', () {
    test('image -> tensor -> image round-trips pixel values', () {
      final im = img.Image(width: 3, height: 2, numChannels: 3);
      im.setPixelRgb(0, 0, 255, 0, 0);
      im.setPixelRgb(1, 0, 0, 255, 0);
      im.setPixelRgb(2, 1, 0, 0, 255);
      final t = ml.imageToTensor(im);
      expect((t.channels, t.height, t.width), (3, 2, 3));
      final back = ml.tensorToImage(t);
      expect(back.getPixel(0, 0).r, 255);
      expect(back.getPixel(1, 0).g, 255);
      expect(back.getPixel(2, 1).b, 255);
    });

    test('rectMask fills exactly the clamped rectangle', () {
      final ImageTensor mask = ml.rectMask(4, 4, [(2, 2, 10, 10)]);
      expect(mask.channels, 1);
      final data = Float32List.fromList(mask.data);
      expect(data[2 * 4 + 2], 1.0);
      expect(data[3 * 4 + 3], 1.0);
      expect(data[0], 0.0);
      expect(data.where((v) => v == 1.0).length, 4); // 2x2 after clamping
    });
  });

  test('parseColor handles #RRGGBB and #AARRGGBB, rejects garbage', () {
    expect(ml.parseColor('#FF0000'), (255, 0, 0, 255));
    expect(ml.parseColor('#80FF0000'), (255, 0, 0, 128));
    expect(() => ml.parseColor('red'), throwsArgumentError);
  });
}
