/// State and actions of the PDF workspace: the opened sources, their
/// thumbnails, the pending edit stack, the page selection and the caches the
/// sheets render from. Edits are only data until Export — the single
/// `pdf/workspace` run built by [PdfWorkspaceController.exportInput].
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:anvil/core/di.dart';
import 'package:anvil/core/file_service.dart';
import 'package:anvil/core/tool_io.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:anvil/ui/tool/editors/pdf_overlay_painter.dart';
import 'package:anvil/ui/tool/workspace/workspace_model.dart';

const _keep = Object();

/// Immutable workspace snapshot.
class PdfWorkspaceState {
  PdfWorkspaceState({
    this.sources = const [],
    this.seedSources = 0,
    this.files = const [],
    this.thumbs = const {},
    this.edits = const [],
    this.selection = const {},
    this.focused,
    this.lastSignRect,
    this.loading = false,
    this.error,
    this.exportedEdits,
    this._doc,
  });

  final List<WorkspaceSource> sources;
  final int seedSources;

  /// Parallel to [sources].
  final List<InputFile> files;
  final Map<PageRef, Uint8List> thumbs;
  final List<PdfEdit> edits;
  final Set<PageRef> selection;
  final PageRef? focused;

  /// Where the sign sheet last placed a signature (fractions, top-left).
  final ui.Rect? lastSignRect;
  final bool loading;
  final String? error;

  /// The [edits] list that was last exported successfully; while it is still
  /// the current list there is nothing to lose by leaving.
  final List<PdfEdit>? exportedEdits;

  WorkspaceDoc? _doc;

  /// The folded document; computed once per edits/sources snapshot.
  WorkspaceDoc get doc => _doc ??= foldEdits(sources, seedSources, edits);

  bool get canExport => edits.isNotEmpty || sources.length > 1;

  /// True when leaving would discard work.
  bool get hasUnsaved => canExport && !identical(exportedEdits, edits);

  PdfWorkspaceState copyWith({
    List<WorkspaceSource>? sources,
    int? seedSources,
    List<InputFile>? files,
    Map<PageRef, Uint8List>? thumbs,
    List<PdfEdit>? edits,
    Set<PageRef>? selection,
    Object? focused = _keep,
    Object? lastSignRect = _keep,
    bool? loading,
    Object? error = _keep,
    Object? exportedEdits = _keep,
  }) {
    final sameDoc = sources == null && seedSources == null && edits == null;
    return PdfWorkspaceState(
      sources: sources ?? this.sources,
      seedSources: seedSources ?? this.seedSources,
      files: files ?? this.files,
      thumbs: thumbs ?? this.thumbs,
      edits: edits ?? this.edits,
      selection: selection ?? this.selection,
      focused: identical(focused, _keep) ? this.focused : focused as PageRef?,
      lastSignRect: identical(lastSignRect, _keep)
          ? this.lastSignRect
          : lastSignRect as ui.Rect?,
      loading: loading ?? this.loading,
      error: identical(error, _keep) ? this.error : error as String?,
      exportedEdits: identical(exportedEdits, _keep)
          ? this.exportedEdits
          : exportedEdits as List<PdfEdit>?,
      doc: sameDoc ? _doc : null,
    );
  }
}

final pdfWorkspaceProvider =
    NotifierProvider.autoDispose<PdfWorkspaceController, PdfWorkspaceState>(
      PdfWorkspaceController.new,
    );

class PdfWorkspaceController extends Notifier<PdfWorkspaceState> {
  final Map<int, Uint8List> _bytes = {};
  final Map<PageRef, Future<Uint8List>> _renders = {};
  final Map<PageRef, Future<ui.Image>> _thumbImages = {};
  final Map<String, Future<ui.Image>> _fileImages = {};
  Future<Uint8List>? _base;

  @override
  PdfWorkspaceState build() {
    ref.onDispose(() {
      for (final f in [..._thumbImages.values, ..._fileImages.values]) {
        f.then((i) => i.dispose(), onError: (_) {});
      }
    });
    return PdfWorkspaceState();
  }

  PdfEngine get _engine => getIt<PdfEngine>();

  Future<
    ({WorkspaceSource source, Map<PageRef, Uint8List> thumbs, Uint8List bytes})
  >
  _load(InputFile f, int index) async {
    final raw = await getIt<FileService>().readBytes(f.path);
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    final infos = await _engine.pageInfos(bytes);
    final thumbs = await _engine.renderThumbnails(bytes);
    return (
      source: WorkspaceSource(
        path: f.path,
        name: f.name,
        sizeBytes: bytes.length,
        pagesPt: [for (final i in infos) (w: i.width, h: i.height)],
      ),
      thumbs: {
        for (var j = 0; j < thumbs.length; j++)
          (source: index, page: j): thumbs[j].bytes,
      },
      bytes: bytes,
    );
  }

  /// Opens [files] as the document (all of them are seeds, not edits).
  Future<void> open(List<InputFile> files) async {
    if (files.isEmpty) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final loaded = [
        for (var i = 0; i < files.length; i++) await _load(files[i], i),
      ];
      _bytes
        ..clear()
        ..addAll({for (var i = 0; i < loaded.length; i++) i: loaded[i].bytes});
      _renders.clear();
      _thumbImages.clear();
      _base = null;
      state = PdfWorkspaceState(
        sources: [for (final l in loaded) l.source],
        seedSources: loaded.length,
        files: files,
        thumbs: {for (final l in loaded) ...l.thumbs},
        edits: <PdfEdit>[],
        lastSignRect: state.lastSignRect,
      );
    } on ToolException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    }
  }

  /// Merge: appends [files] as new sources, one [AddSourceEdit] each.
  Future<void> addSources(List<InputFile> files) async {
    if (files.isEmpty) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final start = state.sources.length;
      final loaded = [
        for (var i = 0; i < files.length; i++) await _load(files[i], start + i),
      ];
      for (var i = 0; i < loaded.length; i++) {
        _bytes[start + i] = loaded[i].bytes;
      }
      _base = null;
      state = state.copyWith(
        loading: false,
        sources: [...state.sources, for (final l in loaded) l.source],
        files: [...state.files, ...files],
        thumbs: {...state.thumbs, for (final l in loaded) ...l.thumbs},
        edits: [
          ...state.edits,
          for (var i = 0; i < loaded.length; i++) AddSourceEdit(start + i),
        ],
      );
    } on ToolException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    }
  }

  void clearError() => state = state.copyWith(error: null);

  void toggleSelect(PageRef p) {
    final next = {...state.selection};
    if (!next.remove(p)) next.add(p);
    state = state.copyWith(selection: next, focused: p);
  }

  void selectAll() => state = state.copyWith(selection: {...state.doc.order});

  void clearSelection() => state = state.copyWith(selection: <PageRef>{});

  void focus(PageRef p) => state = state.copyWith(focused: p);

  void setLastSignRect(ui.Rect r) => state = state.copyWith(lastSignRect: r);

  /// The selection in document order (stable for edit labels/"first page").
  Set<PageRef> _orderedSelection() {
    final sel = state.selection;
    return {
      for (final p in state.doc.order)
        if (sel.contains(p)) p,
    };
  }

  void deleteSelection() {
    final pages = _orderedSelection();
    if (pages.isEmpty) return;
    final doc = state.doc;
    if (pages.length >= doc.order.length) {
      state = state.copyWith(error: 'Cannot delete every page of the PDF.');
      return;
    }
    _setEdits([
      ...state.edits,
      DeleteEdit(
        pages: pages,
        labels: doc.labelsOf(pages),
        before: doc.order.length,
      ),
    ], selection: <PageRef>{});
  }

  void rotateSelection() {
    final pages = _orderedSelection();
    if (pages.isEmpty) return;
    addEdit(RotateEdit(pages: pages, labels: state.doc.labelsOf(pages)));
  }

  void addEdit(PdfEdit e) => _setEdits([...state.edits, e]);

  /// For [CompressEdit]/[SplitEdit]: replaces the existing edit of that type
  /// in place (one row per document-level op), else appends.
  void replaceSingleton(PdfEdit e) {
    final edits = [...state.edits];
    final i = edits.indexWhere((x) => x.runtimeType == e.runtimeType);
    if (i < 0) {
      edits.add(e);
    } else {
      edits[i] = e;
    }
    _setEdits(edits);
  }

  void undoLast() {
    if (state.edits.isEmpty) return;
    _setEdits([...state.edits]..removeLast());
  }

  void removeEdit(PdfEdit e) =>
      _setEdits([...state.edits]..removeWhere((x) => identical(x, e)));

  /// Records a successful export of the current edits.
  void markExported() => state = state.copyWith(exportedEdits: state.edits);

  void _setEdits(List<PdfEdit> edits, {Set<PageRef>? selection}) {
    final next = state.copyWith(edits: edits);
    final alive = next.doc.order.toSet();
    final focused = next.focused;
    state = next.copyWith(
      selection: (selection ?? next.selection).where(alive.contains).toSet(),
      focused: focused != null && alive.contains(focused) ? focused : null,
    );
  }

  /// Full-size render of one page of its source (unrotated, uncropped).
  Future<Uint8List> pageRender(PageRef p) => _renders[p] ??= _engine
      .renderPage(_bytes[p.source]!, p.page, maxWidth: 1200, maxHeight: 1200)
      .then((r) => r.bytes)
      .catchError((Object e) {
        _renders.remove(p);
        throw e;
      });

  /// Decoded thumbnail for painting; null when the page has no thumbnail.
  Future<ui.Image>? thumbImage(PageRef p) {
    final bytes = state.thumbs[p];
    if (bytes == null) return null;
    return _thumbImages[p] ??= decodeImage(bytes);
  }

  /// Decoded image file (signatures) for painting.
  Future<ui.Image> fileImage(String path) =>
      _fileImages[path] ??= getIt<FileService>()
          .readBytes(path)
          .then((b) => decodeImage(b is Uint8List ? b : Uint8List.fromList(b)));

  /// All sources as one document, in source index order (what the compress
  /// preview measures). Pair with [globalIndex].
  Future<Uint8List> baseBytes() {
    final n = state.sources.length;
    if (n == 1) return Future.value(_bytes[0]!);
    return _base ??= _engine.merge([for (var i = 0; i < n; i++) _bytes[i]!]);
  }

  /// Index of [p] inside [baseBytes].
  int globalIndex(PageRef p) {
    var offset = 0;
    for (var s = 0; s < p.source; s++) {
      offset += state.sources[s].pagesPt.length;
    }
    return offset + p.page;
  }

  /// The single `pdf/workspace` run: source files, then each signature image
  /// used by the exported pages. [only] = Extract those pages.
  ToolInput exportInput({Set<PageRef>? only}) {
    final s = state;
    final doc = s.doc;
    final files = [...s.files];
    final imageIndex = <String, int>{};
    for (final ref in doc.order) {
      if (only != null && !only.contains(ref)) continue;
      for (final g in doc.signs[ref] ?? const <SignEdit>[]) {
        if (imageIndex.containsKey(g.imagePath)) continue;
        imageIndex[g.imagePath] = files.length;
        files.add(InputFile(path: g.imagePath, name: p.basename(g.imagePath)));
      }
    }
    final plan = buildPlan(s.sources, doc, imageIndex: imageIndex, only: only);
    return ToolInput(
      files: files,
      params: {'planJson': jsonEncode(plan.toJson())},
    );
  }
}
