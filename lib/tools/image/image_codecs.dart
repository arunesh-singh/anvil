/// Pure-Dart codec/render helpers for the image conversion tools.
///
/// No Flutter imports — everything here runs in isolates via `runOffThread`
/// and is host-unit-testable (test/image_convert_test.dart). Exotic formats
/// (TIFF/PSD/GIF/WebP decode, APNG/GIF/TIFF encode) go through `package:image`;
/// PDF/AI wrapping goes through `package:pdf`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/tools/converters/table_data.dart';

// ── Decode / encode ──────────────────────────────────────────────────────────

/// Decodes [src] using the decoder for [srcExt] (falls back to sniffing).
/// Throws a user-facing [ToolException] when the bytes are unreadable.
img.Image decodeByExt(Uint8List src, String srcExt) {
  final decoded = switch (srcExt) {
    'gif' => img.decodeGif(src),
    'tif' || 'tiff' => img.decodeTiff(src),
    'psd' => img.decodePsd(src),
    'webp' => img.decodeWebP(src),
    'png' => img.decodePng(src),
    'jpg' || 'jpeg' => img.decodeJpg(src),
    _ => img.decodeImage(src),
  };
  if (decoded == null) {
    throw const ToolException(
        'Could not read the image — the file may be corrupted or in an '
        'unsupported format.');
  }
  return decoded;
}

/// Encodes [image] as [format] ('png' | 'apng' | 'jpg' | 'gif' | 'tiff').
/// Multi-frame images stay animated for apng/gif; 'png'/'jpg'/'tiff' take the
/// first frame only.
Uint8List encodeAs(img.Image image, String format) => switch (format) {
      'apng' => img.encodePng(image),
      'png' => img.encodePng(image, singleFrame: true),
      'jpg' || 'jpeg' => img.encodeJpg(image, quality: 90),
      'gif' => img.encodeGif(image),
      'tiff' => img.encodeTiff(image, singleFrame: true),
      _ => throw ArgumentError.value(format, 'format'),
    };

/// One-shot decode+encode: the core of every pure-Dart format conversion.
Uint8List transcode(Uint8List src, String srcExt, String outFormat) =>
    encodeAs(decodeByExt(src, srcExt), outFormat);

// ── Vector/document wrappers ─────────────────────────────────────────────────

/// Wraps a raster image into a standalone SVG (`<image>` with a base64 data
/// URI) at its intrinsic pixel size. JPEG stays JPEG inside the wrapper;
/// everything else is normalized to PNG.
String rasterToSvg(Uint8List src, String srcExt) {
  final image = decodeByExt(src, srcExt);
  final isJpg = srcExt == 'jpg' || srcExt == 'jpeg';
  final payload = isJpg ? src : encodeAs(image, 'png');
  final mime = isJpg ? 'image/jpeg' : 'image/png';
  final w = image.width;
  final h = image.height;
  return '<svg xmlns="http://www.w3.org/2000/svg" '
      'width="$w" height="$h" viewBox="0 0 $w $h">'
      '<image width="$w" height="$h" '
      'href="data:$mime;base64,${base64Encode(payload)}"/>'
      '</svg>';
}

/// Encodes a raster image as a minimal EPS (Level-2 `colorimage`, 8-bit RGB
/// hex data). Valid input for Ghostscript/Illustrator/printers.
Uint8List rasterToEps(Uint8List src, String srcExt) {
  final image = decodeByExt(src, srcExt);
  final w = image.width;
  final h = image.height;
  final header = '%!PS-Adobe-3.0 EPSF-3.0\n'
      '%%BoundingBox: 0 0 $w $h\n'
      '%%Pages: 1\n'
      '%%EndComments\n'
      'gsave\n'
      '$w $h scale\n'
      '$w $h 8 [$w 0 0 -$h 0 $h]\n'
      '{currentfile ${w * 3} string readhexstring pop} bind\n'
      'false 3 colorimage\n';
  const hexDigits = '0123456789abcdef';
  final rowBytes = w * 6 + 1; // 3 channels × 2 hex chars + newline
  final data = Uint8List(rowBytes * h);
  var o = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      for (final c in [p.r.toInt(), p.g.toInt(), p.b.toInt()]) {
        data[o++] = hexDigits.codeUnitAt((c >> 4) & 0xf);
        data[o++] = hexDigits.codeUnitAt(c & 0xf);
      }
    }
    data[o++] = 0x0a;
  }
  const footer = 'grestore\nshowpage\n%%EOF\n';
  final out = BytesBuilder(copy: false)
    ..add(ascii.encode(header))
    ..add(data)
    ..add(ascii.encode(footer));
  return out.toBytes();
}

/// Wraps a raster image into a single-page PDF at its intrinsic pixel size.
/// Also used for `.ai` output — Illustrator files are PDF-compatible.
Future<Uint8List> rasterToPdf(Uint8List src, String srcExt) async {
  final image = decodeByExt(src, srcExt);
  final png = encodeAs(image, 'png');
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat:
        PdfPageFormat(image.width.toDouble(), image.height.toDouble()),
    build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
  ));
  return doc.save();
}

// ── Text / chart rendering (bitmap fonts, isolate-safe) ─────────────────────

int _lineWidth(img.BitmapFont font, String line) {
  var w = 0;
  for (final c in line.codeUnits) {
    final ch = font.characters[c];
    w += ch?.xAdvance ?? font.base ~/ 2;
  }
  return w;
}

img.BitmapFont _fontFor(int size) =>
    size <= 18 ? img.arial14 : (size <= 32 ? img.arial24 : img.arial48);

/// Renders [text] (multi-line) onto a solid background. [color]/[background]
/// are `#RRGGBB` or `#AARRGGBB` hex.
Uint8List renderTextPng(
  String text, {
  int fontSize = 32,
  String color = '#FF000000',
  String background = '#FFFFFFFF',
  int padding = 24,
}) {
  if (text.trim().isEmpty) {
    throw const ToolException('Enter some text to render.');
  }
  final font = _fontFor(fontSize);
  final lines = const LineSplitter().convert(text);
  final lineH = font.lineHeight;
  final textW = lines.fold(0, (m, l) => l.isEmpty ? m : _max(m, _lineWidth(font, l)));
  final width = textW + 2 * padding;
  final height = lines.length * lineH + 2 * padding;
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: _color(image, background));
  final fg = _color(image, color);
  for (var i = 0; i < lines.length; i++) {
    img.drawString(image, lines[i],
        font: font, x: padding, y: padding + i * lineH, color: fg);
  }
  return img.encodePng(image);
}

/// Quote-card style render: centered text on a colored card.
Uint8List renderQuoteCard(
  String text, {
  int width = 1080,
  String color = '#FFFFFFFF',
  String background = '#FF1F2937',
}) {
  if (text.trim().isEmpty) {
    throw const ToolException('Enter some text to render.');
  }
  final font = img.arial48;
  final lineH = font.lineHeight;
  final maxTextW = width - 160;
  // Greedy word wrap by measured width.
  final lines = <String>[];
  for (final para in const LineSplitter().convert(text)) {
    var line = '';
    for (final word in para.split(' ')) {
      final candidate = line.isEmpty ? word : '$line $word';
      if (line.isNotEmpty && _lineWidth(font, candidate) > maxTextW) {
        lines.add(line);
        line = word;
      } else {
        line = candidate;
      }
    }
    lines.add(line);
  }
  final height = _max(lines.length * lineH + 160, width * 9 ~/ 16);
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: _color(image, background));
  final fg = _color(image, color);
  final top = (height - lines.length * lineH) ~/ 2;
  for (var i = 0; i < lines.length; i++) {
    final w = _lineWidth(font, lines[i]);
    img.drawString(image, lines[i],
        font: font, x: (width - w) ~/ 2, y: top + i * lineH, color: fg);
  }
  return img.encodePng(image);
}

/// Draws a bar chart from CSV text: first column = label, second = number.
Uint8List renderBarChart(String csvText, {int width = 1200, int height = 800}) {
  final table = TableData.parseCsv(csvText);
  final data = <(String, double)>[];
  for (var r = 0; r < table.rows.length; r++) {
    final n = double.tryParse(table.cell(r, 1).trim());
    if (n != null) data.add((table.cell(r, 0), n));
  }
  if (data.isEmpty) {
    throw const ToolException(
        'The CSV needs at least one row with a label and a numeric value '
        '(label,value).');
  }
  const margin = 80;
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
  final axis = img.ColorRgba8(55, 65, 81, 255);
  final bar = img.ColorRgba8(59, 130, 246, 255);
  // Axes.
  img.drawLine(image,
      x1: margin, y1: height - margin, x2: width - margin ~/ 2,
      y2: height - margin, color: axis, thickness: 2);
  img.drawLine(image,
      x1: margin, y1: margin ~/ 2, x2: margin, y2: height - margin,
      color: axis, thickness: 2);
  final maxV = data.fold(0.0, (m, d) => d.$2 > m ? d.$2 : m);
  final plotW = width - margin - margin ~/ 2;
  final plotH = height - margin - margin ~/ 2 - margin ~/ 2;
  final slot = plotW ~/ data.length;
  final barW = _max(4, slot * 7 ~/ 10);
  for (var i = 0; i < data.length; i++) {
    final hPx = maxV <= 0 ? 0 : (data[i].$2 / maxV * plotH).round();
    final x1 = margin + i * slot + (slot - barW) ~/ 2;
    final y1 = height - margin - hPx;
    img.fillRect(image,
        x1: x1, y1: y1, x2: x1 + barW, y2: height - margin - 1, color: bar);
    final label = data[i].$1;
    final lw = _lineWidth(img.arial14, label);
    img.drawString(image, label,
        font: img.arial14,
        x: margin + i * slot + (slot - lw) ~/ 2,
        y: height - margin + 8,
        color: axis);
    final value = _trimNum(data[i].$2);
    final vw = _lineWidth(img.arial14, value);
    img.drawString(image, value,
        font: img.arial14,
        x: margin + i * slot + (slot - vw) ~/ 2,
        y: y1 - img.arial14.lineHeight - 2,
        color: axis);
  }
  return img.encodePng(image);
}

// ── Small utilities ──────────────────────────────────────────────────────────

int _max(int a, int b) => a > b ? a : b;

String _trimNum(double v) =>
    v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

/// Parses `#RRGGBB` / `#AARRGGBB` into a color for [image].
img.Color _color(img.Image image, String hex) {
  var s = hex.startsWith('#') ? hex.substring(1) : hex;
  if (s.length == 6) s = 'FF$s';
  final v = int.tryParse(s, radix: 16);
  if (s.length != 8 || v == null) {
    throw ToolException(
        "Invalid color '$hex' — use hex like #FF0000 or #80FF0000.");
  }
  return img.ColorRgba8(
      (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff, (v >> 24) & 0xff);
}
