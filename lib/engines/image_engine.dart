import 'package:flutter/services.dart';

import 'package:anvil/core/tool_io.dart';

/// Bridges to the Kotlin `anvil/image` platform channel (Android Bitmap ops) —
/// the single place the channel is touched, so a future engine swap is one
/// file. Pure-Dart fallbacks for exotic codecs live in the tools layer, not
/// here.
///
/// The Kotlin side runs each op on a background executor and returns encoded
/// bytes, so callers do NOT wrap these in `runOffThread`.
///
/// Only the generic methods ([transform], [transformToMany], [transformMany],
/// [query]) touch the channel; the typed wrappers below delegate to them.
class ImageEngine {
  static const MethodChannel _channel = MethodChannel('anvil/image');

  /// Maps channel-layer errors onto user-presentable [ToolException]s.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (e) {
      throw ToolException(e.message ?? 'Image processing failed.');
    } on MissingPluginException {
      throw const ToolException(
          'Image processing is not available on this platform.');
    }
  }

  /// Runs one named bitmap op and returns the re-encoded image bytes.
  /// Known ops are implemented in `ImageChannel.kt`; an unknown op or a
  /// decode failure surfaces as a [ToolException].
  Future<Uint8List> transform(
    String op,
    Uint8List src,
    Map<String, Object?> args,
  ) => _guard(() async {
        final out = await _channel.invokeMethod<Uint8List>(op, {
          'src': src,
          ...args,
        });
        if (out == null || out.isEmpty) {
          throw const ToolException('Image processing produced no output.');
        }
        return out;
      });

  /// Runs one named bitmap op that produces several images (e.g. split).
  Future<List<Uint8List>> transformToMany(
    String op,
    Uint8List src,
    Map<String, Object?> args,
  ) => _guard(() async {
        final out = await _channel.invokeListMethod<Uint8List>(op, {
          'src': src,
          ...args,
        });
        if (out == null || out.isEmpty) {
          throw const ToolException('Image processing produced no output.');
        }
        return out;
      });

  /// Runs one named bitmap op over several input images producing one image
  /// (e.g. grid collage).
  Future<Uint8List> transformMany(
    String op,
    List<Uint8List> images,
    Map<String, Object?> args,
  ) => _guard(() async {
        final out = await _channel.invokeMethod<Uint8List>(op, {
          'images': images,
          ...args,
        });
        if (out == null || out.isEmpty) {
          throw const ToolException('Image processing produced no output.');
        }
        return out;
      });

  /// Runs one named query op (e.g. EXIF metadata read) returning a map.
  Future<Map<String, Object?>> query(
    String op,
    Uint8List src,
    Map<String, Object?> args,
  ) => _guard(() async {
        final out = await _channel.invokeMapMethod<String, Object?>(op, {
          'src': src,
          ...args,
        });
        return out ?? const {};
      });

  // ── Typed wrappers ─────────────────────────────────────────────────────────

  /// Decodes ANY Android-supported input (incl. HEIC on API 28+) and
  /// re-encodes as [format] ('png' | 'jpg' | 'webp'). Cross-agent contract.
  Future<Uint8List> convert(
    Uint8List src, {
    required String format,
    int quality = 90,
  }) => transform('convert', src, {'format': format, 'quality': quality});

  /// Scales to [width]×[height]; pass 0 for one dimension to keep aspect.
  Future<Uint8List> resize(
    Uint8List src, {
    required int width,
    required int height,
    String format = 'png',
    int quality = 90,
  }) => transform('resize', src, {
        'width': width,
        'height': height,
        'format': format,
        'quality': quality,
      });

  Future<Uint8List> crop(
    Uint8List src, {
    required int x,
    required int y,
    required int width,
    required int height,
    String format = 'png',
    int quality = 90,
  }) => transform('crop', src, {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'format': format,
        'quality': quality,
      });

  /// Center-crops to the largest circle; always a transparent PNG.
  Future<Uint8List> cropCircle(Uint8List src) =>
      transform('cropCircle', src, const {});

  Future<Uint8List> flip(
    Uint8List src, {
    required bool horizontal,
    String format = 'png',
    int quality = 90,
  }) => transform('flip', src, {
        'horizontal': horizontal ? 1 : 0,
        'format': format,
        'quality': quality,
      });

  Future<Uint8List> grayscale(
    Uint8List src, {
    String format = 'png',
    int quality = 90,
  }) => transform('grayscale', src, {'format': format, 'quality': quality});

  /// [color] is hex like `#FF0000` or `#80FF0000` (AARRGGBB).
  Future<Uint8List> border(
    Uint8List src, {
    required int sizePx,
    required String color,
    String format = 'png',
    int quality = 90,
  }) => transform('border', src, {
        'sizePx': sizePx,
        'color': color,
        'format': format,
        'quality': quality,
      });

  Future<Uint8List> pixelate(
    Uint8List src, {
    required int blockSize,
    String format = 'png',
    int quality = 90,
  }) => transform('pixelate', src, {
        'blockSize': blockSize,
        'format': format,
        'quality': quality,
      });

  /// Lossy re-encode; [format] must be 'jpg' or 'webp'.
  Future<Uint8List> compress(
    Uint8List src, {
    required int quality,
    String format = 'jpg',
  }) => transform('compress', src, {'quality': quality, 'format': format});

  /// Composites [layers] onto [base] in order. Each layer map carries the
  /// overlay bytes plus its placement in BASE-IMAGE PIXELS:
  ///   {'overlay': Uint8List, 'x': int, 'y': int, 'width': int, 'height': int,
  ///    'rotation': double}   // width/height <= 0 => overlay's native size;
  ///                          // rotation in degrees clockwise about the layer center.
  Future<Uint8List> composite(
    Uint8List base,
    List<Map<String, Object?>> layers, {
    String format = 'png',
    int quality = 100,
  }) => _guard(() async {
        final out = await _channel.invokeMethod<Uint8List>('composite', {
          'src': base,
          'layers': layers,
          'format': format,
          'quality': quality,
        });
        if (out == null || out.isEmpty) {
          throw const ToolException('Image processing produced no output.');
        }
        return out;
      });

  /// Lays [images] out on a grid with [columns] columns (<= 0 means one row);
  /// transparent PNG output.
  Future<Uint8List> grid(List<Uint8List> images, {required int columns}) =>
      transformMany('grid', images, {'columns': columns});

  /// Cuts [src] into a rows×cols grid of PNG tiles, row-major.
  Future<List<Uint8List>> split(
    Uint8List src, {
    required int rows,
    required int cols,
  }) => transformToMany('split', src, {'rows': rows, 'cols': cols});

  /// Reads EXIF metadata (plus pixel dimensions) as a flat map.
  Future<Map<String, Object?>> metadataRead(Uint8List src) =>
      query('metadataRead', src, const {});

  /// Re-encodes without any EXIF metadata.
  Future<Uint8List> metadataStrip(
    Uint8List src, {
    String format = 'png',
    int quality = 90,
  }) =>
      transform('metadataStrip', src, {'format': format, 'quality': quality});
}
