/// The fully resolved export description the PDF workspace hands to the
/// `pdf/workspace` export module as JSON. Pure Dart (no Flutter) so the UI's
/// fold → plan mapping and the module's plan → engine calls are both
/// host-testable. All geometry is already in PDF points of the **unrotated**
/// page, origin bottom-left — the UI resolves fractions before export.
library;

/// One vector text run placed on a page.
class WorkspacePlanText {
  const WorkspacePlanText({
    required this.text,
    required this.family,
    required this.bold,
    required this.italic,
    required this.size,
    required this.x,
    required this.y,
    required this.color,
  });

  final String text;

  /// `'Helvetica' | 'Times' | 'Courier'`.
  final String family;
  final bool bold, italic;

  /// Points; (x, y) = text baseline-left, origin bottom-left.
  final double size, x, y;

  /// `'#RRGGBB'`.
  final String color;

  Map<String, dynamic> toJson() => {
    'text': text,
    'family': family,
    'bold': bold,
    'italic': italic,
    'size': size,
    'x': x,
    'y': y,
    'color': color,
  };

  factory WorkspacePlanText.fromJson(Map<String, dynamic> j) =>
      WorkspacePlanText(
        text: j['text'] as String,
        family: j['family'] as String,
        bold: j['bold'] as bool,
        italic: j['italic'] as bool,
        size: (j['size'] as num).toDouble(),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        color: j['color'] as String,
      );
}

/// One image (signature) stamped on a page.
class WorkspacePlanStamp {
  const WorkspacePlanStamp({
    required this.image,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Index into `ToolInput.files`.
  final int image;

  /// Points; (x, y) = bottom-left corner.
  final double x, y, width, height;

  Map<String, dynamic> toJson() => {
    'image': image,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory WorkspacePlanStamp.fromJson(Map<String, dynamic> j) =>
      WorkspacePlanStamp(
        image: j['image'] as int,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
      );
}

/// One output page: where it comes from and what happens to it.
class WorkspacePlanPage {
  const WorkspacePlanPage({
    required this.source,
    required this.page,
    this.rotate = 0,
    this.crop,
    this.texts = const [],
    this.stamps = const [],
  });

  /// Index into `ToolInput.files`; [page] is 0-based within that file.
  final int source, page;

  /// Clockwise delta: 0 | 90 | 180 | 270.
  final int rotate;

  /// Margins in points, or null for no crop.
  final ({double l, double t, double r, double b})? crop;
  final List<WorkspacePlanText> texts;
  final List<WorkspacePlanStamp> stamps;

  Map<String, dynamic> toJson() => {
    'source': source,
    'page': page,
    'rotate': rotate,
    'crop': crop == null
        ? null
        : {'l': crop!.l, 't': crop!.t, 'r': crop!.r, 'b': crop!.b},
    'texts': [for (final t in texts) t.toJson()],
    'stamps': [for (final s in stamps) s.toJson()],
  };

  factory WorkspacePlanPage.fromJson(Map<String, dynamic> j) {
    final c = j['crop'] as Map<String, dynamic>?;
    return WorkspacePlanPage(
      source: j['source'] as int,
      page: j['page'] as int,
      rotate: j['rotate'] as int,
      crop: c == null
          ? null
          : (
              l: (c['l'] as num).toDouble(),
              t: (c['t'] as num).toDouble(),
              r: (c['r'] as num).toDouble(),
              b: (c['b'] as num).toDouble(),
            ),
      texts: [
        for (final t in j['texts'] as List)
          WorkspacePlanText.fromJson(t as Map<String, dynamic>),
      ],
      stamps: [
        for (final s in j['stamps'] as List)
          WorkspacePlanStamp.fromJson(s as Map<String, dynamic>),
      ],
    );
  }
}

/// The whole export: output page order plus document-level ops.
class WorkspacePlan {
  const WorkspacePlan({
    required this.pages,
    this.compress,
    this.splitEvery = 0,
    required this.name,
  });

  /// Final output order.
  final List<WorkspacePlanPage> pages;
  final ({String method, int quality, int dpi})? compress;

  /// 0 = no split.
  final int splitEvery;

  /// Output base name, e.g. `quarterly-report.pdf`.
  final String name;

  Map<String, dynamic> toJson() => {
    'pages': [for (final p in pages) p.toJson()],
    'compress': compress == null
        ? null
        : {
            'method': compress!.method,
            'quality': compress!.quality,
            'dpi': compress!.dpi,
          },
    'splitEvery': splitEvery,
    'name': name,
  };

  factory WorkspacePlan.fromJson(Map<String, dynamic> j) {
    final c = j['compress'] as Map<String, dynamic>?;
    return WorkspacePlan(
      pages: [
        for (final p in j['pages'] as List)
          WorkspacePlanPage.fromJson(p as Map<String, dynamic>),
      ],
      compress: c == null
          ? null
          : (
              method: c['method'] as String,
              quality: c['quality'] as int,
              dpi: c['dpi'] as int,
            ),
      splitEvery: j['splitEvery'] as int,
      name: j['name'] as String,
    );
  }
}
