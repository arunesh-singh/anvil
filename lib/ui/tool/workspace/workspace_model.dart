/// Pure model of the PDF workspace: pending edits, the fold that replays them
/// into a document view, the review-row copy, the size estimate and the
/// mapping to the export [WorkspacePlan]. No widgets, no engines — undo of any
/// row is "drop it and replay from scratch", so this file IS the semantics and
/// is host-testable.
library;

import 'dart:ui' show Offset, Rect;

import 'package:anvil/tools/pdf/pdf_workspace_plan.dart';

/// Stable identity of a page across edits: (source file index, 0-based page).
typedef PageRef = ({int source, int page});

/// One pending edit. Identity matters (Review undoes a specific instance), so
/// no subclass defines `==`.
sealed class PdfEdit {
  const PdfEdit();
}

/// Merge: appends every page of source [source].
final class AddSourceEdit extends PdfEdit {
  AddSourceEdit(this.source);
  final int source;
}

/// Full page-order snapshot taken when the user applied a reorder.
final class ReorderEdit extends PdfEdit {
  ReorderEdit(this.order);
  final List<PageRef> order;
}

/// [labels] on the page-scoped edits are the 1-based positions of the affected
/// pages at the time the edit was made (row text only).
final class DeleteEdit extends PdfEdit {
  DeleteEdit({required this.pages, required this.labels, required this.before});
  final Set<PageRef> pages;
  final List<int> labels;

  /// Alive page count before the delete.
  final int before;
}

/// +90° clockwise on each page.
final class RotateEdit extends PdfEdit {
  RotateEdit({required this.pages, required this.labels});
  final Set<PageRef> pages;
  final List<int> labels;
}

final class TextEdit extends PdfEdit {
  TextEdit({
    required this.pages,
    required this.labels,
    required this.all,
    required this.text,
    required this.family,
    required this.bold,
    required this.italic,
    required this.size,
    required this.color,
    required this.anchor,
  });
  final Set<PageRef> pages;
  final List<int> labels;
  final bool all;
  final String text, family;
  final bool bold, italic;

  /// Points.
  final double size;

  /// ARGB.
  final int color;

  /// Fraction of the unrotated page: dx from left, dy from TOP; the text's
  /// baseline-left corner.
  final Offset anchor;
}

final class SignEdit extends PdfEdit {
  SignEdit({
    required this.pages,
    required this.labels,
    required this.all,
    required this.imagePath,
    required this.rect,
  });
  final Set<PageRef> pages;
  final List<int> labels;
  final bool all;
  final String imagePath;

  /// Fractions of the unrotated page, top-left origin.
  final Rect rect;
}

final class CropEdit extends PdfEdit {
  CropEdit({
    required this.pages,
    required this.labels,
    required this.all,
    required this.rect,
  });
  final Set<PageRef> pages;
  final List<int> labels;
  final bool all;

  /// Kept area as fractions of the unrotated page, top-left origin.
  final Rect rect;
}

final class CompressEdit extends PdfEdit {
  CompressEdit({
    required this.method,
    required this.quality,
    required this.dpi,
    required this.measuredBytes,
    required this.measuredFrom,
    required this.measuredPages,
  });
  final String method;
  final int quality, dpi;

  /// Measured output size, the input size it came from, and the page count
  /// of that input.
  final int measuredBytes, measuredFrom, measuredPages;
}

final class SplitEdit extends PdfEdit {
  SplitEdit(this.every);
  final int every;
}

/// One opened PDF.
class WorkspaceSource {
  const WorkspaceSource({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.pagesPt,
  });
  final String path, name;
  final int sizeBytes;

  /// Unrotated page sizes in points.
  final List<({double w, double h})> pagesPt;
}

/// The result of folding the edits over the opened sources.
class WorkspaceDoc {
  const WorkspaceDoc({
    required this.order,
    required this.rotation,
    required this.crop,
    required this.cropFrom,
    required this.texts,
    required this.signs,
    this.compress,
    this.split,
  });

  /// Alive pages, display/output order.
  final List<PageRef> order;

  /// 0 | 90 | 180 | 270; absent = 0.
  final Map<PageRef, int> rotation;

  /// Last [CropEdit] rect covering the page.
  final Map<PageRef, Rect> crop;

  /// Which edit set [crop] (for "overridden").
  final Map<PageRef, CropEdit> cropFrom;
  final Map<PageRef, List<TextEdit>> texts;
  final Map<PageRef, List<SignEdit>> signs;
  final CompressEdit? compress;
  final SplitEdit? split;

  /// 1-based position of [p] in [order], or 0 when it is not alive.
  int labelOf(PageRef p) => order.indexOf(p) + 1;

  /// Sorted 1-based positions of the alive pages among [refs].
  List<int> labelsOf(Iterable<PageRef> refs) {
    final want = refs.toSet();
    return [
      for (var i = 0; i < order.length; i++)
        if (want.contains(order[i])) i + 1,
    ];
  }
}

/// Replays [edits] over the pages of the first [seedSources] sources (files
/// opened together are seeds, not edits). Edits that only touch dead pages
/// are no-ops, so undoing any row is "remove it and fold again".
WorkspaceDoc foldEdits(
  List<WorkspaceSource> sources,
  int seedSources,
  List<PdfEdit> edits,
) {
  List<PageRef> pagesOf(int s) => [
    for (var p = 0; p < sources[s].pagesPt.length; p++) (source: s, page: p),
  ];
  final order = <PageRef>[
    for (var s = 0; s < seedSources && s < sources.length; s++) ...pagesOf(s),
  ];
  final rotation = <PageRef, int>{};
  final crop = <PageRef, Rect>{};
  final cropFrom = <PageRef, CropEdit>{};
  final texts = <PageRef, List<TextEdit>>{};
  final signs = <PageRef, List<SignEdit>>{};
  CompressEdit? compress;
  SplitEdit? split;

  Iterable<PageRef> alive(Set<PageRef> pages) {
    final live = order.toSet();
    return pages.where(live.contains);
  }

  for (final e in edits) {
    switch (e) {
      case AddSourceEdit(:final source):
        if (source < sources.length) {
          final live = order.toSet();
          order.addAll(pagesOf(source).where((p) => !live.contains(p)));
        }
      case ReorderEdit(order: final snapshot):
        final live = order.toSet();
        final next = <PageRef>[];
        final seen = <PageRef>{};
        for (final p in snapshot) {
          if (live.contains(p) && seen.add(p)) next.add(p);
        }
        next.addAll(order.where((p) => !seen.contains(p)));
        order
          ..clear()
          ..addAll(next);
      case DeleteEdit(:final pages):
        order.removeWhere(pages.contains);
        for (final m in <Map<PageRef, Object>>[
          rotation,
          crop,
          cropFrom,
          texts,
          signs,
        ]) {
          m.removeWhere((k, _) => pages.contains(k));
        }
      case RotateEdit(:final pages):
        for (final p in alive(pages)) {
          rotation[p] = ((rotation[p] ?? 0) + 90) % 360;
        }
      case TextEdit(:final pages):
        for (final p in alive(pages)) {
          (texts[p] ??= []).add(e);
        }
      case SignEdit(:final pages):
        for (final p in alive(pages)) {
          (signs[p] ??= []).add(e);
        }
      case CropEdit(:final pages, :final rect):
        for (final p in alive(pages)) {
          crop[p] = rect;
          cropFrom[p] = e;
        }
      case CompressEdit():
        compress = e;
      case SplitEdit():
        split = e;
    }
  }
  return WorkspaceDoc(
    order: order,
    rotation: rotation,
    crop: crop,
    cropFrom: cropFrom,
    texts: texts,
    signs: signs,
    compress: compress,
    split: split,
  );
}

/// Sorted, de-duplicated, runs collapsed: `[2,4,5,6]` → `'2, 4-6'`.
String formatPageList(List<int> oneBased) {
  final xs = oneBased.toSet().toList()..sort();
  final parts = <String>[];
  var i = 0;
  while (i < xs.length) {
    var j = i;
    while (j + 1 < xs.length && xs[j + 1] == xs[j] + 1) {
      j++;
    }
    parts.add(j == i ? '${xs[i]}' : '${xs[i]}-${xs[j]}');
    i = j + 1;
  }
  return parts.join(', ');
}

/// `'1 page'` / `'$n pages'`.
String pageCountLabel(int n) => n == 1 ? '1 page' : '$n pages';

/// Where a page-scoped sheet applies its edit.
enum ScopeChoice { page, selection, all }

/// Resolves a [ScopeChoice] to the pages (in document order) and the `all`
/// flag the edits store. An empty selection falls back to [page].
({Set<PageRef> pages, bool all}) resolveScope(
  ScopeChoice choice,
  WorkspaceDoc d,
  PageRef page,
  Set<PageRef> selection,
) {
  switch (choice) {
    case ScopeChoice.all:
      return (pages: {...d.order}, all: true);
    case ScopeChoice.selection when selection.isNotEmpty:
      return (
        pages: {
          for (final p in d.order)
            if (selection.contains(p)) p,
        },
        all: false,
      );
    case ScopeChoice.selection:
    case ScopeChoice.page:
      return (pages: {page}, all: false);
  }
}

/// `'A4'`, `'Letter'` or `'Legal'` (either orientation, ±2pt), else null.
String? pageSizeName(double w, double h) {
  bool near(double a, double b) => (a - b).abs() <= 2;
  bool isSize(double sw, double sh) =>
      (near(w, sw) && near(h, sh)) || (near(w, sh) && near(h, sw));
  if (isSize(595, 842)) return 'A4';
  if (isSize(612, 792)) return 'Letter';
  if (isSize(612, 1008)) return 'Legal';
  return null;
}

/// Unrotated point size of [p].
({double w, double h}) pageSizeOf(List<WorkspaceSource> s, PageRef p) =>
    s[p.source].pagesPt[p.page];

/// Output size estimate: the last compress measurement (else the source
/// sizes) scaled by the alive page share.
int estimateBytes(
  List<WorkspaceSource> s,
  WorkspaceDoc d, {
  Set<PageRef>? only,
}) {
  final base =
      d.compress?.measuredBytes ?? s.fold<int>(0, (a, x) => a + x.sizeBytes);
  final basePages =
      d.compress?.measuredPages ??
      s.fold<int>(0, (a, x) => a + x.pagesPt.length);
  if (basePages == 0) return 0;
  final pages = only == null
      ? d.order.length
      : d.order.where(only.contains).length;
  return (base * pages / basePages).round();
}

/// Number of files a split every [every] pages produces from [alive] pages.
int splitFileCount(int alive, int every) =>
    every <= 0 ? 1 : (alive + every - 1) ~/ every;

String _scopeSub(bool all, List<int> labels) => all
    ? 'all pages'
    : labels.length == 1
    ? 'page ${labels.single}'
    : 'pages ${formatPageList(labels)}';

String _pt(double v) => v.round().toString();

/// Review-row copy for [e]. `icon` is a Material icon NAME (the UI maps it),
/// keeping this file widget-free. [alive] is the current alive page count
/// (split rows report the resulting file count).
({String icon, String title, String? sub}) describeEdit(
  PdfEdit e,
  List<WorkspaceSource> s,
  String Function(int bytes) fmtBytes, {
  required int alive,
}) {
  switch (e) {
    case AddSourceEdit(:final source):
      final src = s[source];
      return (
        icon: 'add',
        title: 'Added ${src.name}',
        sub: '+${pageCountLabel(src.pagesPt.length)}',
      );
    case ReorderEdit(:final order):
      return (
        icon: 'reorder',
        title: 'Reordered pages',
        sub: pageCountLabel(order.length),
      );
    case DeleteEdit(:final labels, :final before, :final pages):
      return (
        icon: 'delete',
        title: labels.length == 1
            ? 'Deleted page ${labels.single}'
            : 'Deleted pages ${formatPageList(labels)}',
        sub: '$before → ${pageCountLabel(before - pages.length)}',
      );
    case RotateEdit(:final labels):
      return (
        icon: 'rotate_right',
        title: labels.length == 1
            ? 'Rotated page ${labels.single} 90° clockwise'
            : 'Rotated pages ${formatPageList(labels)} 90° clockwise',
        sub: null,
      );
    case TextEdit(:final text, :final all, :final labels):
      final shown = text.length > 24 ? '${text.substring(0, 24)}…' : text;
      return (
        icon: 'title',
        title: 'Added text “$shown”',
        sub: _scopeSub(all, labels),
      );
    case SignEdit(:final all, :final labels):
      return (
        icon: 'gesture',
        title: 'Placed signature',
        sub: _scopeSub(all, labels),
      );
    case CropEdit(:final all, :final labels, :final pages, :final rect):
      final first = pages.isEmpty ? null : pageSizeOf(s, pages.first);
      return (
        icon: 'crop',
        title: all
            ? 'Cropped all pages'
            : labels.length == 1
            ? 'Cropped page ${labels.single}'
            : 'Cropped pages ${formatPageList(labels)}',
        sub: first == null
            ? null
            : '${_pt(first.w)}×${_pt(first.h)}pt → '
                  '${_pt(rect.width * first.w)}×${_pt(rect.height * first.h)}pt',
      );
    case CompressEdit(
      :final method,
      :final quality,
      :final dpi,
      :final measuredFrom,
      :final measuredBytes,
    ):
      return (
        icon: 'compress',
        title: method == 'raster'
            ? 'Compressed · raster, q$quality, $dpi dpi'
            : 'Compressed · optimize, q$quality',
        sub: '${fmtBytes(measuredFrom)} → ${fmtBytes(measuredBytes)}',
      );
    case SplitEdit(:final every):
      return (
        icon: 'call_split',
        title: 'Split every ${pageCountLabel(every)}',
        sub: '→ ${splitFileCount(alive, every)} files',
      );
  }
}

String _hexRgb(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Resolves the folded document into an export plan. [imageIndex] maps each
/// signature image path to its `ToolInput.files` index; [only] restricts the
/// output to those pages (Extract), keeping order and skipping the split.
WorkspacePlan buildPlan(
  List<WorkspaceSource> s,
  WorkspaceDoc d, {
  required Map<String, int> imageIndex,
  Set<PageRef>? only,
}) {
  final refs = only == null ? d.order : d.order.where(only.contains).toList();
  final c = d.compress;
  return WorkspacePlan(
    name: s.first.name,
    splitEvery: only == null ? (d.split?.every ?? 0) : 0,
    compress: c == null
        ? null
        : (method: c.method, quality: c.quality, dpi: c.dpi),
    pages: [
      for (final ref in refs)
        () {
          final size = pageSizeOf(s, ref);
          final w = size.w, h = size.h;
          final f = d.crop[ref];
          return WorkspacePlanPage(
            source: ref.source,
            page: ref.page,
            rotate: d.rotation[ref] ?? 0,
            crop: f == null
                ? null
                : (
                    l: f.left * w,
                    t: f.top * h,
                    r: (1 - f.right) * w,
                    b: (1 - f.bottom) * h,
                  ),
            texts: [
              for (final t in d.texts[ref] ?? const <TextEdit>[])
                WorkspacePlanText(
                  text: t.text,
                  family: t.family,
                  bold: t.bold,
                  italic: t.italic,
                  size: t.size,
                  x: t.anchor.dx * w,
                  y: h - t.anchor.dy * h,
                  color: _hexRgb(t.color),
                ),
            ],
            stamps: [
              for (final g in d.signs[ref] ?? const <SignEdit>[])
                WorkspacePlanStamp(
                  image: imageIndex[g.imagePath]!,
                  x: g.rect.left * w,
                  y: h - g.rect.bottom * h,
                  width: g.rect.width * w,
                  height: g.rect.height * h,
                ),
            ],
          );
        }(),
    ],
  );
}
