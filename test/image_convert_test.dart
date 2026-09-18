import 'dart:convert';
import 'dart:typed_data';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/tools/image/image_codecs.dart' as codecs;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 3×2 RGB test bitmap with distinct corner colors.
Uint8List _png() {
  final im = img.Image(width: 3, height: 2, numChannels: 4);
  im.setPixelRgba(0, 0, 255, 0, 0, 255);
  im.setPixelRgba(2, 1, 0, 0, 255, 255);
  return img.encodePng(im);
}

Uint8List _animatedGif(int frames) {
  final base = img.Image(width: 4, height: 4);
  for (var i = 1; i < frames; i++) {
    final f = img.Image(width: 4, height: 4);
    img.fill(f, color: img.ColorRgb8(i * 40, 0, 0));
    base.addFrame(f);
  }
  return img.encodeGif(base);
}

void main() {
  group('transcode', () {
    test('png -> gif -> png round-trips dimensions', () {
      final gif = codecs.transcode(_png(), 'png', 'gif');
      expect(img.decodeGif(gif), isNotNull);
      final back = codecs.transcode(gif, 'gif', 'png');
      final decoded = img.decodePng(back)!;
      expect((decoded.width, decoded.height), (3, 2));
    });

    test('png -> tiff decodes with same size', () {
      final tiff = codecs.transcode(_png(), 'png', 'tiff');
      final decoded = img.decodeTiff(tiff)!;
      expect((decoded.width, decoded.height), (3, 2));
    });

    test('animated gif -> apng keeps all frames', () {
      final apng = codecs.transcode(_animatedGif(3), 'gif', 'apng');
      final decoded = img.decodePng(apng)!;
      expect(decoded.numFrames, 3);
    });

    test('animated gif -> jpg flattens to a single frame', () {
      final jpg = codecs.transcode(_animatedGif(3), 'gif', 'jpg');
      final decoded = img.decodeJpg(jpg)!;
      expect(decoded.numFrames, 1);
    });

    test('garbage bytes throw a user-facing ToolException', () {
      expect(
        () => codecs.transcode(Uint8List.fromList([1, 2, 3]), 'png', 'gif'),
        throwsA(isA<ToolException>()),
      );
    });
  });

  group('vector/document wrappers', () {
    test('rasterToSvg embeds a base64 image at intrinsic size', () {
      final svg = codecs.rasterToSvg(_png(), 'png');
      expect(svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
      expect(svg, contains('width="3" height="2"'));
      expect(svg, contains('data:image/png;base64,'));
      // The payload decodes back to the source pixels.
      final b64 = RegExp('base64,([^"]+)').firstMatch(svg)!.group(1)!;
      expect(img.decodePng(base64Decode(b64)), isNotNull);
    });

    test('rasterToEps produces a valid EPS header and bounding box', () {
      final eps = ascii.decode(codecs.rasterToEps(_png(), 'png'),
          allowInvalid: true);
      expect(eps, startsWith('%!PS-Adobe-3.0 EPSF-3.0'));
      expect(eps, contains('%%BoundingBox: 0 0 3 2'));
      expect(eps, contains('false 3 colorimage'));
      expect(eps.trimRight(), endsWith('%%EOF'));
      // First pixel is pure red -> hex data starts with ff0000.
      final dataStart = eps.indexOf('colorimage\n') + 'colorimage\n'.length;
      expect(eps.substring(dataStart, dataStart + 6), 'ff0000');
    });

    test('rasterToPdf wraps the bitmap in a one-page PDF', () async {
      final pdf = await codecs.rasterToPdf(_png(), 'png');
      expect(ascii.decode(pdf.sublist(0, 5), allowInvalid: true), '%PDF-');
    });
  });

  group('renders', () {
    test('renderTextPng draws multi-line text on the chosen background', () {
      final png = codecs.renderTextPng('hi\nthere',
          fontSize: 14, background: '#FF00FF00');
      final im = img.decodePng(png)!;
      expect(im.width, greaterThan(0));
      // Corner pixel is pure green background.
      final p = im.getPixel(0, 0);
      expect((p.r, p.g, p.b), (0, 255, 0));
    });

    test('renderTextPng rejects empty text and bad colors', () {
      expect(() => codecs.renderTextPng('  '), throwsA(isA<ToolException>()));
      expect(() => codecs.renderTextPng('x', color: 'nope'),
          throwsA(isA<ToolException>()));
    });

    test('renderQuoteCard wraps long text and stays 16:9 or taller', () {
      final png = codecs.renderQuoteCard(
          'a long quote that definitely needs to wrap onto several lines '
          'to fit within the card width limits of the renderer',
          width: 640);
      final im = img.decodePng(png)!;
      expect(im.width, 640);
      expect(im.height, greaterThanOrEqualTo(640 * 9 ~/ 16));
    });

    test('renderBarChart draws bars for numeric rows', () {
      final png = codecs.renderBarChart('label,value\nA,10\nB,20',
          width: 300, height: 200);
      final im = img.decodePng(png)!;
      expect((im.width, im.height), (300, 200));
      // Some pixels must be the bar blue (59,130,246).
      var found = false;
      for (var y = 0; y < im.height && !found; y++) {
        for (var x = 0; x < im.width && !found; x++) {
          final p = im.getPixel(x, y);
          found = p.r == 59 && p.g == 130 && p.b == 246;
        }
      }
      expect(found, isTrue, reason: 'expected bar pixels in the chart');
    });

    test('renderBarChart rejects CSV without numeric rows', () {
      expect(() => codecs.renderBarChart('label,value\nA,x'),
          throwsA(isA<ToolException>()));
    });
  });
}
