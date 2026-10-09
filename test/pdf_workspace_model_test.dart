/// Pure tests for the PDF workspace fold: undoing any row is "remove it and
/// replay", so these pin the replay semantics, the plan geometry mapping and
/// the estimate the Export pill shows.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:anvil/ui/tool/workspace/workspace_model.dart';

WorkspaceSource _src(String name, int pages, {int bytes = 1000}) =>
    WorkspaceSource(
      path: '/$name',
      name: name,
      sizeBytes: bytes,
      pagesPt: [for (var i = 0; i < pages; i++) (w: 595.0, h: 842.0)],
    );

PageRef _r(int s, int p) => (source: s, page: p);

void main() {
  test('undoing a delete restores the page and keeps a later rotation', () {
    final sources = [_src('a.pdf', 3)];
    final delete = DeleteEdit(pages: {_r(0, 1)}, labels: const [2], before: 3);
    final rotate = RotateEdit(pages: {_r(0, 2)}, labels: const [2]);
    final edits = <PdfEdit>[delete, rotate];

    final withDelete = foldEdits(sources, 1, edits);
    expect(withDelete.order, [_r(0, 0), _r(0, 2)]);
    expect(withDelete.rotation[_r(0, 2)], 90);

    final undone = foldEdits(sources, 1, edits..remove(delete));
    expect(undone.order, [_r(0, 0), _r(0, 1), _r(0, 2)]);
    expect(undone.rotation[_r(0, 2)], 90);
  });

  test('undoing an added source drops its pages from a later reorder', () {
    final sources = [_src('a.pdf', 2), _src('b.pdf', 2)];
    final add = AddSourceEdit(1);
    final reorder = ReorderEdit([_r(1, 0), _r(0, 0), _r(0, 1), _r(1, 1)]);
    final edits = <PdfEdit>[add, reorder];

    expect(foldEdits(sources, 1, edits).order.first, _r(1, 0));
    expect(foldEdits(sources, 1, edits..remove(add)).order, [
      _r(0, 0),
      _r(0, 1),
    ]);
  });

  test('buildPlan maps top-left fractions to bottom-left points', () {
    final sources = [_src('a.pdf', 1)];
    final doc = foldEdits(sources, 1, [
      TextEdit(
        pages: {_r(0, 0)},
        labels: const [1],
        all: true,
        text: 'Hi',
        family: 'Helvetica',
        bold: false,
        italic: false,
        size: 18,
        color: 0xFFE53935,
        anchor: const Offset(0.1, 0.12),
      ),
      CropEdit(
        pages: {_r(0, 0)},
        labels: const [1],
        all: true,
        rect: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
      ),
    ]);
    final page = buildPlan(sources, doc, imageIndex: const {}).pages.single;
    final t = page.texts.single;
    expect(t.x, closeTo(59.5, 1e-9));
    expect(t.y, closeTo(740.96, 1e-9));
    expect(t.color, '#E53935');
    final c = page.crop!;
    expect(c.l, closeTo(59.5, 1e-9));
    expect(c.t, closeTo(84.2, 1e-9));
    expect(c.r, closeTo(59.5, 1e-9));
    expect(c.b, closeTo(84.2, 1e-9));
  });

  test('page lists collapse runs', () {
    expect(formatPageList([2, 4, 5, 6]), '2, 4-6');
    expect(formatPageList([9, 4, 5, 6, 7, 8]), '4-9');
  });

  test('the estimate scales the compress measure by alive pages', () {
    final sources = [_src('a.pdf', 10, bytes: 4000000)];
    final edits = <PdfEdit>[
      CompressEdit(
        method: 'optimize',
        quality: 60,
        dpi: 150,
        measuredBytes: 1000000,
        measuredFrom: 4000000,
        measuredPages: 10,
      ),
      DeleteEdit(
        pages: {for (var p = 5; p < 10; p++) _r(0, p)},
        labels: const [6, 7, 8, 9, 10],
        before: 10,
      ),
    ];
    expect(estimateBytes(sources, foldEdits(sources, 1, edits)), 500000);
  });
}
