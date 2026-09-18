/// Image format conversions and generators (gif/tiff/psd/svg/eps/pdf/avif,
/// text/chart renders). Pure transforms live in `image_codecs.dart` and run in
/// isolates; AVIF uses `flutter_avif` (rav1e FFI); SVG rasterization and font
/// rendering need `dart:ui` and stay on the root isolate.
/// The single registration list for this block lives in
/// [buildImageConvertTools].
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_avif/flutter_avif.dart' as avif;
import 'package:flutter_svg/flutter_svg.dart';

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/isolate_runner.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/image_engine.dart';
import 'package:anvil/tools/image/image_codecs.dart' as codecs;

// ── Helpers ──────────────────────────────────────────────────────────────────

const _mimeByExt = {
  'png': 'image/png',
  'apng': 'image/apng',
  'jpg': 'image/jpeg',
  'gif': 'image/gif',
  'tiff': 'image/tiff',
  'svg': 'image/svg+xml',
  'eps': 'application/postscript',
  'pdf': 'application/pdf',
  'ai': 'application/pdf',
  'avif': 'image/avif',
};

String _mime(String ext) => _mimeByExt[ext] ?? 'application/octet-stream';

String _outName(String input, String ext) {
  final dot = input.lastIndexOf('.');
  final base = dot <= 0 ? input : input.substring(0, dot);
  return '$base.$ext';
}

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  final e = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return e == 'jpeg' ? 'jpg' : (e == 'tif' ? 'tiff' : e);
}

int _intParam(Map<String, dynamic> p, String key, int fallback) =>
    switch (p[key]) { final int v => v, _ => fallback };

String _textParam(Map<String, dynamic> p, String key, String fallback) =>
    switch (p[key]) {
      final String v when v.isNotEmpty => v,
      _ => fallback,
    };

Future<Uint8List> _readBytes(InputFile f) async =>
    await getIt<FileService>().readBytes(f.path) as Uint8List;

/// Injectable AVIF encoder seam — flutter_avif is FFI and cannot run in host
/// tests; tests swap this for a fake. Production default set at registration.
typedef AvifEncode = Future<Uint8List> Function(Uint8List src);

Future<Uint8List> _encodeAvif(Uint8List src) =>
    avif.encodeAvif(src, maxQuantizer: 40, minQuantizer: 20);

// ── Generic tool shapes ──────────────────────────────────────────────────────

/// File in → bytes out, where the transform is a pure function executed on a
/// background isolate.
class _PureConvert extends BaseToolModule {
  _PureConvert(this.meta, this._outExt, this._fn);
  @override
  final ToolMeta meta;
  final String _outExt;

  /// (src bytes, normalized src extension, tool params) → output bytes.
  final Future<Uint8List> Function(
      Uint8List src, String srcExt, Map<String, dynamic> params) _fn;

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading file…');
    final f = input.files.single;
    final src = await _readBytes(f);
    final srcExt = _ext(f.name);
    yield const ToolRunning(fraction: 0.3, message: 'Converting…');
    final out = await _fn(src, srcExt, input.params);
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(f.name, _outExt);
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _mime(_outExt))],
    ));
  }
}

/// No input file → rendered image out (text/quote generators).
class _Generator extends BaseToolModule {
  _Generator(this.meta, this._fn);
  @override
  final ToolMeta meta;
  final Future<Uint8List> Function(Map<String, dynamic> params) _fn;

  @override
  EngineKind get engine => EngineKind.dartlib;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Rendering…');
    final out = await _fn(input.params);
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    const name = 'generated.png';
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _mime('png'))],
    ));
  }
}

// ── dart:ui-backed renders (root isolate) ───────────────────────────────────

/// Rasterizes an SVG to PNG via flutter_svg at its intrinsic size (or a
/// caller-chosen width).
Future<Uint8List> _svgToPng(Uint8List src, int width) async {
  final PictureInfo info;
  try {
    info = await vg.loadPicture(
        SvgBytesLoader(src), null); // parses + resolves the picture
  } catch (_) {
    throw const ToolException('Could not read the SVG file.');
  }
  try {
    final srcW = info.size.width;
    final srcH = info.size.height;
    final scale = width > 0 && srcW > 0 ? width / srcW : 1.0;
    final outW = (srcW * scale).round().clamp(1, 16384);
    final outH = (srcH * scale).round().clamp(1, 16384);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(scale.toDouble());
    canvas.drawPicture(info.picture);
    final image = await recorder.endRecording().toImage(outW, outH);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const ToolException('Could not rasterize the SVG.');
    }
    return data.buffer.asUint8List();
  } finally {
    info.picture.dispose();
  }
}

/// Renders a specimen sheet for an uploaded .ttf/.otf font.
Future<Uint8List> _fontSpecimen(Uint8List fontBytes) async {
  const family = 'anvil-font-preview';
  try {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(fontBytes.buffer)));
    await loader.load();
  } catch (_) {
    throw const ToolException('Could not read the font file.');
  }
  const sample = 'AaBbCcDdEeFfGg 0123456789\n'
      'The quick brown fox jumps over the lazy dog.';
  const sizes = [16.0, 24.0, 36.0, 56.0];
  const pad = 32.0;
  final painters = [
    for (final s in sizes)
      TextPainter(
        text: TextSpan(
          text: sample,
          style: TextStyle(
              fontFamily: family, fontSize: s, color: const Color(0xFF111111)),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 1200),
  ];
  final width = pad * 2 +
      painters.fold(0.0, (m, p) => p.width > m ? p.width : m);
  final height = pad * 2 +
      painters.fold(0.0, (m, p) => m + p.height + pad);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width, height),
      ui.Paint()..color = const Color(0xFFFFFFFF));
  var y = pad;
  for (final p in painters) {
    p.paint(canvas, ui.Offset(pad, y));
    y += p.height + pad;
  }
  final image =
      await recorder.endRecording().toImage(width.ceil(), height.ceil());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw const ToolException('Could not render the font preview.');
  }
  return data.buffer.asUint8List();
}

// ── Registration ─────────────────────────────────────────────────────────────

ToolMeta _meta(
  String id,
  String label,
  IconData icon,
  String description,
  List<String> accepts, {
  List<ToolParam> params = const [],
  bool requiresInput = true,
}) => ToolMeta(
  id: id,
  category: ToolCategory.image,
  label: label,
  icon: icon,
  description: description,
  tinywowSlug: id,
  acceptedExtensions: accepts,
  params: params,
  requiresInput: requiresInput,
);

/// Pure-Dart `<from>-to-<to>` transcode tool.
_PureConvert _transcode(String from, String to,
        {String? outFormat, String? label, String? description}) =>
    _PureConvert(
      _meta(
        '$from-to-$to',
        label ?? '${from.toUpperCase()} to ${to.toUpperCase()}',
        Icons.image,
        description ?? 'Convert a .$from image into a .$to image.',
        [if (from == 'jpg') 'jpeg', if (from == 'tiff') 'tif', from],
      ),
      to,
      (src, srcExt, _) =>
          runOffThread(() => codecs.transcode(src, srcExt, outFormat ?? to)),
    );

/// Raster → SVG wrapper tool (embeds the bitmap in a standalone SVG).
_PureConvert _toSvg(String from) => _PureConvert(
      _meta(
        '$from-to-svg',
        '${from.toUpperCase()} to SVG',
        Icons.polyline,
        'Wrap a .$from image in a standalone SVG file (embeds the bitmap).',
        [if (from == 'jpg') 'jpeg', if (from == 'tiff') 'tif', from],
      ),
      'svg',
      (src, srcExt, _) => runOffThread(
          () => Uint8List.fromList(codecs.rasterToSvg(src, srcExt).codeUnits)),
    );

/// Still image → AVIF tool via the injected [AvifEncode] seam.
_PureConvert _toAvif(String from, AvifEncode encode,
        {String? description}) =>
    _PureConvert(
      _meta(
        '$from-to-avif',
        '${from.toUpperCase()} to AVIF',
        Icons.image,
        description ??
            'Convert a .$from image into an AVIF image (animation kept for '
                'animated sources).',
        [if (from == 'jpg') 'jpeg', from],
      ),
      'avif',
      (src, _, _) => encode(src),
    );

/// Every image conversion/generation tool. The single registration list for
/// this block. [avifEncode] is a test seam; production uses flutter_avif.
List<ToolModule> buildImageConvertTools({AvifEncode avifEncode = _encodeAvif}) => [
  _PureConvert(
    _meta('chart-maker', 'Chart Maker', Icons.bar_chart,
        'Draw a bar chart from a CSV file (label,value per row).', ['csv'],
        params: const [
          ToolParam(key: 'width', label: 'Width (px)', defaultValue: 1200),
          ToolParam(key: 'height', label: 'Height (px)', defaultValue: 800),
        ]),
    'png',
    (src, _, p) => runOffThread(() => codecs.renderBarChart(
        String.fromCharCodes(src),
        width: _intParam(p, 'width', 1200),
        height: _intParam(p, 'height', 800))),
  ),
  _PureConvert(
    _meta('font-to-png', 'Font to PNG', Icons.font_download,
        'Render a preview specimen sheet of a .ttf/.otf font.', ['ttf', 'otf']),
    'png',
    (src, _, _) => _fontSpecimen(src),
  ),
  _transcode('gif', 'apng',
      label: 'GIF to APNG',
      description: 'Convert an animated GIF into an animated PNG (APNG).'),
  _toAvif('gif', avifEncode,
      description:
          'Convert a GIF (animation kept) into an AVIF image.'),
  _transcode('gif', 'jpg',
      description: 'Convert a GIF\'s first frame into a JPG image.'),
  _transcode('gif', 'png',
      description: 'Convert a GIF\'s first frame into a PNG image.'),
  _PureConvert(
    _meta('heic-to-avif', 'HEIC to AVIF', Icons.image,
        'Convert a HEIC/HEIF photo into an AVIF image.', ['heic', 'heif']),
    'avif',
    (src, _, _) async {
      // HEIC decode is native-only; normalize to PNG first, then encode.
      final png = await getIt<ImageEngine>()
          .convert(src, format: 'png', quality: 100);
      return avifEncode(png);
    },
  ),
  _toAvif('jpg', avifEncode),
  _transcode('jpg', 'gif'),
  _toSvg('jpg'),
  _transcode('jpg', 'tiff'),
  _toAvif('png', avifEncode),
  _PureConvert(
    _meta('png-to-eps', 'PNG to EPS', Icons.polyline,
        'Convert a PNG image into an EPS (PostScript) file.', ['png']),
    'eps',
    (src, srcExt, _) => runOffThread(() => codecs.rasterToEps(src, srcExt)),
  ),
  _transcode('png', 'gif'),
  _toSvg('png'),
  _transcode('png', 'tiff'),
  _PureConvert(
    _meta('psd-to-ai', 'PSD to AI', Icons.brush,
        'Convert a Photoshop file into an Illustrator-compatible .ai '
        '(PDF-based) file.', ['psd']),
    'ai',
    (src, _, _) => runOffThread(() => codecs.rasterToPdf(src, 'psd')),
  ),
  _transcode('psd', 'jpg',
      description: 'Convert a Photoshop file into a JPG image.'),
  _PureConvert(
    _meta('psd-to-pdf', 'PSD to PDF', Icons.picture_as_pdf,
        'Convert a Photoshop file into a single-page PDF.', ['psd']),
    'pdf',
    (src, _, _) => runOffThread(() => codecs.rasterToPdf(src, 'psd')),
  ),
  _transcode('psd', 'png',
      description: 'Convert a Photoshop file into a PNG image.'),
  _toSvg('psd'),
  _PureConvert(
    _meta('svg-to-png', 'SVG to PNG', Icons.image,
        'Rasterize an SVG into a PNG image.', ['svg'],
        params: const [
          ToolParam(
              key: 'width', label: 'Width (px, 0 = intrinsic)'),
        ]),
    'png',
    (src, _, p) => _svgToPng(src, _intParam(p, 'width', 0)),
  ),
  _Generator(
    _meta('text-image-generator', 'Text Image Generator', Icons.format_quote,
        'Generate a shareable quote card from text.', const [],
        params: const [
          ToolParam(
              key: 'text',
              label: 'Text',
              type: ToolParamType.text,
              defaultText: 'Hello from Anvil'),
          ToolParam(
              key: 'background',
              label: 'Background (hex)',
              type: ToolParamType.text,
              defaultText: '#FF1F2937'),
          ToolParam(
              key: 'color',
              label: 'Text color (hex)',
              type: ToolParamType.text,
              defaultText: '#FFFFFFFF'),
        ],
        requiresInput: false),
    (p) => runOffThread(() => codecs.renderQuoteCard(
          _textParam(p, 'text', 'Hello from Anvil'),
          background: _textParam(p, 'background', '#FF1F2937'),
          color: _textParam(p, 'color', '#FFFFFFFF'),
        )),
  ),
  _Generator(
    _meta('text-to-image', 'Text to Image', Icons.text_fields,
        'Render plain text onto an image.', const [],
        params: const [
          ToolParam(
              key: 'text',
              label: 'Text',
              type: ToolParamType.text,
              defaultText: 'Hello'),
          ToolParam(key: 'fontSize', label: 'Font size', defaultValue: 32),
          ToolParam(
              key: 'color',
              label: 'Text color (hex)',
              type: ToolParamType.text,
              defaultText: '#FF000000'),
          ToolParam(
              key: 'background',
              label: 'Background (hex)',
              type: ToolParamType.text,
              defaultText: '#FFFFFFFF'),
        ],
        requiresInput: false),
    (p) => runOffThread(() => codecs.renderTextPng(
          _textParam(p, 'text', 'Hello'),
          fontSize: _intParam(p, 'fontSize', 32),
          color: _textParam(p, 'color', '#FF000000'),
          background: _textParam(p, 'background', '#FFFFFFFF'),
        )),
  ),
  _transcode('tiff', 'jpg'),
  _transcode('tiff', 'png'),
  _toSvg('tiff'),
  _toAvif('webp', avifEncode),
  _transcode('webp', 'gif',
      description:
          'Convert a WebP (animation kept) into a GIF image.'),
];
