import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/ui/tool/editors/border_image_screen.dart';
import 'package:anvil/ui/tool/editors/compress_image_screen.dart';
import 'package:anvil/ui/tool/editors/resize_image_screen.dart';

void main() {
  group('compress estimate', () {
    const before = 5033165; // 4.8 MB
    const after = 1153434; // 1.1 MB

    test('states before → after with the saving', () {
      final e = compressEstimate(before, after);
      expect(e.value, '4.8 MB → 1.1 MB');
      expect(e.delta, '−77%');
    });

    test('a bigger output reads as a plus', () {
      expect(compressEstimate(1000, 1200).delta, '+20%');
    });

    test('measuring shows … and a failure ?, both without a delta', () {
      expect(compressEstimate(before, null).value, '4.8 MB → …');
      expect(compressEstimate(before, null).delta, isNull);
      expect(compressEstimate(before, null, failed: true).value, '4.8 MB → ?');
    });

    test('presets map to qualities; off-preset selects none', () {
      expect(CompressPreset.of(40), CompressPreset.smallest);
      expect(CompressPreset.of(75), CompressPreset.balanced);
      expect(CompressPreset.of(90), CompressPreset.sharpest);
      expect(CompressPreset.of(74), isNull);
    });

    test('a format change is called out; jpeg ↔ jpg is not one', () {
      expect(
        formatChangeNote('a.png', 'a.jpg'),
        'PNG has no quality setting — saves as JPG.',
      );
      expect(formatChangeNote('a.jpeg', 'a.jpg'), isNull);
      expect(formatChangeNote('a.webp', 'a.webp'), isNull);
      expect(formatChangeNote('a.png', null), isNull);
    });
  });

  group('resize maths', () {
    test('percent scales both sides', () {
      expect(scaleByPercent(4032, 3024, 50), (width: 2016, height: 1512));
      expect(scaleByPercent(4032, 3024, 33), (width: 1331, height: 998));
    });

    test('pixels: locked keeps the source aspect, unlocked does not', () {
      const cur = (width: 4032, height: 3024);
      expect(withWidth(cur, 1200, srcW: 4032, srcH: 3024, locked: true), (
        width: 1200,
        height: 900,
      ));
      expect(withHeight(cur, 900, srcW: 4032, srcH: 3024, locked: true), (
        width: 1200,
        height: 900,
      ));
      expect(withWidth(cur, 1200, srcW: 4032, srcH: 3024, locked: false), (
        width: 1200,
        height: 3024,
      ));
      expect(withHeight(cur, 500, srcW: 4032, srcH: 3024, locked: false), (
        width: 4032,
        height: 500,
      ));
    });

    test('long edge applies to the longer side, landscape and portrait', () {
      expect(fitLongEdge(4032, 3024, 1080), (width: 1080, height: 810));
      expect(fitLongEdge(3024, 4032, 1080), (width: 810, height: 1080));
      expect(longEdgeOf((width: 810, height: 1080), 3024, 4032), 1080);
    });

    test('quick sizes: 50% and long-edge px targets (4K = 3840)', () {
      expect(QuickSize.half.apply(4032, 3024), (width: 2016, height: 1512));
      expect(QuickSize.edge1200.apply(4032, 3024), (width: 1200, height: 900));
      expect(QuickSize.uhd.apply(3024, 4032), (width: 2880, height: 3840));
      expect(QuickSize.edge2048.apply(1000, 1000), (width: 2048, height: 2048));
    });

    test('params are always explicit — never 0, never absurd', () {
      expect(resizeParams(scaleByPercent(10, 10, 1)), {
        'width': 1,
        'height': 1,
      });
      expect(resizeParams(fitLongEdge(5000, 10, 1000)), {
        'width': 1000,
        'height': 2,
      });
      expect(fitLongEdge(4032, 3024, 99999).width, maxResizeSide);
      expect(percentOf((width: 2016, height: 1512), 4032), 50);
    });
  });

  group('border', () {
    test('slider range is 1..10% of the long edge, with travel', () {
      expect(borderRange(4032, 3024), (min: 1, max: 403));
      expect(borderRange(3024, 4032), (min: 1, max: 403));
      expect(borderRange(10, 5), (min: 1, max: 2));
      expect(borderDefault(4032, 3024), 161);
      expect(borderDefault(10, 5), 1);
    });

    test('output geometry per style matches the native tool', () {
      expect(borderGeometry(100, 50, 10, BorderLayout.even), (
        width: 120,
        height: 70,
        left: 10.0,
        top: 10.0,
      ));
      expect(borderGeometry(100, 50, 10, BorderLayout.polaroid), (
        width: 120,
        height: 100,
        left: 10.0,
        top: 10.0,
      ));
      expect(borderGeometry(100, 50, 10, BorderLayout.square), (
        width: 120,
        height: 120,
        left: 10.0,
        top: 35.0,
      ));
    });

    test('params carry size, #AARRGGBB colour and style', () {
      expect(borderParams(48, const Color(0xFF1A1B1E), BorderLayout.polaroid), {
        'sizePx': 48,
        'color': '#FF1A1B1E',
        'style': 'polaroid',
      });
      expect(
        borderParams(1, Colors.white, BorderLayout.square)['style'],
        'square',
      );
      expect(rgbHex(const Color(0xFFD9C7A8)), '#D9C7A8');
    });

    test('eyedropper samples the pixel under the tap', () {
      // 2×2: red, green / blue, white.
      final rgba = Uint8List.fromList([
        255, 0, 0, 255, 0, 255, 0, 255, //
        0, 0, 255, 255, 255, 255, 255, 255,
      ]);
      expect(sampleRgba(rgba, 2, 2, 0.1, 0.1), const Color(0xFFFF0000));
      expect(sampleRgba(rgba, 2, 2, 0.9, 0.1), const Color(0xFF00FF00));
      expect(sampleRgba(rgba, 2, 2, 0.1, 0.9), const Color(0xFF0000FF));
      expect(sampleRgba(rgba, 2, 2, 1.0, 1.0), const Color(0xFFFFFFFF));
    });
  });
}
