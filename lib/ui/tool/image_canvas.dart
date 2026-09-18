import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Builds overlay content for [ImageCanvas], given the on-screen rectangle the
/// fitted image occupies and the image's intrinsic pixel size.
typedef CanvasBuilder = Widget Function(
    BuildContext context, Rect displayRect, Size imagePx);

/// Lays [imageBytes] out with `BoxFit.contain` inside its constraints and hands
/// the fitted rectangle to [builder] so overlays/handles align to pixels.
///
/// The intrinsic pixel size [imagePx] is decoded once by the caller (via
/// `ui.decodeImageFromList`) so the geometry math is exact:
/// `scale = imagePx.width / displayRect.width` converts canvas → pixels.
class ImageCanvas extends StatelessWidget {
  const ImageCanvas({
    super.key,
    required this.imageBytes,
    required this.imagePx,
    required this.builder,
    this.background,
  });

  final Uint8List imageBytes;
  final Size imagePx;
  final CanvasBuilder builder;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.maxWidth;
        final ch = constraints.maxHeight;
        final fit = (imagePx.width <= 0 || imagePx.height <= 0)
            ? 1.0
            : (cw / imagePx.width < ch / imagePx.height
                ? cw / imagePx.width
                : ch / imagePx.height);
        final displaySize = Size(imagePx.width * fit, imagePx.height * fit);
        final displayRect = Rect.fromCenter(
          center: Offset(cw / 2, ch / 2),
          width: displaySize.width,
          height: displaySize.height,
        );
        return Container(
          color: background,
          width: cw,
          height: ch,
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: displayRect,
                child: Image.memory(
                  imageBytes,
                  width: displaySize.width,
                  height: displaySize.height,
                  fit: BoxFit.fill,
                ),
              ),
              builder(context, displayRect, imagePx),
            ],
          ),
        );
      },
    );
  }
}
