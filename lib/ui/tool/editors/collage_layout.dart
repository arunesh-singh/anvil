/// The collage/combine draft (design `tools-workspace.html`, frame "Collage
/// maker"): ordered images, a layout, gap and background — and the output
/// size `ImageChannel.grid` will produce, stated before Run.
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:anvil/core/tool_io.dart';

/// The four layout tiles → the grid tool's `columns`.
enum CollageLayout {
  // Short enough for a quarter-width tile on a phone.
  oneRow('Row', 0),
  twoColumns('2 cols', 2),
  threeColumns('3 cols', 3),
  oneColumn('Column', 1);

  const CollageLayout(this.label, this.columns);

  final String label;
  final int columns;
}

/// Output pixel size of `ImageChannel.grid`: cells are the largest image's
/// width × height, [gap] separates cells and frames the outside.
Size collageOutputSize(List<Size> images, int columns, int gap) {
  final n = images.length;
  if (n == 0) return Size.zero;
  var cellW = 0.0;
  var cellH = 0.0;
  for (final s in images) {
    if (s.width > cellW) cellW = s.width;
    if (s.height > cellH) cellH = s.height;
  }
  final cols = columns <= 0 ? n : (columns < n ? columns : n);
  final rows = (n + cols - 1) ~/ cols;
  return Size(cellW * cols + gap * (cols + 1), cellH * rows + gap * (rows + 1));
}

/// One picked image with its decoded size and bytes for the preview.
class CollageItem {
  const CollageItem({
    required this.file,
    required this.size,
    required this.bytes,
  });

  final InputFile file;
  final Size size;
  final Uint8List bytes;
}

/// One undoable collage state.
class CollageDraft {
  const CollageDraft({
    this.items = const [],
    required this.layout,
    this.gap = 0,
    required this.background,
  });

  final List<CollageItem> items;
  final CollageLayout layout;
  final int gap;

  /// `#AARRGGBB`.
  final String background;

  CollageDraft copyWith({
    List<CollageItem>? items,
    CollageLayout? layout,
    int? gap,
    String? background,
  }) => CollageDraft(
    items: items ?? this.items,
    layout: layout ?? this.layout,
    gap: gap ?? this.gap,
    background: background ?? this.background,
  );

  CollageDraft add(List<CollageItem> more) =>
      copyWith(items: [...items, ...more]);

  CollageDraft remove(int index) =>
      copyWith(items: [...items]..removeAt(index));

  /// Moves [from] so it lands at [to] (an index in the list without it).
  CollageDraft reorder(int from, int to) {
    final next = [...items];
    next.insert(to, next.removeAt(from));
    return copyWith(items: next);
  }

  bool get canRun => items.length >= 2;

  Size get outputSize =>
      collageOutputSize([for (final i in items) i.size], layout.columns, gap);

  ToolInput get input => ToolInput(
    files: [for (final i in items) i.file],
    params: {'columns': layout.columns, 'gap': gap, 'background': background},
  );
}
