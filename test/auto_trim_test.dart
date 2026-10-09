import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:anvil/ui/tool/workspace/auto_trim.dart';

Uint8List _page({bool square = true}) {
  final im = img.Image(width: 100, height: 100);
  img.fill(im, color: img.ColorRgb8(255, 255, 255));
  if (square) {
    img.fillRect(
      im,
      x1: 20,
      y1: 20,
      x2: 60,
      y2: 60,
      color: img.ColorRgb8(0, 0, 0),
    );
  }
  return img.encodePng(im);
}

void main() {
  test('bounds the inked square with a 1% margin', () {
    final r = contentBounds(_page())!;
    expect(r.left, closeTo(0.19, 0.001));
    expect(r.top, closeTo(0.19, 0.001));
    expect(r.right, closeTo(0.62, 0.001));
    expect(r.bottom, closeTo(0.62, 0.001));
  });

  test('a blank page has no content', () {
    expect(contentBounds(_page(square: false)), isNull);
  });
}
