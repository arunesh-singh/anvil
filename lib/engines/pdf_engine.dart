import 'dart:typed_data';

import 'package:pdf_manipulator/pdf_manipulator.dart';

import 'package:anvil/core/tool_io.dart';

/// One embedded or rendered image produced by the engine, with its file
/// extension and mime type so callers can write and label it directly.
class PdfImageOut {
  final Uint8List bytes;
  final String ext; // 'png', 'jpeg', …
  final String mime;
  const PdfImageOut(this.bytes, this.ext, this.mime);
}

/// Wraps `pdf_manipulator` — the single place the PDF plugin is touched, so a
/// future engine swap is one file. `pdf_manipulator` runs every op off the main
/// thread (Rust worker), so callers do NOT wrap these in `runOffThread`.
///
/// Every op funnels through [_guard], which converts the typed [PdfError]
/// hierarchy into user-facing [ToolException]s the job layer maps to a failed
/// UI state. Empty extraction/render results throw rather than yielding a
/// zero-file "success".
class PdfEngine {
  final Pdf _pdf = Pdf();

  /// Releases the Rust worker and cancels any in-flight tasks. Idempotent.
  Future<void> dispose() => _pdf.dispose();

  Future<Uint8List> merge(List<Uint8List> inputs) => _guard(() async {
    final out = MemorySink();
    await _pdf.merge([for (final b in inputs) MemorySource(b)], out);
    return out.takeBytes();
  });

  Future<List<Uint8List>> split(Uint8List input, int every) => _guard(() async {
    final sinks = <MemorySink>[];
    await _pdf.split(MemorySource(input), (i) {
      final s = MemorySink();
      sinks.add(s);
      return s;
    }, every: every);
    return [for (final s in sinks) s.takeBytes()];
  });

  Future<Uint8List> rotateAll(Uint8List input, int degrees) => _guard(() async {
    final out = MemorySink();
    await _pdf.rotateAllPages(MemorySource(input), out, degrees: degrees);
    return out.takeBytes();
  });

  /// Recompresses embedded images at [imageQuality] and rewrites the file
  /// with stream compression. Resolution is left alone (no downsampling) —
  /// the compress tool's raster mode is the aggressive path.
  Future<Uint8List> compress(Uint8List input, int imageQuality) =>
      _guard(() async {
        final out = MemorySink();
        await _pdf.compress(
          MemorySource(input),
          out,
          images: PdfImagePolicy(
            jpegQuality: imageQuality,
            convertCmykToRgb: true,
            recompressJpeg: true,
          ),
        );
        return out.takeBytes();
      });

  Future<String> extractText(Uint8List input) => _guard(() async {
    final doc = await _pdf.open(MemorySource(input));
    try {
      return await doc.extract(pages: const PdfPages.all());
    } finally {
      await doc.dispose();
    }
  });

  Future<List<PdfImageOut>> extractImages(Uint8List input) => _guard(() async {
    final doc = await _pdf.open(MemorySource(input));
    try {
      final out = <PdfImageOut>[];
      await for (final im in doc.extractImages(pages: const PdfPages.all())) {
        final ext = im.format.isEmpty ? 'img' : im.format.toLowerCase();
        out.add(PdfImageOut(im.data, ext, 'image/$ext'));
      }
      if (out.isEmpty) {
        throw const ToolException('No images found in this PDF.');
      }
      return out;
    } finally {
      await doc.dispose();
    }
  });

  Future<Uint8List> imagesToPdf(List<Uint8List> images) => _guard(() async {
    final out = MemorySink();
    await _pdf.imagesToPdf([for (final b in images) MemorySource(b)], out);
    return out.takeBytes();
  });

  /// Rasterizes each page. The Rust engine returns PNG-encoded bytes directly
  /// (the [RenderedPage.data] doc says "raw RGBA" but this engine emits PNG —
  /// verified by the PNG magic header), so no client-side encoding is needed.
  Future<List<PdfImageOut>> renderToPng(Uint8List input) => _guard(() async {
    final doc = await _pdf.open(MemorySource(input));
    try {
      final pages = <PdfImageOut>[];
      await for (final r in doc.render(
        pages: const PdfPages.all(),
        size: const PdfRenderSize(maxWidth: 2000, maxHeight: 2000),
      )) {
        pages.add(PdfImageOut(r.data, 'png', 'image/png'));
      }
      if (pages.isEmpty) {
        throw const ToolException('This PDF has no pages.');
      }
      return pages;
    } finally {
      await doc.dispose();
    }
  });

  /// Per-page metadata (dimensions in points, rotation), for coordinate
  /// mapping in the WYSIWYG editors. Read-only; opens and disposes the doc.
  Future<List<PdfPageInfo>> pageInfos(Uint8List input) => _guard(() async {
    final doc = await _pdf.open(MemorySource(input));
    try {
      return doc.pages;
    } finally {
      await doc.dispose();
    }
  });

  /// Renders one page (0-based) to PNG bytes for on-screen editing.
  Future<PdfImageOut> renderPage(Uint8List input, int pageIndex,
          {int maxWidth = 1600, int maxHeight = 1600}) =>
      _guard(() async {
        final doc = await _pdf.open(MemorySource(input));
        try {
          await for (final r in doc.render(
            pages: PdfPages.single(pageIndex),
            size: PdfRenderSize(maxWidth: maxWidth, maxHeight: maxHeight),
          )) {
            return PdfImageOut(r.data, 'png', 'image/png');
          }
          throw const ToolException('This PDF has no pages.');
        } finally {
          await doc.dispose();
        }
      });

  /// Renders every page small, for page-organizer thumbnails.
  Future<List<PdfImageOut>> renderThumbnails(Uint8List input,
          {int maxWidth = 320, int maxHeight = 320}) =>
      _guard(() async {
        final doc = await _pdf.open(MemorySource(input));
        try {
          final out = <PdfImageOut>[];
          await for (final r in doc.render(
            pages: const PdfPages.all(),
            size: PdfRenderSize(maxWidth: maxWidth, maxHeight: maxHeight),
          )) {
            out.add(PdfImageOut(r.data, 'png', 'image/png'));
          }
          if (out.isEmpty) throw const ToolException('This PDF has no pages.');
          return out;
        } finally {
          await doc.dispose();
        }
      });

  /// Number of pages, for page-indexed ops and validation.
  Future<int> pageCount(Uint8List input) => _guard(() async {
    final doc = await _pdf.open(MemorySource(input));
    try {
      return doc.pageCount;
    } finally {
      await doc.dispose();
    }
  });

  /// Encrypts with AES-256; [password] becomes both user and owner password.
  Future<Uint8List> protect(Uint8List input, String password) =>
      _guard(() async {
        final out = MemorySink();
        await _pdf.encrypt(
          MemorySource(input),
          out,
          encryption: PdfEncryptionConfig(
            ownerPassword: password,
            userPassword: password,
          ),
        );
        return out.takeBytes();
      });

  /// Removes encryption from a password-protected PDF.
  Future<Uint8List> unlock(Uint8List input, String password) =>
      _guard(() async {
        final out = MemorySink();
        await _pdf.decrypt(MemorySource(input), out, password: password);
        return out.takeBytes();
      });

  /// Diagonal tiled text watermark across every page.
  Future<Uint8List> watermark(Uint8List input, String text) =>
      _guard(() async {
        final out = MemorySink();
        await _pdf.watermark(
          MemorySource(input),
          out,
          text: text,
          position: const PdfWatermarkPosition.tiled(columns: 2, rows: 3),
        );
        return out.takeBytes();
      });

  /// Places [text] at exact page coordinates (points, origin bottom-left).
  /// [pageIndex] is 0-based; -1 targets every page.
  Future<Uint8List> addText(
    Uint8List input,
    String text, {
    required int pageIndex,
    required double x,
    required double y,
    double fontSize = 18,
    double opacity = 1,
    String? fontName,
    PdfColor color = PdfColor.black,
  }) => _guard(() async {
    final editor = await _pdf.edit(MemorySource(input));
    try {
      await editor.addWatermark(
        pageIndex,
        text,
        style: PdfWatermarkStyle(
            fontSize: fontSize,
            opacity: opacity,
            rotation: 0,
            fontName: fontName,
            color: color),
        position: PdfWatermarkPosition.exact(
            x: x, y: y, width: fontSize * text.length * 0.6, height: fontSize * 1.4),
      );
      final out = MemorySink();
      await editor.save(out);
      return out.takeBytes();
    } finally {
      await editor.dispose();
    }
  });

  /// Stamps [image] onto one page ([pageIndex] 0-based) at (x, y) points.
  Future<Uint8List> addImageStamp(
    Uint8List input,
    Uint8List image, {
    required int pageIndex,
    required double x,
    required double y,
    required double width,
    required double height,
    double opacity = 1,
  }) => _guard(() async {
    final out = MemorySink();
    await _pdf.addImageStamp(
      MemorySource(input),
      out,
      page: pageIndex,
      imageData: MemorySource(image),
      rect: PdfRect(x: x, y: y, width: width, height: height),
      opacity: opacity,
    );
    return out.takeBytes();
  });

  /// Deletes the given 0-based pages.
  Future<Uint8List> deletePages(Uint8List input, List<int> pages) =>
      _guard(() async {
        final out = MemorySink();
        await _pdf.deletePages(MemorySource(input), out, pages: pages);
        return out.takeBytes();
      });

  /// Reorders/subsets pages to [order] (0-based indices).
  Future<Uint8List> reorderPages(Uint8List input, List<int> order) =>
      _guard(() async {
        final out = MemorySink();
        await _pdf.reorderPages(MemorySource(input), out, order: order);
        return out.takeBytes();
      });

  /// Trims page margins by the given amounts (points).
  Future<Uint8List> cropMargins(
    Uint8List input, {
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) => _guard(() async {
    final editor = await _pdf.edit(MemorySource(input));
    try {
      await editor.cropMargins(
          left: left, top: top, right: right, bottom: bottom);
      final out = MemorySink();
      await editor.save(out);
      return out.takeBytes();
    } finally {
      await editor.dispose();
    }
  });

  /// Erases the same rectangular region on every page (e.g. a stamped
  /// watermark). Coordinates in points, origin bottom-left.
  Future<Uint8List> eraseRegionAllPages(Uint8List input, PdfRect rect) =>
      _guard(() async {
        final editor = await _pdf.edit(MemorySource(input));
        try {
          final pages = await editor.pageCount;
          for (var i = 0; i < pages; i++) {
            await editor.eraseRegions(i, [rect]);
          }
          final out = MemorySink();
          await editor.save(out);
          return out.takeBytes();
        } finally {
          await editor.dispose();
        }
      });

  /// Appends [count] blank A4 pages to the document.
  Future<Uint8List> appendBlankPages(Uint8List input, int count) =>
      _guard(() async {
        final builder = await _pdf.build();
        final blank = MemorySink();
        try {
          for (var i = 0; i < count; i++) {
            final page = await builder.addA4Page();
            await page.done();
          }
          await builder.save(blank);
        } finally {
          await builder.dispose();
        }
        return merge([input, blank.takeBytes()]);
      });

  /// Builds a new PDF from plain text (blank-line separated paragraphs).
  Future<Uint8List> createTextPdf(String text, {String? title}) =>
      _guard(() async {
        final builder = await _pdf.build();
        try {
          if (title != null && title.isNotEmpty) {
            await builder.setTitle(title);
          }
          final page = await builder.addA4Page();
          if (title != null && title.isNotEmpty) {
            await page.heading(1, title);
          }
          for (final para in text.split(RegExp(r'\n\s*\n'))) {
            if (para.trim().isEmpty) continue;
            await page.paragraph(para.trim());
          }
          await page.done();
          final out = MemorySink();
          await builder.save(out);
          return out.takeBytes();
        } finally {
          await builder.dispose();
        }
      });

  /// Builds a new PDF with one blank page per size (in points). An empty list
  /// throws — a document needs at least one page.
  Future<Uint8List> createBlankPdf(List<({double w, double h})> sizesPt) =>
      _guard(() async {
        if (sizesPt.isEmpty) {
          throw const ToolException('Add at least one page.');
        }
        final builder = await _pdf.build();
        try {
          for (final s in sizesPt) {
            final page = await builder.addPage(width: s.w, height: s.h);
            await page.done();
          }
          final out = MemorySink();
          await builder.save(out);
          return out.takeBytes();
        } finally {
          await builder.dispose();
        }
      });

  /// Stamps a full-page image [png] onto each listed page, sized to that page's
  /// media box, in a single editor round-trip. Empty [overlays] returns [pdf]
  /// unchanged. Used by the WYSIWYG editor to flatten placed elements.
  Future<Uint8List> stampOverlays(
    Uint8List pdf,
    List<({int page, Uint8List png})> overlays,
  ) => _guard(() async {
        if (overlays.isEmpty) return pdf;
        final editor = await _pdf.edit(MemorySource(pdf));
        try {
          for (final o in overlays) {
            final mb = await editor.pageMediaBox(o.page);
            await editor.addImageStamp(
              o.page,
              MemorySource(o.png),
              rect: PdfRect(
                  x: mb.x, y: mb.y, width: mb.width, height: mb.height),
              opacity: 1,
            );
          }
          final out = MemorySink();
          await editor.save(out);
          return out.takeBytes();
        } finally {
          await editor.dispose();
        }
      });

  /// Crops each page by its own margins. [perPage] length must equal the page
  /// count; a null entry leaves that page uncropped. Margins are in points.
  Future<Uint8List> cropPerPage(
    Uint8List pdf,
    List<({double left, double top, double right, double bottom})?> perPage,
  ) => _guard(() async {
        final pages = await split(pdf, 1);
        if (perPage.length != pages.length) {
          throw const ToolException('Page selection does not match the PDF.');
        }
        if (perPage.every((m) => m == null)) return pdf;
        for (var i = 0; i < pages.length; i++) {
          final m = perPage[i];
          if (m == null) continue;
          pages[i] = await cropMargins(pages[i],
              left: m.left, top: m.top, right: m.right, bottom: m.bottom);
        }
        return merge(pages);
      });

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on ToolException {
      rethrow;
    } on PdfPasswordRequired {
      throw const ToolException('This PDF is password-protected.');
    } on PdfCorrupted {
      throw const ToolException('This file is not a valid PDF.');
    } on PdfError catch (e) {
      throw ToolException(e.message);
    }
  }
}
