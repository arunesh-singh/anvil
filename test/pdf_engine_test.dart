import 'dart:convert';
import 'dart:typed_data';

import 'package:anvil/core/tool_io.dart';
import 'package:anvil/engines/pdf_engine.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart' show PdfRect;
import 'package:flutter_test/flutter_test.dart';

/// Best-effort integration test against the real Rust native asset. If the host
/// cannot load pdf_manipulator's native binary under `flutter test`, this file
/// fails to run — that is expected; rely on the registry/widget tests and the
/// APK build for the rest. It passes once host native assets resolve.
void main() {
  // 1×1 transparent PNG.
  final png = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
  ));
  // 8×8 solid-red PNG (the stamp decoder rejects the 1×1 above).
  final solidPng = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR42mO4IyKCFTEMLQkAmD9BAeEqE6gAAAAASUVORK5CYII=',
  ));

  late PdfEngine engine;
  late Uint8List twoPagePdf;

  setUp(() async {
    engine = PdfEngine();
    twoPagePdf = await engine.imagesToPdf([png, png]);
  });

  tearDown(() => engine.dispose());

  test('imagesToPdf builds a non-empty PDF', () {
    expect(twoPagePdf, isNotEmpty);
  });

  test('split chunks per page count', () async {
    expect(await engine.split(twoPagePdf, 1), hasLength(2));
    expect(await engine.split(twoPagePdf, 2), hasLength(1));
  });

  test('merge concatenates documents', () async {
    final merged = await engine.merge([twoPagePdf, twoPagePdf]);
    expect(await engine.split(merged, 1), hasLength(4));
  });

  test('rotateAll and compress return valid PDFs', () async {
    final rotated = await engine.rotateAll(twoPagePdf, 90);
    expect(await engine.split(rotated, 1), hasLength(2));
    final compressed = await engine.compress(twoPagePdf, 50);
    expect(compressed, isNotEmpty);
  });

  test('extractText returns a string', () async {
    expect(await engine.extractText(twoPagePdf), isA<String>());
  });

  test('extractImages throws when no embedded images are present', () async {
    expect(
      () => engine.extractImages(twoPagePdf),
      throwsA(isA<ToolException>()),
    );
  });

  test('renderToPng yields one PNG per page', () async {
    final pages = await engine.renderToPng(twoPagePdf);
    expect(pages, hasLength(2));
    expect(pages.every((p) => p.ext == 'png'), isTrue);
    // PNG magic header on the produced bytes.
    expect(pages.first.bytes.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
  });

  test('pageCount reports pages', () async {
    expect(await engine.pageCount(twoPagePdf), 2);
  });

  test('pageInfos returns one sized info per page', () async {
    final infos = await engine.pageInfos(twoPagePdf);
    expect(infos, hasLength(2));
    expect(infos.every((i) => i.width > 0 && i.height > 0), isTrue);
  });

  test('renderPage returns PNG bytes for a page', () async {
    final page = await engine.renderPage(twoPagePdf, 0);
    expect(page.bytes, isNotEmpty);
    expect(page.bytes.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
  });

  test('renderThumbnails yields one thumbnail per page', () async {
    final thumbs = await engine.renderThumbnails(twoPagePdf);
    expect(thumbs, hasLength(2));
    expect(thumbs.first.bytes, isNotEmpty);
  });

  test('protect then unlock round-trips', () async {
    final locked = await engine.protect(twoPagePdf, 'secret');
    expect(locked, isNotEmpty);
    // Without the password the engine refuses the document.
    expect(() => engine.pageCount(locked), throwsA(isA<ToolException>()));
    final unlocked = await engine.unlock(locked, 'secret');
    expect(await engine.pageCount(unlocked), 2);
  });

  test('watermark and addText keep the document readable', () async {
    final marked = await engine.watermark(twoPagePdf, 'CONFIDENTIAL');
    expect(await engine.pageCount(marked), 2);
    final texted = await engine.addText(twoPagePdf, 'hello',
        pageIndex: 0, x: 40, y: 40);
    expect(await engine.pageCount(texted), 2);
  });

  test('deletePages and reorderPages change page structure', () async {
    final one = await engine.deletePages(twoPagePdf, [1]);
    expect(await engine.pageCount(one), 1);
    final swapped = await engine.reorderPages(twoPagePdf, [1, 0]);
    expect(await engine.pageCount(swapped), 2);
    final subset = await engine.reorderPages(twoPagePdf, [0]);
    expect(await engine.pageCount(subset), 1);
  });

  test('appendBlankPages grows the document', () async {
    final grown = await engine.appendBlankPages(twoPagePdf, 3);
    expect(await engine.pageCount(grown), 5);
  });

  test('createTextPdf builds a searchable document', () async {
    final doc = await engine.createTextPdf('First paragraph.\n\nSecond one.',
        title: 'My Doc');
    expect(await engine.pageCount(doc), greaterThanOrEqualTo(1));
    final text = await engine.extractText(doc);
    expect(text, contains('First paragraph.'));
  });

  test('cropMargins and eraseRegionAllPages return valid PDFs', () async {
    final cropped = await engine.cropMargins(twoPagePdf,
        left: 2, top: 2, right: 2, bottom: 2);
    expect(await engine.pageCount(cropped), 2);
    final erased = await engine.eraseRegionAllPages(
        twoPagePdf, const PdfRect(x: 0, y: 0, width: 10, height: 10));
    expect(await engine.pageCount(erased), 2);
  });

  test('createBlankPdf builds one page per size', () async {
    final doc = await engine.createBlankPdf([(w: 595.0, h: 842.0)]);
    expect(await engine.pageCount(doc), 1);
    final two =
        await engine.createBlankPdf([(w: 595.0, h: 842.0), (w: 612.0, h: 792.0)]);
    expect(await engine.pageCount(two), 2);
  });

  test('createBlankPdf rejects an empty page list', () async {
    expect(() => engine.createBlankPdf(const []),
        throwsA(isA<ToolException>()));
  });

  test('stampOverlays keeps the page count and returns a valid PDF', () async {
    final onePage = await engine.imagesToPdf([png]);
    final stamped =
        await engine.stampOverlays(onePage, [(page: 0, png: solidPng)]);
    expect(await engine.pageCount(stamped), 1);
    // Empty overlays are a no-op passthrough.
    final same = await engine.stampOverlays(onePage, const []);
    expect(await engine.pageCount(same), 1);
  });

  test('cropPerPage preserves page count and passes through all-null', () async {
    final cropped = await engine.cropPerPage(twoPagePdf, [
      (left: 10.0, top: 10.0, right: 10.0, bottom: 10.0),
      null,
    ]);
    expect(await engine.pageCount(cropped), 2);
    // All-null selection returns the input unchanged.
    final passthrough = await engine.cropPerPage(twoPagePdf, [null, null]);
    expect(passthrough, equals(twoPagePdf));
  });

  test('cropPerPage rejects a mismatched selection length', () async {
    expect(
      () => engine.cropPerPage(twoPagePdf, [null]),
      throwsA(isA<ToolException>()),
    );
  });
}
