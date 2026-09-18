/// Deterministic image ops backed by the native `anvil/image` channel
/// (resize/crop/compress/flip/grayscale/border/pixelate/format-convert/EXIF).
/// The single registration list for this block lives in [buildImageNativeTools].
library;

import 'dart:typed_data';

import 'package:flutter/material.dart' show IconData, Icons;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/core/tool_module.dart';
import 'package:anvil/engines/image_engine.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

const _mimeByExt = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'webp': 'image/webp',
};

String _mime(String ext) => _mimeByExt[ext] ?? 'application/octet-stream';

String _outName(String input, String ext, {int? index}) {
  final dot = input.lastIndexOf('.');
  final base = dot <= 0 ? input : input.substring(0, dot);
  return index == null ? '$base.$ext' : '${base}_${index + 1}.$ext';
}

/// Lowercase extension of [name], normalized so 'jpeg' reads as 'jpg'.
String _ext(String name) {
  final dot = name.lastIndexOf('.');
  final e = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return e == 'jpeg' ? 'jpg' : e;
}

/// Resolves every declared [ToolParam] against [input], falling back to the
/// param's default so tools never see a missing key.
Map<String, dynamic> _params(ToolModule tool, ToolInput input) => {
      for (final p in tool.meta.params)
        p.key: switch (p.type) {
          ToolParamType.integer => switch (input.params[p.key]) {
              final int v => v,
              _ => p.defaultValue,
            },
          ToolParamType.text => switch (input.params[p.key]) {
              final String v when v.isNotEmpty => v,
              _ => p.defaultText,
            },
        },
    };

Future<Uint8List> _readBytes(InputFile f) async =>
    await getIt<FileService>().readBytes(f.path) as Uint8List;

// ── Output-extension policies ────────────────────────────────────────────────

String _same(String inExt) => inExt;
String _png(String _) => 'png';
String _compressExt(String inExt) => inExt == 'webp' ? 'webp' : 'jpg';

/// Metadata-strip re-encodes, so HEIC inputs come back as JPG.
String _stripExt(String inExt) =>
    (inExt == 'heic' || inExt == 'heif') ? 'jpg' : inExt;

// ── Generic tool shapes ──────────────────────────────────────────────────────

/// Single image in → single image out (resize, crop, converts, …).
class _SingleImage extends BaseToolModule {
  _SingleImage(this.meta, this._fn, this._outExt);
  @override
  final ToolMeta meta;
  final Future<Uint8List> Function(
      ImageEngine e, Uint8List src, String outExt, Map<String, dynamic> p) _fn;
  final String Function(String inExt) _outExt;

  @override
  EngineKind get engine => EngineKind.image;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading image…');
    final f = input.files.single;
    final src = await _readBytes(f);
    final ext = _outExt(_ext(f.name));
    yield const ToolRunning(fraction: 0.3, message: 'Processing…');
    final out = await _fn(getIt<ImageEngine>(), src, ext, _params(this, input));
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(f.name, ext);
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _mime(ext))],
    ));
  }
}

/// Several images in → one image out (overlay, collage/combine grid).
class _MultiImage extends BaseToolModule {
  _MultiImage(this.meta, this._fn);
  @override
  final ToolMeta meta;
  final Future<Uint8List> Function(
      ImageEngine e, List<Uint8List> images, Map<String, dynamic> p) _fn;

  @override
  EngineKind get engine => EngineKind.image;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    if (input.files.length < 2) {
      throw const ToolException('Select at least two images.');
    }
    yield const ToolRunning(message: 'Reading images…');
    final images = [for (final f in input.files) await _readBytes(f)];
    yield const ToolRunning(fraction: 0.3, message: 'Processing…');
    final out = await _fn(getIt<ImageEngine>(), images, _params(this, input));
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(input.files.first.name, 'png');
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _mime('png'))],
    ));
  }
}

/// Base image (first file) + N overlays composited via the editor's geometry.
/// Reads `input.params['layers']` — a List of maps, one per overlay file:
///   {'fileIndex': int, 'x': int, 'y': int, 'width': int, 'height': int,
///    'rotation': double}. Absent/empty => each overlay stacked at (0,0)
///    at native size (fallback for non-editor / agent callers).
class _CompositeImage extends BaseToolModule {
  _CompositeImage(this.meta);
  @override
  final ToolMeta meta;
  @override
  EngineKind get engine => EngineKind.image;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    if (input.files.length < 2) {
      throw const ToolException('Select a base image and at least one overlay.');
    }
    yield const ToolRunning(message: 'Reading images…');
    final bytes = [for (final f in input.files) await _readBytes(f)];
    final specs = (input.params['layers'] as List?) ?? const [];
    final layers = <Map<String, Object?>>[];
    if (specs.isEmpty) {
      for (var i = 1; i < bytes.length; i++) {
        layers.add({'overlay': bytes[i], 'x': 0, 'y': 0,
            'width': 0, 'height': 0, 'rotation': 0.0});
      }
    } else {
      for (final s in specs.cast<Map>()) {
        final idx = s['fileIndex'] as int;
        layers.add({
          'overlay': bytes[idx],
          'x': s['x'] as int, 'y': s['y'] as int,
          'width': s['width'] as int, 'height': s['height'] as int,
          'rotation': (s['rotation'] as num).toDouble(),
        });
      }
    }
    yield const ToolRunning(fraction: 0.3, message: 'Compositing…');
    final out = await getIt<ImageEngine>().composite(bytes.first, layers);
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(input.files.first.name, 'png');
    final file = await getIt<FileService>().writeBytes(name, out);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _mime('png'))],
    ));
  }
}

/// Single image in → many images out (split into tiles).
class _SplitImage extends BaseToolModule {
  _SplitImage(this.meta);
  @override
  final ToolMeta meta;

  @override
  EngineKind get engine => EngineKind.image;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading image…');
    final f = input.files.single;
    final src = await _readBytes(f);
    final p = _params(this, input);
    yield const ToolRunning(fraction: 0.3, message: 'Splitting…');
    final parts = await getIt<ImageEngine>()
        .split(src, rows: p['rows'] as int, cols: p['cols'] as int);
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final files = <OutputFile>[];
    for (var i = 0; i < parts.length; i++) {
      final name = _outName(f.name, 'png', index: i);
      final file = await getIt<FileService>().writeBytes(name, parts[i]);
      files.add(
        OutputFile(path: file.path, name: name, mimeType: _mime('png')),
      );
    }
    yield ToolSucceeded(ToolResult(files: files));
  }
}

/// EXIF viewer + remover: surfaces the metadata as text AND writes a stripped
/// copy of the image.
class _Metadata extends BaseToolModule {
  _Metadata(this.meta);
  @override
  final ToolMeta meta;

  @override
  EngineKind get engine => EngineKind.image;

  @override
  Stream<ToolProgress> run(ToolInput input) async* {
    yield const ToolRunning(message: 'Reading image…');
    final f = input.files.single;
    final src = await _readBytes(f);
    final engine = getIt<ImageEngine>();
    yield const ToolRunning(fraction: 0.3, message: 'Reading metadata…');
    final meta = await engine.metadataRead(src);
    final text = meta.isEmpty
        ? 'No metadata found.'
        : ([for (final k in meta.keys.toList()..sort()) '$k: ${meta[k]}']
            .join('\n'));
    yield const ToolRunning(fraction: 0.6, message: 'Removing metadata…');
    final ext = _stripExt(_ext(f.name));
    final stripped = await engine.metadataStrip(src, format: ext);
    yield const ToolRunning(fraction: 0.85, message: 'Saving…');
    final name = _outName(f.name, ext);
    final file = await getIt<FileService>().writeBytes(name, stripped);
    yield ToolSucceeded(ToolResult(
      files: [OutputFile(path: file.path, name: name, mimeType: _mime(ext))],
      text: text,
    ));
  }
}

// ── Registration ─────────────────────────────────────────────────────────────

ToolMeta _meta(
  String id,
  String label,
  IconData icon,
  String description,
  List<String> accepts, {
  List<ToolParam> params = const [],
  bool acceptsMultiple = false,
}) => ToolMeta(
  id: id,
  category: ToolCategory.image,
  label: label,
  icon: icon,
  description: description,
  tinywowSlug: id,
  acceptedExtensions: accepts,
  params: params,
  acceptsMultiple: acceptsMultiple,
);

const _images = ['jpg', 'jpeg', 'png', 'webp'];
const _heic = ['heic', 'heif'];
const _jpg = ['jpg', 'jpeg'];

const _qualityParam =
    ToolParam(key: 'quality', label: 'Quality (0-100)', defaultValue: 90);

/// A single-image tool that just re-encodes to a fixed [format].
_SingleImage _convertTool(
  String id,
  String label,
  String description,
  List<String> accepts,
  String format, {
  bool lossy = false,
}) => _SingleImage(
  _meta(id, label, Icons.image, description, accepts,
      params: lossy ? const [_qualityParam] : const []),
  (e, src, ext, p) => e.convert(src,
      format: format, quality: lossy ? p['quality'] as int : 100),
  (_) => format,
);

/// Every native-bitmap image tool. The single registration list for this block.
List<ToolModule> buildImageNativeTools() => [
  _CompositeImage(
    _meta('add-images', 'Add Image to Image', Icons.add_photo_alternate,
        'Overlay images on top of a base image at a chosen position.', _images,
        params: const [], acceptsMultiple: true),
  ),
  _SingleImage(
    _meta('border', 'Add Border', Icons.border_outer,
        'Add a solid color border around an image.', _images,
        params: const [
          ToolParam(key: 'sizePx', label: 'Border size (px)', defaultValue: 16),
          ToolParam(
            key: 'color',
            label: 'Color (hex, e.g. #FF0000)',
            type: ToolParamType.text,
            defaultText: '#FF000000',
          ),
        ]),
    (e, src, ext, p) => e.border(src,
        sizePx: p['sizePx'] as int, color: p['color'] as String, format: ext),
    _same,
  ),
  _MultiImage(
    _meta('collage-maker', 'Collage Maker', Icons.dashboard,
        'Arrange several images into a grid collage.', _images,
        params: const [
          ToolParam(key: 'columns', label: 'Columns', defaultValue: 2),
        ],
        acceptsMultiple: true),
    (e, images, p) => e.grid(images, columns: p['columns'] as int),
  ),
  _MultiImage(
    _meta('combine-maker', 'Combine Images', Icons.view_week,
        'Combine images side by side into one image (0 columns = one row).',
        _images,
        params: const [
          ToolParam(key: 'columns', label: 'Columns (0 = one row)'),
        ],
        acceptsMultiple: true),
    (e, images, p) => e.grid(images, columns: p['columns'] as int),
  ),
  _SingleImage(
    _meta('compress', 'Compress Image', Icons.compress,
        'Shrink an image\'s file size with lossy re-encoding.', _images,
        params: const [
          ToolParam(key: 'quality', label: 'Quality (0-100)', defaultValue: 75),
        ]),
    (e, src, ext, p) =>
        e.compress(src, quality: p['quality'] as int, format: ext),
    _compressExt,
  ),
  _SingleImage(
    _meta('crop', 'Crop Image', Icons.crop,
        'Crop an image to a rectangle.', _images,
        params: const [
          ToolParam(key: 'x', label: 'Left (px)'),
          ToolParam(key: 'y', label: 'Top (px)'),
          ToolParam(key: 'width', label: 'Width (px)', defaultValue: 512),
          ToolParam(key: 'height', label: 'Height (px)', defaultValue: 512),
        ]),
    (e, src, ext, p) => e.crop(src,
        x: p['x'] as int,
        y: p['y'] as int,
        width: p['width'] as int,
        height: p['height'] as int,
        format: ext),
    _same,
  ),
  _SingleImage(
    _meta('crop-circle', 'Circle Crop', Icons.circle_outlined,
        'Crop an image into a circle with a transparent background.', _images),
    (e, src, ext, p) => e.cropCircle(src),
    _png,
  ),
  _SingleImage(
    _meta('flip', 'Flip Image', Icons.flip,
        'Mirror an image horizontally or vertically.', _images,
        params: const [
          ToolParam(
            key: 'horizontal',
            label: 'Horizontal? (1 = yes, 0 = vertical)',
            defaultValue: 1,
          ),
        ]),
    (e, src, ext, p) => e.flip(src,
        horizontal: (p['horizontal'] as int) != 0, format: ext),
    _same,
  ),
  _SingleImage(
    _meta('grayscale', 'Grayscale Image', Icons.filter_b_and_w,
        'Convert an image to black and white.', _images),
    (e, src, ext, p) => e.grayscale(src, format: ext),
    _same,
  ),
  _convertTool('heic-to-jpg', 'HEIC to JPG',
      'Convert a HEIC/HEIF photo into a JPG image.', _heic, 'jpg',
      lossy: true),
  _convertTool('heic-to-png', 'HEIC to PNG',
      'Convert a HEIC/HEIF photo into a PNG image.', _heic, 'png'),
  _convertTool('jpg-to-png', 'JPG to PNG',
      'Convert a JPG image into a PNG image.', _jpg, 'png'),
  _convertTool('jpg-to-webp', 'JPG to WebP',
      'Convert a JPG image into a WebP image.', _jpg, 'webp',
      lossy: true),
  _Metadata(
    _meta(
        'metadata',
        'Image Metadata',
        Icons.info_outline,
        'View an image\'s EXIF metadata and save a copy with it removed.',
        [..._images, ..._heic]),
  ),
  _SingleImage(
    _meta('pixelate', 'Pixelate Image', Icons.blur_on,
        'Pixelate an image with a chosen block size.', _images,
        params: const [
          ToolParam(key: 'blockSize', label: 'Block size (px)', defaultValue: 8),
        ]),
    (e, src, ext, p) =>
        e.pixelate(src, blockSize: p['blockSize'] as int, format: ext),
    _same,
  ),
  _convertTool('png-to-jpg', 'PNG to JPG',
      'Convert a PNG image into a JPG image.', ['png'], 'jpg',
      lossy: true),
  _convertTool('png-to-webp', 'PNG to WebP',
      'Convert a PNG image into a WebP image.', ['png'], 'webp',
      lossy: true),
  _SingleImage(
    _meta('resize', 'Resize Image', Icons.photo_size_select_large,
        'Resize an image (set one dimension to 0 to keep the aspect ratio).',
        _images,
        params: const [
          ToolParam(key: 'width', label: 'Width (px, 0 = auto)',
              defaultValue: 1024),
          ToolParam(key: 'height', label: 'Height (px, 0 = auto)'),
        ]),
    (e, src, ext, p) => e.resize(src,
        width: p['width'] as int, height: p['height'] as int, format: ext),
    _same,
  ),
  _SplitImage(
    _meta('split', 'Split Image', Icons.grid_on,
        'Cut an image into a grid of tiles.', _images,
        params: const [
          ToolParam(key: 'rows', label: 'Rows', defaultValue: 2),
          ToolParam(key: 'cols', label: 'Columns', defaultValue: 2),
        ]),
  ),
  _convertTool('webp-to-jpg', 'WebP to JPG',
      'Convert a WebP image into a JPG image.', ['webp'], 'jpg',
      lossy: true),
  _convertTool('webp-to-png', 'WebP to PNG',
      'Convert a WebP image into a PNG image.', ['webp'], 'png'),
];
