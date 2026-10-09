/// Full-screen pinch-zoom view of one rendered page, opened by long-pressing a
/// thumbnail in the PDF workspace grid.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Shows [png] in a black zoomable dialog, turned by [quarterTurns].
Future<void> showPageZoom(
  BuildContext context,
  Uint8List png, {
  int quarterTurns = 0,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Center(
              child: RotatedBox(
                quarterTurns: quarterTurns,
                child: Image.memory(png),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        ],
      ),
    ),
  );
}
