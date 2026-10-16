/// Named split presets for what people actually post (design
/// `tools-workspace.html`, frame "Split into grid") and the tile maths of
/// `image/split`: row-major tiles, the last row/column absorbing the
/// remainder.
library;

/// A pill on the split screen. Labels read rows × columns.
enum SplitPreset {
  grid3x3('Grid 3×3', 3, 3, feed: true),
  grid2x3('Grid 2×3', 2, 3, feed: true),
  row1x3('Carousel 1×3', 1, 3),
  row1x2('Carousel 1×2', 1, 2),
  custom('Custom', 0, 0);

  const SplitPreset(this.label, this.rows, this.cols, {this.feed = false});

  final String label;
  final int rows;
  final int cols;

  /// A profile-grid preset: posted last tile first.
  final bool feed;
}

/// The tiles one split produces from a [width] × [height] image.
class SplitPlan {
  const SplitPlan({
    required this.width,
    required this.height,
    required this.rows,
    required this.cols,
  });

  final int width;
  final int height;
  final int rows;
  final int cols;

  int get files => rows * cols;

  /// Every tile but the last column/row.
  int get tileWidth => width ~/ cols;
  int get tileHeight => height ~/ rows;

  /// Whether the last column/row is larger than the rest.
  bool get uneven => width % cols != 0 || height % rows != 0;

  /// "Each tile 1008 × 1008 px · 9 files" (`~` when the edges differ).
  String get readout =>
      'Each tile ${uneven ? '~' : ''}$tileWidth × $tileHeight px · '
      '$files ${files == 1 ? 'file' : 'files'}';

  Map<String, Object> get params => {'rows': rows, 'cols': cols};
}
